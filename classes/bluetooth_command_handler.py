"""
bluetooth_command_handler.py

Bridge between BLE commands (JSON strings received over Bluetooth) and the
Stargate object + WiFi manager.

Each public handle() call dispatches a command string + params dict and
returns a result dict:
  {'status': 'ok',              'data': {...}}
  {'status': 'error',           'message': '...'}
  {'status': 'unknown_command'}
"""

import platform
import subprocess


class BluetoothCommandHandler:
    """
    Translate a BLE command name + params dict into the appropriate
    Stargate / WiFi manager call and return a normalised result dict.
    """

    def __init__(self, stargate, wifi_manager, log):
        self.stargate = stargate
        self.wifi_manager = wifi_manager
        self.log = log

        # Map command strings to handler methods so handle() stays O(1)
        self._dispatch = {
            # WiFi
            'wifi_scan':         self._wifi_scan,
            'wifi_connect':      self._wifi_connect,
            'wifi_disconnect':   self._wifi_disconnect,
            'wifi_status':       self._wifi_status,
            'wifi_saved':        self._wifi_saved,
            'wifi_forget':       self._wifi_forget,
            'set_hostname':      self._set_hostname,
            'get_hostname':      self._get_hostname,
            # Stargate status
            'get_status':        self._get_status,
            'get_system_info':   self._get_system_info,
            # DHD / dialing
            'dhd_press':         self._dhd_press,
            'clear_buffer':      self._clear_buffer,
            'simulate_incoming': self._simulate_incoming,
            # Wormhole
            'wormhole_on':       self._wormhole_on,
            'wormhole_off':      self._wormhole_off,
            # Lamp
            'lamp_on':           self._lamp_on,
            'lamp_off':          self._lamp_off,
            'lamp_set':          self._lamp_set,
            'lamp_status':       self._lamp_status,
            'lamp_animations':   self._lamp_animations,
            # Chevrons
            'chevron_cycle':     self._chevron_cycle,
            'all_leds_on':       self._all_leds_on,
            'all_leds_off':      self._all_leds_off,
            # Ring
            'symbol_forward':    self._symbol_forward,
            'symbol_backward':   self._symbol_backward,
            'ring_set_zero':     self._ring_set_zero,
            # Test / system
            'test_audio':        self._test_audio,
            'reboot':            self._reboot,
            'restart_service':   self._restart_service,
        }

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def handle(self, cmd: str, params: dict) -> dict:
        """
        Dispatch *cmd* to the appropriate handler.

        :param cmd:    Command name string.
        :param params: Optional parameters dict (may be empty).
        :returns:      Result dict with 'status' key.
        """
        self.log.log(f'BT CMD: {cmd} params={params}')

        handler = self._dispatch.get(cmd)
        if handler is None:
            return {'status': 'unknown_command'}

        try:
            data = handler(params)
            return {'status': 'ok', 'data': data}
        except Exception as ex:  # pylint: disable=broad-except
            self.log.log(f'BT CMD ERROR [{cmd}]: {ex}')
            return {'status': 'error', 'message': str(ex)}

    # ------------------------------------------------------------------
    # Internal helper
    # ------------------------------------------------------------------

    @staticmethod
    def _ok(data: dict = None) -> dict:
        """Return a success data payload (used internally before wrapping)."""
        return data if data is not None else {}

    # ------------------------------------------------------------------
    # WiFi handlers
    # ------------------------------------------------------------------

    def _wifi_scan(self, _params):
        result = self.wifi_manager.scan_networks()
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Scan failed'))
        return {'networks': result['data']}

    def _wifi_connect(self, params):
        result = self.wifi_manager.connect(params['ssid'], params.get('password', ''))
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Connect failed'))
        return result['data']

    def _wifi_disconnect(self, _params):
        result = self.wifi_manager.disconnect()
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Disconnect failed'))
        return result.get('data', {'message': 'Disconnected'})

    def _wifi_status(self, _params):
        result = self.wifi_manager.get_status()
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Status failed'))
        return result['data']  # {connected, ssid, ip, signal}

    def _wifi_saved(self, _params):
        result = self.wifi_manager.get_saved_networks()
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Failed'))
        return {'saved_networks': result['data']}

    def _wifi_forget(self, params):
        result = self.wifi_manager.forget_network(params['ssid'])
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Forget failed'))
        return result.get('data', {})

    def _set_hostname(self, params):
        result = self.wifi_manager.set_hostname(params['hostname'])
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Failed'))
        return result['data']

    def _get_hostname(self, _params):
        result = self.wifi_manager.get_hostname()
        if result.get('status') != 'ok':
            raise Exception(result.get('message', 'Failed'))
        return result['data']

    # ------------------------------------------------------------------
    # Stargate status handlers
    # ------------------------------------------------------------------

    def _get_status(self, _params):
        sg = self.stargate
        return {
            'wormhole_active':     sg.wormhole_active,
            'lamp_mode':           sg.lamp_mode,
            'lamp_color':          list(sg.lamp_color),
            'lamp_brightness':     sg.lamp_brightness,
            'lamp_animation':      sg.lamp_animation,
            'dialing_in_progress': len(sg.address_buffer_outgoing) > 0,
            'locked_chevrons':     sg.locked_chevrons_outgoing,
        }

    def _get_system_info(self, _params):
        sg = self.stargate
        # Mirror web_server.py: prefer interface-based lookup, fall back to
        # get_local_ip() for robustness.
        local_ip = sg.net_tools.get_ip_by_interface_list(['wlan0', 'eth0', 'en0', 'en1'])
        if not local_ip:
            local_ip = sg.net_tools.get_local_ip()

        # Gate name comes from the address manager, matching web_server.py
        try:
            gate_name = sg.addr_manager.get_book().get_local_gate_name()
        except Exception:  # pylint: disable=broad-except
            gate_name = sg.cfg.get('gate_name') or 'Stargate'

        return {
            'local_ip':      local_ip,
            'gate_name':     gate_name,
            'python_version': platform.python_version(),
        }

    # ------------------------------------------------------------------
    # DHD / dialing handlers — mirror web_server.py /do/dhd_press logic
    # ------------------------------------------------------------------

    def _dhd_press(self, params):
        sg = self.stargate
        symbol_number = int(params['symbol'])

        # Turn off lamp mode before any dialing action (matches web_server.py)
        if sg.lamp_mode:
            sg.set_lamp_mode(False)

        if symbol_number > 0:
            sg.keyboard.queue_symbol(symbol_number)
        elif symbol_number == 0:
            sg.keyboard.queue_center_button()
        elif symbol_number == -1 and not sg.wormhole_active and len(sg.address_buffer_outgoing) > 0:
            # Abort dialing — mirror web_server.py exactly
            sg.dialing_log.dialing_fail(sg.address_buffer_outgoing)
            sg.shutdown(cancel_sound=False, wormhole_fail_sound=False)

        return {'symbol': symbol_number}

    def _clear_buffer(self, _params):
        sg = self.stargate
        if sg.lamp_mode:
            sg.set_lamp_mode(False)
        # shutdown() resets address_buffer_outgoing and all state vars cleanly
        sg.shutdown(cancel_sound=False, wormhole_fail_sound=False)
        return {'cleared': True}

    def _simulate_incoming(self, _params):
        sg = self.stargate
        if sg.lamp_mode:
            sg.set_lamp_mode(False)
        if sg.wormhole_active:
            return {'success': False, 'message': 'A wormhole is already established.'}

        # Mirror web_server.py /do/simulate_incoming exactly
        for symbol_number in sg.addr_manager.get_book().get_local_loopback_address():
            sg.address_buffer_incoming.append(symbol_number)
        sg.address_buffer_incoming.append(7)  # Point of origin
        sg.centre_button_incoming = True
        return {'success': True}

    # ------------------------------------------------------------------
    # Wormhole handlers — mirror web_server.py /do/wormhole_on|off
    # ------------------------------------------------------------------

    def _wormhole_on(self, _params):
        sg = self.stargate
        if sg.lamp_mode:
            sg.set_lamp_mode(False)
        if sg.wormhole_active:
            return {'success': False, 'message': 'A wormhole is already established.'}
        sg.wormhole_active = True
        return {'success': True}

    def _wormhole_off(self, _params):
        sg = self.stargate
        if sg.lamp_mode:
            sg.set_lamp_mode(False)
        sg.wormhole_active = False
        return {'success': True}

    # ------------------------------------------------------------------
    # Lamp handlers — mirror web_server.py /do/lamp_* logic
    # ------------------------------------------------------------------

    def _lamp_on(self, params):
        sg = self.stargate
        color = params.get('color')
        brightness = params.get('brightness')
        animation = params.get('animation', 'static')
        sg.set_lamp_mode(True, color=color, brightness=brightness, animation=animation)
        return {
            'lamp_mode':      True,
            'color':          list(sg.lamp_color),
            'brightness':     sg.lamp_brightness,
            'lamp_animation': sg.lamp_animation,
        }

    def _lamp_off(self, _params):
        self.stargate.set_lamp_mode(False)
        return {'lamp_mode': False}

    def _lamp_set(self, params):
        sg = self.stargate
        if not sg.lamp_mode:
            return {'success': False, 'message': 'Lamp mode is not active.'}

        color = params.get('color')
        brightness = params.get('brightness')
        animation = params.get('animation')
        sg.lamp_set(color=color, brightness=brightness, animation=animation)
        return {
            'success':        True,
            'color':          list(sg.lamp_color),
            'brightness':     sg.lamp_brightness,
            'lamp_animation': sg.lamp_animation,
        }

    def _lamp_status(self, _params):
        sg = self.stargate
        return {
            'lamp_mode':      sg.lamp_mode,
            'lamp_color':     list(sg.lamp_color),
            'lamp_brightness': sg.lamp_brightness,
            'lamp_animation': sg.lamp_animation,
        }

    def _lamp_animations(self, _params):
        return {'animations': self.stargate.LAMP_ANIMATIONS}

    # ------------------------------------------------------------------
    # Chevron handlers — mirror web_server.py /do/chevron_cycle etc.
    # ------------------------------------------------------------------

    def _chevron_cycle(self, params):
        chevron_number = int(params['chevron'])
        self.stargate.chevrons.get(chevron_number).cycle_outgoing()
        return {'chevron': chevron_number}

    def _all_leds_on(self, _params):
        self.stargate.chevrons.all_lights_on()
        return {'success': True}

    def _all_leds_off(self, _params):
        self.stargate.chevrons.all_off()
        self.stargate.wormhole_active = False
        return {'success': True}

    # ------------------------------------------------------------------
    # Ring handlers — mirror web_server.py /do/symbol_forward|backward
    # ------------------------------------------------------------------

    def _symbol_forward(self, _params):
        ring = self.stargate.ring
        ring.move(33, ring.forward_direction)
        ring.release()
        return {'success': True}

    def _symbol_backward(self, _params):
        ring = self.stargate.ring
        ring.move(33, ring.backward_direction)
        ring.release()
        return {'success': True}

    def _ring_set_zero(self, _params):
        self.stargate.ring.zero_position()
        return {'success': True}

    # ------------------------------------------------------------------
    # Test / system handlers
    # ------------------------------------------------------------------

    def _test_audio(self, _params):
        self.stargate.audio.sound_start('wormhole_open')
        return {'success': True}

    def _reboot(self, _params):
        self.log.log('BT CMD: reboot requested')
        subprocess.run(['reboot'], check=False)
        return {'success': True}

    def _restart_service(self, _params):
        if not self.stargate.app.is_daemon:
            self.log.log('BT CMD: restart_service requested but not running as daemon.')
            return {'success': False, 'message': 'Not running as daemon — cannot restart service.'}
        self.log.log('BT CMD: restart_service requested')
        subprocess.run(['systemctl', 'restart', 'stargate.service'], check=False)
        return {'success': True}
