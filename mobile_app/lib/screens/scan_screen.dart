import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/connection_provider.dart';
import '../services/ble_service.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingDeviceId;
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningStateSub;

  @override
  void initState() {
    super.initState();
    _listenToScanResults();
    _listenToScanningState();
  }

  void _listenToScanResults() {
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _results.clear();
        for (final r in results) {
          // Filter: show Stargate devices or devices advertising our service
          final name = r.device.platformName.toLowerCase();
          final hasService = r.advertisementData.serviceUuids
              .any((u) => u.toString().toLowerCase() == BleService.serviceUuid.toLowerCase());
          if (name.contains('stargate') || hasService) {
            _results.add(r);
          }
        }
      });
    });
  }

  void _listenToScanningState() {
    _scanningStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!mounted) return;
      setState(() => _scanning = scanning);
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  Future<void> _startScan() async {
    await _requestPermissions();

    final btState = await FlutterBluePlus.adapterState.first;
    if (btState != BluetoothAdapterState.on) {
      _showError('Bluetooth is off. Please enable Bluetooth and try again.');
      return;
    }

    setState(() {
      _results.clear();
      _scanning = true;
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(BleService.serviceUuid)],
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      if (mounted) {
        _showError('Scan failed: $e');
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() => _scanning = false);
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    if (_connecting) return;
    await _stopScan();

    setState(() {
      _connecting = true;
      _connectingDeviceId = device.remoteId.str;
    });

    try {
      final bleService = ref.read(bleServiceProvider);
      await bleService.connect(device);

      if (!mounted) return;

      // Check if we have a saved PIN
      final authState = ref.read(authStateProvider);
      if (authState.savedPin != null) {
        // Try to authenticate silently with saved PIN
        final stargateService = ref.read(stargateServiceProvider);
        try {
          final ok = await stargateService.authenticate(authState.savedPin!);
          if (ok) {
            ref.read(authStateProvider.notifier).setAuthenticated(true);
            if (mounted) context.go('/home');
            return;
          }
        } catch (_) {
          // Fall through to auth screen
        }
      }
      if (mounted) context.go('/auth');
    } catch (e) {
      if (mounted) {
        _showError('Connection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectingDeviceId = null;
        });
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningStateSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('STARGATE CONTROLLER'),
      ),
      body: Column(
        children: [
          // Header / hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF03045E),
                  const Color(0xFF0077B6).withOpacity(0.5),
                ],
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.blur_circular,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'SCAN FOR STARGATE',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: 3,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find and connect to your Stargate replica via Bluetooth',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: _scanning
                ? Column(
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _stopScan,
                        icon: const Icon(Icons.stop),
                        label: const Text('STOP SCAN'),
                      ),
                    ],
                  )
                : ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('SCAN FOR DEVICES'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
          ),

          // Results list
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 48,
                          color: theme.colorScheme.secondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _scanning ? 'Searching...' : 'No Stargate devices found',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.secondary.withOpacity(0.7),
                          ),
                        ),
                        if (!_scanning) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Make sure the Pi is powered on\nand BLE is enabled.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary.withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      final device = result.device;
                      final name = device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Unknown Device';
                      final isThisConnecting =
                          _connecting && _connectingDeviceId == device.remoteId.str;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.blur_circular, size: 36),
                          title: Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            device.remoteId.str,
                            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${result.rssi} dBm',
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              isThisConnecting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : ElevatedButton(
                                      onPressed: _connecting ? null : () => _connectTo(device),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      child: const Text('CONNECT'),
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
