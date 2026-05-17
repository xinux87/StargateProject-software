import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../providers/stargate_provider.dart';

class TestScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const TestScreen({super.key, this.embedded = false});

  @override
  ConsumerState<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends ConsumerState<TestScreen> {
  Map<String, dynamic>? _systemInfo;
  bool _loadingInfo = false;
  bool _systemExpanded = false;

  Future<void> _loadSystemInfo() async {
    setState(() => _loadingInfo = true);
    try {
      final service = ref.read(stargateServiceProvider);
      final info = await service.getSystemInfo();
      if (mounted) setState(() { _systemInfo = info; _systemExpanded = true; });
    } catch (e) {
      if (mounted) _showError('Failed to load system info: $e');
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _chevronCycle(int index, bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).chevronCycle(index);
      if (mounted) _showSuccess('Chevron $index cycled');
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _allLedsOn(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).allLedsOn();
      if (mounted) _showSuccess('All LEDs turned ON');
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _allLedsOff(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).allLedsOff();
      if (mounted) _showSuccess('All LEDs turned OFF');
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _ringForward(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).symbolForward();
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _ringBackward(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).symbolBackward();
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _testAudio(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).testAudio();
      if (mounted) _showSuccess('Audio test triggered');
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _restartService(bool isConnected) async {
    if (!isConnected) return;
    final confirmed = await _showConfirmDialog(
      'Restart Service',
      'This will restart the Stargate service on the Pi. The BLE connection will be lost briefly.',
    );
    if (!confirmed) return;
    try {
      await ref.read(stargateServiceProvider).restartService();
      if (mounted) _showSuccess('Service restart triggered');
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _rebootPi(bool isConnected) async {
    if (!isConnected) return;
    final confirmed = await _showConfirmDialog(
      'Reboot Raspberry Pi',
      'This will reboot the entire Pi. The BLE connection will be lost and the gate will be offline for ~60 seconds.',
    );
    if (!confirmed) return;
    try {
      await ref.read(stargateServiceProvider).rebootPi();
      if (mounted) _showSuccess('Reboot triggered. Disconnecting...');
    } catch (e) {
      // Ignore — connection may drop before response arrives
      if (mounted) _showSuccess('Reboot command sent');
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF023E8A),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(title.toUpperCase()),
          ),
        ],
      ),
    );
    return result ?? false;
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

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chevrons section
          _SectionCard(
            title: 'CHEVRONS',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cycle individual chevron:', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (i) {
                    final index = i + 1;
                    return SizedBox(
                      width: 52,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isConnected ? () => _chevronCycle(index, isConnected) : null,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        child: Text('$index'),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? () => _allLedsOn(isConnected) : null,
                        icon: const Icon(Icons.lightbulb, size: 18),
                        label: const Text('ALL ON'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? () => _allLedsOff(isConnected) : null,
                        icon: const Icon(Icons.lightbulb_outline, size: 18),
                        label: const Text('ALL OFF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF023E8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Ring section
          _SectionCard(
            title: 'RING',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _IconActionButton(
                  icon: Icons.arrow_back,
                  label: 'BACK',
                  enabled: isConnected,
                  onTap: () => _ringBackward(isConnected),
                ),
                Container(
                  width: 1,
                  height: 60,
                  color: const Color(0xFF0077B6),
                ),
                _IconActionButton(
                  icon: Icons.arrow_forward,
                  label: 'FORWARD',
                  enabled: isConnected,
                  onTap: () => _ringForward(isConnected),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Audio section
          _SectionCard(
            title: 'AUDIO',
            child: ElevatedButton.icon(
              onPressed: isConnected ? () => _testAudio(isConnected) : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('TEST AUDIO'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ),

          const SizedBox(height: 16),

          // System info
          _SectionCard(
            title: 'SYSTEM INFO',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton.icon(
                  onPressed: isConnected ? _loadSystemInfo : null,
                  icon: _loadingInfo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.info_outline),
                  label: Text(_loadingInfo ? 'Loading...' : 'FETCH SYSTEM INFO'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
                if (_systemInfo != null) ...[
                  const SizedBox(height: 12),
                  ..._systemInfo!.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                '${e.key}:',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${e.value}',
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Danger zone
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'DANGER ZONE',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.red,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: isConnected ? () => _restartService(isConnected) : null,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('RESTART SERVICE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: isConnected ? () => _rebootPi(isConnected) : null,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('REBOOT PI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('TESTS & DIAGNOSTICS')),
      body: body,
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: enabled ? const Color(0xFF00B4D8) : Colors.grey,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: enabled ? const Color(0xFF00B4D8) : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
