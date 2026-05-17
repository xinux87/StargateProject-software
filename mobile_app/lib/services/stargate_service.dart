import '../models/stargate_state.dart';
import '../models/wifi_network.dart';
import 'ble_service.dart';

class StargateService {
  final BleService _ble;

  StargateService(this._ble);

  // ──────────────────────────────────────────────
  // Authentication
  // ──────────────────────────────────────────────

  Future<bool> authenticate(String pin) async {
    final res = await _ble.sendCommand('auth', params: {'pin': pin});
    return res['status'] == 'ok';
  }

  // ──────────────────────────────────────────────
  // WiFi
  // ──────────────────────────────────────────────

  Future<List<WifiNetwork>> scanWifi() async {
    final res = await _ble.sendCommand('wifi_scan', params: {});
    if (res['status'] != 'ok') {
      throw Exception(res['error'] ?? 'wifi_scan failed');
    }
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final networks = data['networks'] as List<dynamic>? ?? [];
    return networks
        .map((n) => WifiNetwork.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<bool> connectWifi(String ssid, {String password = ''}) async {
    final res = await _ble.sendCommand(
      'wifi_connect',
      params: {'ssid': ssid, 'password': password},
    );
    return res['status'] == 'ok';
  }

  Future<Map<String, dynamic>> getWifiStatus() async {
    final res = await _ble.sendCommand('wifi_status', params: {});
    if (res['status'] != 'ok') {
      throw Exception(res['error'] ?? 'wifi_status failed');
    }
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  Future<bool> disconnectWifi() async {
    final res = await _ble.sendCommand('wifi_disconnect', params: {});
    return res['status'] == 'ok';
  }

  Future<List<String>> getSavedNetworks() async {
    final res = await _ble.sendCommand('wifi_saved', params: {});
    if (res['status'] != 'ok') return [];
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final networks = data['saved_networks'] as List<dynamic>? ?? [];
    return networks
        .map((n) => (n as Map<String, dynamic>)['ssid']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<bool> forgetNetwork(String ssid) async {
    final res = await _ble.sendCommand('wifi_forget', params: {'ssid': ssid});
    return res['status'] == 'ok';
  }

  // ──────────────────────────────────────────────
  // Stargate state
  // ──────────────────────────────────────────────

  Future<StargateState> getStatus() async {
    final res = await _ble.sendCommand('get_status', params: {});
    if (res['status'] != 'ok') {
      throw Exception(res['error'] ?? 'get_status failed');
    }
    final data = res['data'] as Map<String, dynamic>? ?? {};
    return StargateState.fromJson(data);
  }

  Future<void> dhdPress(int symbol) async {
    await _ble.sendCommand('dhd_press', params: {'symbol': symbol});
  }

  Future<void> wormholeOn() async {
    await _ble.sendCommand('wormhole_on', params: {});
  }

  Future<void> wormholeOff() async {
    await _ble.sendCommand('wormhole_off', params: {});
  }

  Future<void> abortDial() async {
    await _ble.sendCommand('dhd_press', params: {'symbol': -1});
  }

  Future<void> simulateIncoming() async {
    await _ble.sendCommand('simulate_incoming', params: {});
  }

  // ──────────────────────────────────────────────
  // Lamp
  // ──────────────────────────────────────────────

  Future<void> lampOn({
    List<int>? color,
    int? brightness,
    String? animation,
  }) async {
    final params = <String, dynamic>{};
    if (color != null) params['color'] = color;
    if (brightness != null) params['brightness'] = brightness;
    if (animation != null) params['animation'] = animation;
    await _ble.sendCommand('lamp_on', params: params);
  }

  Future<void> lampOff() async {
    await _ble.sendCommand('lamp_off', params: {});
  }

  Future<void> lampSet({
    List<int>? color,
    int? brightness,
    String? animation,
  }) async {
    final params = <String, dynamic>{};
    if (color != null) params['color'] = color;
    if (brightness != null) params['brightness'] = brightness;
    if (animation != null) params['animation'] = animation;
    await _ble.sendCommand('lamp_set', params: params);
  }

  Future<List<Map<String, String>>> getLampAnimations() async {
    final res = await _ble.sendCommand('lamp_animations', params: {});
    if (res['status'] != 'ok') {
      // Fallback to known animations if gate firmware is older
      return const [
        {'id': 'static', 'name': 'Static Color'},
        {'id': 'wormhole', 'name': 'Wormhole Effect'},
        {'id': 'black_hole', 'name': 'Black Hole'},
        {'id': 'kawoosh', 'name': 'Kawoosh Loop'},
      ];
    }
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final animations = data['animations'] as List<dynamic>? ?? [];
    return animations
        .map((a) {
          final m = a as Map<String, dynamic>;
          return <String, String>{
            'id': m['id']?.toString() ?? '',
            'name': m['name']?.toString() ?? '',
          };
        })
        .toList();
  }

  // ──────────────────────────────────────────────
  // Chevrons & LEDs
  // ──────────────────────────────────────────────

  Future<void> chevronCycle(int index) async {
    await _ble.sendCommand('chevron_cycle', params: {'chevron': index});
  }

  Future<void> allLedsOn() async {
    await _ble.sendCommand('all_leds_on', params: {});
  }

  Future<void> allLedsOff() async {
    await _ble.sendCommand('all_leds_off', params: {});
  }

  // ──────────────────────────────────────────────
  // Ring
  // ──────────────────────────────────────────────

  Future<void> symbolForward() async {
    await _ble.sendCommand('symbol_forward', params: {});
  }

  Future<void> symbolBackward() async {
    await _ble.sendCommand('symbol_backward', params: {});
  }

  // ──────────────────────────────────────────────
  // Tests & System
  // ──────────────────────────────────────────────

  Future<Map<String, dynamic>> getSystemInfo() async {
    final res = await _ble.sendCommand('get_system_info', params: {});
    if (res['status'] != 'ok') {
      throw Exception(res['error'] ?? 'get_system_info failed');
    }
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  Future<void> testAudio() async {
    await _ble.sendCommand('test_audio', params: {});
  }

  Future<void> restartService() async {
    await _ble.sendCommand('restart_service', params: {});
  }

  Future<void> rebootPi() async {
    await _ble.sendCommand('reboot', params: {});
  }

  // ──────────────────────────────────────────────
  // Address book / planets
  // ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAddresses() async {
    final res = await _ble.sendCommand('get_addresses', params: {});
    if (res['status'] == 'unknown_command') {
      throw Exception('Firmware does not support get_addresses — restart the Pi service');
    }
    if (res['status'] != 'ok') {
      throw Exception(res['message'] ?? res['error'] ?? 'get_addresses failed');
    }
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final planets = data['planets'] as List<dynamic>? ?? [];
    if (planets.isEmpty) {
      throw Exception('Address book is empty on the gate');
    }
    return planets.map((p) {
      final m = p as Map<String, dynamic>;
      return <String, dynamic>{
        'name': m['name']?.toString() ?? '',
        'address': (m['address'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
        'type': m['type']?.toString() ?? 'unknown',
      };
    }).toList();
  }
}
