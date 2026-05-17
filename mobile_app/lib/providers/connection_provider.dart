import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ble_service.dart';
import '../services/stargate_service.dart';

// ──────────────────────────────────────────────
// BleService singleton
// ──────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ──────────────────────────────────────────────
// StargateService
// ──────────────────────────────────────────────

final stargateServiceProvider = Provider<StargateService>((ref) {
  return StargateService(ref.read(bleServiceProvider));
});

// ──────────────────────────────────────────────
// Connection state stream
// ──────────────────────────────────────────────

final connectionStateProvider = StreamProvider<bool>((ref) {
  return ref.read(bleServiceProvider).connectionStream;
});

// ──────────────────────────────────────────────
// BLE scan results
// ──────────────────────────────────────────────

final scanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  return FlutterBluePlus.onScanResults;
});

// ──────────────────────────────────────────────
// Bluetooth adapter state
// ──────────────────────────────────────────────

final bluetoothAdapterStateProvider = StreamProvider<BluetoothAdapterState>((ref) {
  return FlutterBluePlus.adapterState;
});

// ──────────────────────────────────────────────
// Auth state
// ──────────────────────────────────────────────

class AuthState {
  final bool authenticated;
  final String? savedPin;

  const AuthState({required this.authenticated, this.savedPin});

  AuthState copyWith({bool? authenticated, String? savedPin}) {
    return AuthState(
      authenticated: authenticated ?? this.authenticated,
      savedPin: savedPin ?? this.savedPin,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(authenticated: false)) {
    _loadSavedPin();
  }

  Future<void> _loadSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString('stargate_pin');
    if (pin != null) {
      state = AuthState(authenticated: false, savedPin: pin);
    }
  }

  Future<void> setSaved(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stargate_pin', pin);
    state = AuthState(authenticated: true, savedPin: pin);
  }

  void setAuthenticated(bool value) {
    state = state.copyWith(authenticated: value);
  }

  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('stargate_pin');
    state = const AuthState(authenticated: false, savedPin: null);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
