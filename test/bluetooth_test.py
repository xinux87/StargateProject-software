#!/usr/bin/env python3
"""
Bluetooth BLE test client for Stargate.
Run on the Pi itself or any Linux machine with BLE support.
Usage: python3 test/bluetooth_test.py
"""
import asyncio
import json
import sys
from bleak import BleakScanner, BleakClient

SERVICE_UUID  = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
CMD_UUID      = "a1b2c3d4-e5f6-7890-abcd-ef1234567891"
RESPONSE_UUID = "a1b2c3d4-e5f6-7890-abcd-ef1234567892"
STATUS_UUID   = "a1b2c3d4-e5f6-7890-abcd-ef1234567893"

pending_response = {}
received_chunks = {}

def notification_handler(sender, data: bytearray):
    # Reassemble chunks
    if len(data) == 0:
        return
    chunk_idx = data[0]
    payload = data[1:]

    char_uuid = str(sender).lower()
    if char_uuid not in received_chunks:
        received_chunks[char_uuid] = {}

    if chunk_idx == 255:
        # Final chunk - assemble
        all_chunks = received_chunks.get(char_uuid, {})
        full_data = b''
        for i in sorted(all_chunks.keys()):
            full_data += all_chunks[i]
        full_data += payload
        received_chunks[char_uuid] = {}

        try:
            msg = json.loads(full_data.decode('utf-8'))
            if 'id' in msg:
                pending_response[msg['id']] = msg
            else:
                print(f"STATUS: {json.dumps(msg, indent=2)}")
        except Exception as e:
            print(f"Parse error: {e}, raw: {full_data}")
    else:
        received_chunks.setdefault(char_uuid, {})[chunk_idx] = payload

async def send_command(client: BleakClient, cmd: str, params: dict = {}, req_id: str = "req-1") -> dict:
    payload = json.dumps({"cmd": cmd, "params": params, "id": req_id}).encode()
    await client.write_gatt_char(CMD_UUID, payload, response=False)
    # Wait for response
    for _ in range(50):  # 5 second timeout
        await asyncio.sleep(0.1)
        if req_id in pending_response:
            return pending_response.pop(req_id)
    return {"status": "timeout"}

async def main():
    print("Scanning for Stargate BLE devices...")
    devices = await BleakScanner.discover(timeout=5.0)

    stargate = None
    for d in devices:
        if d.name and 'Stargate' in d.name:
            stargate = d
            print(f"Found: {d.name} ({d.address})")
            break

    if not stargate:
        print("No Stargate BLE device found. Is the Pi running?")
        sys.exit(1)

    async with BleakClient(stargate.address) as client:
        print(f"Connected to {stargate.name}")

        # Subscribe to notifications
        await client.start_notify(RESPONSE_UUID, notification_handler)
        await client.start_notify(STATUS_UUID, notification_handler)

        # Auth
        print("\n--- Auth ---")
        r = await send_command(client, "auth", {"pin": "1969"}, "auth-1")
        print(f"Auth response: {r}")

        if r.get('status') != 'ok':
            print("Authentication failed!")
            return

        # WiFi status
        print("\n--- WiFi Status ---")
        r = await send_command(client, "wifi_status", {}, "wifi-1")
        print(f"WiFi: {json.dumps(r, indent=2)}")

        # Stargate status
        print("\n--- Stargate Status ---")
        r = await send_command(client, "get_status", {}, "status-1")
        print(f"Status: {json.dumps(r, indent=2)}")

        # Lamp on (blue)
        print("\n--- Lamp ON (blue) ---")
        r = await send_command(client, "lamp_on", {"color": [0, 100, 255], "brightness": 128, "animation": "static"}, "lamp-1")
        print(f"Lamp on: {r}")

        await asyncio.sleep(2)

        # Lamp off
        print("\n--- Lamp OFF ---")
        r = await send_command(client, "lamp_off", {}, "lamp-2")
        print(f"Lamp off: {r}")

        # System info
        print("\n--- System Info ---")
        r = await send_command(client, "get_system_info", {}, "sys-1")
        print(f"System: {json.dumps(r, indent=2)}")

        print("\n--- Listening for STATUS updates for 10s ---")
        await asyncio.sleep(10)

        print("\nTest complete!")

if __name__ == "__main__":
    asyncio.run(main())
