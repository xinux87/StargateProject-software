import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wifi_network.dart';
import '../providers/connection_provider.dart';

class WifiScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const WifiScreen({super.key, this.embedded = false});

  @override
  ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  bool _scanning = false;
  bool _connecting = false;
  bool _refreshingStatus = false;
  List<WifiNetwork> _networks = [];
  Map<String, dynamic> _wifiStatus = {};
  bool _statusLoaded = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    // Auto-refresh WiFi status every 15 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus({bool showSpinner = false}) async {
    if (showSpinner && mounted) setState(() => _refreshingStatus = true);
    try {
      final service = ref.read(stargateServiceProvider);
      final status = await service.getWifiStatus();
      if (mounted) setState(() { _wifiStatus = status; _statusLoaded = true; _refreshingStatus = false; });
    } catch (e) {
      if (mounted) setState(() { _statusLoaded = true; _refreshingStatus = false; });
    }
  }

  Future<void> _scanNetworks() async {
    setState(() { _scanning = true; _networks = []; });
    try {
      final service = ref.read(stargateServiceProvider);
      final networks = await service.scanWifi();
      if (mounted) setState(() => _networks = networks);
    } catch (e) {
      if (mounted) _showError('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      final service = ref.read(stargateServiceProvider);
      await service.disconnectWifi();
      await _loadStatus();
      if (mounted) _showSuccess('Disconnected from WiFi');
    } catch (e) {
      if (mounted) _showError('Failed to disconnect: $e');
    }
  }

  Future<void> _connectToNetwork(WifiNetwork network) async {
    String password = '';
    if (network.isSecured) {
      final result = await _showPasswordDialog(network.ssid);
      if (result == null) return;
      password = result;
    }

    setState(() => _connecting = true);
    try {
      final service = ref.read(stargateServiceProvider);
      final ok = await service.connectWifi(network.ssid, password: password);
      if (!mounted) return;
      if (ok) {
        _showSuccess('Connected to ${network.ssid}');
        await _loadStatus();
      } else {
        _showError('Failed to connect to ${network.ssid}');
      }
    } catch (e) {
      if (mounted) _showError('Connection error: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<String?> _showPasswordDialog(String ssid) async {
    final controller = TextEditingController();
    bool obscure = true;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF023E8A),
          title: Text('Connect to $ssid'),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('CONNECT'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionAsync = ref.watch(connectionStateProvider);
    final isConnected = connectionAsync.maybeWhen(data: (v) => v, orElse: () => true);

    final currentSsid = _wifiStatus['ssid'] as String?;
    final currentIp = _wifiStatus['ip'] as String?;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current connection card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('CURRENT CONNECTION', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
                      _refreshingStatus
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: 'Refresh',
                              onPressed: () => _loadStatus(showSpinner: true),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_statusLoaded)
                    const Center(child: CircularProgressIndicator())
                  else if (currentSsid != null && currentSsid.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          currentSsid,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (currentIp != null && currentIp.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('IP: $currentIp', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isConnected ? _disconnect : null,
                      icon: const Icon(Icons.wifi_off, size: 18),
                      label: const Text('DISCONNECT'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Icon(Icons.wifi_off, color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text('Not connected to WiFi', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Scan button
          _scanning
              ? Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text('Scanning for networks...', style: theme.textTheme.bodyMedium),
                  ],
                )
              : ElevatedButton.icon(
                  onPressed: isConnected ? _scanNetworks : null,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('SCAN NETWORKS'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                ),

          const SizedBox(height: 16),

          // Networks list
          if (_networks.isNotEmpty) ...[
            Text('AVAILABLE NETWORKS', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
            const SizedBox(height: 8),
            ...(_connecting
                ? [const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))]
                : _networks
                    .where((n) => n.ssid.isNotEmpty)
                    .map((network) => _NetworkTile(
                          network: network,
                          onConnect: isConnected ? () => _connectToNetwork(network) : null,
                        ))
                    .toList()),
          ],
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('WIFI SETTINGS')),
      body: body,
    );
  }
}

class _NetworkTile extends StatelessWidget {
  final WifiNetwork network;
  final VoidCallback? onConnect;

  const _NetworkTile({required this.network, this.onConnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _SignalBars(bars: network.signalBars),
        title: Text(
          network.ssid,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: network.connected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${network.security} ${network.connected ? "• Connected" : ""}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 11,
            color: network.connected ? Colors.green : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (network.isSecured)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.lock_outline, size: 16, color: Colors.grey),
              ),
            network.connected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : ElevatedButton(
                    onPressed: onConnect,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('CONNECT'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int bars;
  const _SignalBars({required this.bars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 5,
          height: 6.0 + (i * 4),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00B4D8) : const Color(0xFF023E8A),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
