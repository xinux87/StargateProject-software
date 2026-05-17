"""
StargateBluetoothServer — BLE GATT server for the SG1 v4 Stargate replica.

Runs in a background daemon thread with its own asyncio event loop.
Uses the `bless` library (v0.2.0+). Import will fail gracefully when
bless is not installed; calling start() simply logs a warning.

UUIDs
-----
SERVICE_UUID  = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
CMD_UUID      = write + write_without_response   (client → gate)
RESPONSE_UUID = notify                            (gate → client, per-request reply)
STATUS_UUID   = notify + read                     (gate → client, pushed every 2 s)

Authentication
--------------
Every new connection starts unauthenticated.  Only the "auth" command
is accepted before the client supplies the correct PIN.  All other
commands are rejected with {"status": "unauthorized"}.

Chunking
--------
BLE notifications are limited to MTU-3 bytes (commonly 20 bytes without
negotiation).  To be safe, all outgoing notifications are sliced into
CHUNK_SIZE-byte payloads.  Each chunk is prefixed with one byte:
  - byte 0 in [0, 254]: sequential chunk index
  - byte 0 == 255      : final (or only) chunk
"""

import asyncio
import json
import logging
import threading

# ---------------------------------------------------------------------------
# Optional import — server is disabled when bless is not installed
# ---------------------------------------------------------------------------
try:
    from bless import (  # type: ignore
        BlessServer,
        GATTCharacteristicProperties,
        GATTAttributePermissions,
    )
    _BLESS_AVAILABLE = True
except ImportError:
    _BLESS_AVAILABLE = False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SERVICE_UUID  = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
CMD_UUID      = "a1b2c3d4-e5f6-7890-abcd-ef1234567891"
RESPONSE_UUID = "a1b2c3d4-e5f6-7890-abcd-ef1234567892"
STATUS_UUID   = "a1b2c3d4-e5f6-7890-abcd-ef1234567893"

CHUNK_SIZE          = 180   # max payload bytes per BLE notification
STATUS_INTERVAL     = 2.0   # seconds between status pushes
STOP_POLL_INTERVAL  = 0.25  # seconds between "are we done?" checks in _serve


class StargateBluetoothServer:
    """BLE GATT server that exposes gate state and accepts gate commands."""

    def __init__(
        self,
        stargate,
        command_handler,
        log,
        device_name: str = "Stargate",
        pin: str = "1969",
    ):
        """
        Parameters
        ----------
        stargate:        The live Stargate instance (attribute access only).
        command_handler: Object with a synchronous handle(cmd, params) method.
        log:             Project logger (must expose a .log(str) method).
        device_name:     BLE advertised device name.
        pin:             PIN required to authenticate a client connection.
        """
        self._stargate        = stargate
        self._command_handler = command_handler
        self._log             = log
        self._device_name     = device_name
        self._pin             = pin

        self._running: bool                     = False
        self._authenticated: bool               = False
        self._thread: threading.Thread | None   = None
        self._loop:   asyncio.AbstractEventLoop | None = None
        self._server: "BlessServer | None"      = None   # type annotation only

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Spawn the BLE server in a background daemon thread (non-blocking)."""
        if not _BLESS_AVAILABLE:
            self._log.log(
                "BluetoothServer: bless library not installed — "
                "BLE server will not start.  Install with: pip install bless"
            )
            return

        if self._running:
            self._log.log("BluetoothServer: already running, ignoring start()")
            return

        self._running = True
        self._thread = threading.Thread(
            target=self._run_loop, daemon=True, name="BLEServer"
        )
        self._thread.start()
        self._log.log(
            f"BluetoothServer: thread started (device='{self._device_name}')"
        )

    def stop(self) -> None:
        """Stop the BLE server and wait for the background thread to finish."""
        if not self._running:
            return

        self._log.log("BluetoothServer: stopping…")
        self._running = False

        # Ask the event loop to shut down the bless server and cancel tasks.
        if self._loop is not None and not self._loop.is_closed():
            self._loop.call_soon_threadsafe(self._loop.stop)

        if self._thread is not None and self._thread.is_alive():
            self._thread.join(timeout=6)

        self._log.log("BluetoothServer: stopped")

    def is_running(self) -> bool:
        """Return True while the server thread is alive."""
        return self._running and (
            self._thread is not None and self._thread.is_alive()
        )

    # ------------------------------------------------------------------
    # Thread entry point
    # ------------------------------------------------------------------

    def _run_loop(self) -> None:
        """Entry point for the daemon thread.  Owns its own event loop."""
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._serve())
        except Exception as exc:  # noqa: BLE001
            self._log.log(f"BluetoothServer: unexpected error in _run_loop: {exc}")
        finally:
            try:
                # Cancel all remaining tasks before closing.
                pending = asyncio.all_tasks(self._loop)
                for task in pending:
                    task.cancel()
                if pending:
                    self._loop.run_until_complete(
                        asyncio.gather(*pending, return_exceptions=True)
                    )
            except Exception:  # noqa: BLE001
                pass
            self._loop.close()
            self._running = False
            self._log.log("BluetoothServer: event loop closed")

    # ------------------------------------------------------------------
    # Async server logic
    # ------------------------------------------------------------------

    async def _serve(self) -> None:
        """Set up the GATT server, start advertising, and run until stopped."""
        try:
            self._server = BlessServer(
                name=self._device_name, loop=self._loop
            )
            self._server.read_request_func  = self._handle_read
            self._server.write_request_func = self._handle_write
        except Exception as exc:  # noqa: BLE001
            self._log.log(
                f"BluetoothServer: failed to create BlessServer "
                f"(is a Bluetooth adapter present?): {exc}"
            )
            self._running = False
            return

        # ---- Build the GATT service and characteristics ----
        try:
            await self._server.add_new_service(SERVICE_UUID)

            # CMD — writable by the client
            await self._server.add_new_characteristic(
                SERVICE_UUID,
                CMD_UUID,
                GATTCharacteristicProperties.write
                | GATTCharacteristicProperties.write_without_response,
                None,
                GATTAttributePermissions.writeable,
            )

            # RESPONSE — notify only (gate replies to client commands)
            await self._server.add_new_characteristic(
                SERVICE_UUID,
                RESPONSE_UUID,
                GATTCharacteristicProperties.notify,
                None,
                GATTAttributePermissions.readable,
            )

            # STATUS — notify + read (gate pushes state every 2 s)
            await self._server.add_new_characteristic(
                SERVICE_UUID,
                STATUS_UUID,
                GATTCharacteristicProperties.notify
                | GATTCharacteristicProperties.read,
                None,
                GATTAttributePermissions.readable,
            )
        except Exception as exc:  # noqa: BLE001
            self._log.log(
                f"BluetoothServer: failed to register GATT characteristics: {exc}"
            )
            self._running = False
            return

        # ---- Start advertising ----
        try:
            await self._server.start()
            self._log.log(
                f"BluetoothServer: advertising as '{self._device_name}' "
                f"on service {SERVICE_UUID}"
            )
        except Exception as exc:  # noqa: BLE001
            self._log.log(
                f"BluetoothServer: failed to start advertising "
                f"(Bluetooth adapter unavailable?): {exc}"
            )
            self._running = False
            return

        # ---- Background status pusher ----
        status_task = asyncio.ensure_future(self._status_loop())

        # ---- Main keep-alive loop ----
        try:
            while self._running:
                await asyncio.sleep(STOP_POLL_INTERVAL)
        finally:
            status_task.cancel()
            try:
                await status_task
            except asyncio.CancelledError:
                pass
            try:
                await self._server.stop()
            except Exception:  # noqa: BLE001
                pass
            self._log.log("BluetoothServer: advertising stopped")

    # ------------------------------------------------------------------
    # Status loop
    # ------------------------------------------------------------------

    async def _status_loop(self) -> None:
        """Push a STATUS notification every STATUS_INTERVAL seconds."""
        while self._running:
            try:
                await self._push_status()
            except Exception as exc:  # noqa: BLE001
                self._log.log(f"BluetoothServer: error in _status_loop: {exc}")
            await asyncio.sleep(STATUS_INTERVAL)

    async def _push_status(self) -> None:
        """Build and notify the current gate status on STATUS_UUID."""
        payload = self._build_status_payload()
        await self._notify(STATUS_UUID, payload)

    def _build_status_payload(self) -> dict:
        """Read live Stargate attributes and return a serialisable dict."""
        sg = self._stargate

        # wormhole_active is False, 'outgoing', or 'incoming'
        wormhole_active = bool(sg.wormhole_active)

        lamp_color = sg.lamp_color
        if isinstance(lamp_color, tuple):
            lamp_color = list(lamp_color)

        return {
            "wormhole_active": wormhole_active,
            "lamp_mode":       sg.lamp_mode,
            "lamp_color":      lamp_color,
            "lamp_brightness": sg.lamp_brightness,
            "lamp_animation":  sg.lamp_animation,
            "dialing":         bool(sg.address_buffer_outgoing),
            "locked_chevrons": sg.locked_chevrons_outgoing,
        }

    # ------------------------------------------------------------------
    # GATT callback — reads
    # ------------------------------------------------------------------

    def _handle_read(self, characteristic, **kwargs) -> bytearray:
        """Return the current value stored on a readable characteristic."""
        char_uuid = str(characteristic.uuid).lower()
        if char_uuid == STATUS_UUID.lower():
            data = json.dumps(self._build_status_payload()).encode("utf-8")
            return bytearray(data)
        return bytearray()

    # ------------------------------------------------------------------
    # GATT callback — writes (client → gate)
    # ------------------------------------------------------------------

    def _handle_write(self, characteristic, value: bytearray, **kwargs) -> None:
        """
        Called by bless on the event-loop thread when the client writes to
        CMD_UUID.  Parse the JSON and dispatch to _process_command.
        """
        char_uuid = str(characteristic.uuid).lower()
        if char_uuid != CMD_UUID.lower():
            return

        raw = bytes(value).decode("utf-8", errors="replace").strip()
        try:
            message = json.loads(raw)
        except json.JSONDecodeError as exc:
            self._log.log(
                f"BluetoothServer: received non-JSON write: {raw!r} ({exc})"
            )
            asyncio.run_coroutine_threadsafe(
                self._send_response(
                    {"status": "error", "message": f"Invalid JSON: {exc}"}
                ),
                self._loop,
            )
            return

        cmd    = message.get("cmd", "")
        params = message.get("params", {})
        req_id = message.get("id", None)

        # Schedule command processing on the event loop (thread-safe)
        asyncio.run_coroutine_threadsafe(
            self._process_command(cmd, params, req_id),
            self._loop,
        )

    # ------------------------------------------------------------------
    # Command dispatch
    # ------------------------------------------------------------------

    async def _process_command(
        self, cmd: str, params: dict, req_id
    ) -> None:
        """Authenticate, dispatch to command_handler, and send reply."""
        # Authentication gate
        if cmd == "auth":
            await self._handle_auth(params, req_id)
            return

        if not self._authenticated:
            await self._send_response(
                {
                    "id":      req_id,
                    "status":  "unauthorized",
                    "message": "Please authenticate first",
                }
            )
            return

        # Dispatch to the project's command handler (synchronous call).
        # handle() already returns {'status': ..., 'data': ...} — just inject id.
        try:
            result = self._command_handler.handle(cmd, params)
            if result is None:
                result = {"status": "ok"}
            result["id"] = req_id
            await self._send_response(result)
        except Exception as exc:  # noqa: BLE001
            self._log.log(
                f"BluetoothServer: command_handler.handle raised: {exc}"
            )
            await self._send_response(
                {
                    "id":      req_id,
                    "status":  "error",
                    "message": str(exc),
                }
            )

    async def _handle_auth(self, params: dict, req_id) -> None:
        """Verify PIN and update authentication state."""
        supplied_pin = str(params.get("pin", ""))
        if supplied_pin == self._pin:
            self._authenticated = True
            self._log.log("BluetoothServer: client authenticated successfully")
            await self._send_response(
                {"id": req_id, "status": "ok", "data": {"authenticated": True}}
            )
        else:
            self._authenticated = False
            self._log.log(
                "BluetoothServer: client supplied wrong PIN — rejected"
            )
            await self._send_response(
                {
                    "id":      req_id,
                    "status":  "unauthorized",
                    "message": "Wrong PIN",
                }
            )

    # ------------------------------------------------------------------
    # Notification helpers
    # ------------------------------------------------------------------

    async def _send_response(self, payload: dict) -> None:
        """Serialise payload and notify on RESPONSE_UUID."""
        await self._notify(RESPONSE_UUID, payload)

    async def _notify(self, char_uuid: str, payload: dict) -> None:
        """
        JSON-encode payload, chunk it, and call server.update_value() for
        each chunk.

        Chunk format
        ------------
        Each chunk is prefixed with exactly one byte:
          - bytes [0, 254]: sequential index of this chunk
          - byte 255      : marks the final (or only) chunk

        Example — payload that fits in one chunk:
          b'\\xff' + b'{"status": "ok"}'
        """
        if self._server is None:
            return

        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        chunks = [
            data[i : i + CHUNK_SIZE] for i in range(0, max(len(data), 1), CHUNK_SIZE)
        ]
        total = len(chunks)

        for idx, chunk_data in enumerate(chunks):
            is_final = (idx == total - 1)
            prefix   = bytes([255 if is_final else idx])
            packet   = prefix + chunk_data

            try:
                char = self._server.get_characteristic(char_uuid)
                if char is None:
                    self._log.log(
                        f"BluetoothServer: characteristic {char_uuid} not found"
                    )
                    return
                char.value = bytearray(packet)
                self._server.update_value(SERVICE_UUID, char_uuid)
            except Exception as exc:  # noqa: BLE001
                self._log.log(
                    f"BluetoothServer: failed to notify {char_uuid} "
                    f"(chunk {idx}/{total - 1}): {exc}"
                )
                return  # abort remaining chunks on error

    # ------------------------------------------------------------------
    # Connection lifecycle hook (optional — reset auth on disconnect)
    # ------------------------------------------------------------------

    def on_client_disconnect(self) -> None:
        """
        Call this from the bless disconnect callback (if bless exposes one)
        to reset per-connection authentication state.
        """
        if self._authenticated:
            self._log.log(
                "BluetoothServer: client disconnected — authentication cleared"
            )
        self._authenticated = False
