import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stargate_state.dart';
import '../models/wifi_network.dart';
import 'connection_provider.dart';

// ──────────────────────────────────────────────
// Live Stargate state from STATUS characteristic notifications
// ──────────────────────────────────────────────

final stargateStateProvider = StreamProvider<StargateState>((ref) {
  return ref
      .read(bleServiceProvider)
      .statusStream
      .map((json) => StargateState.fromJson(json));
});

// ──────────────────────────────────────────────
// WiFi networks (fetched on demand, auto-disposed)
// ──────────────────────────────────────────────

final wifiNetworksProvider = FutureProvider.autoDispose<List<WifiNetwork>>((ref) async {
  final service = ref.read(stargateServiceProvider);
  return service.scanWifi();
});

// ──────────────────────────────────────────────
// Lamp animations list (fetched once per session)
// ──────────────────────────────────────────────

final lampAnimationsProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  final service = ref.read(stargateServiceProvider);
  return service.getLampAnimations();
});

// ──────────────────────────────────────────────
// System info (fetched on demand, auto-disposed)
// ──────────────────────────────────────────────

final systemInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final service = ref.read(stargateServiceProvider);
  return service.getSystemInfo();
});

// ──────────────────────────────────────────────
// WiFi connection status (fetched on demand, auto-disposed)
// ──────────────────────────────────────────────

final wifiStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final service = ref.read(stargateServiceProvider);
  return service.getWifiStatus();
});

