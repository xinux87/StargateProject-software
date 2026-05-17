import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/stargate_state.dart';
import '../providers/connection_provider.dart';
import '../providers/stargate_provider.dart';
import 'control_screen.dart';
import 'lights_screen.dart';
import 'wifi_screen.dart';
import 'test_screen.dart';

// Shared planet-dialing helper used by Home and Control screens
Future<void> dialPlanet(
  List<int> address,
  dynamic service,
  BuildContext context,
) async {
  for (final symbol in address) {
    await service.dhdPress(symbol);
    await Future.delayed(const Duration(milliseconds: 600));
  }
  await service.dhdPress(0); // centre button
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dialing sequence sent')),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    _DashboardTab(),
    ControlScreen(embedded: true),
    LightsScreen(embedded: true),
    WifiScreen(embedded: true),
    TestScreen(embedded: true),
  ];

  void _disconnect() async {
    await ref.read(bleServiceProvider).disconnect();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionAsync = ref.watch(connectionStateProvider);

    final isConnected = connectionAsync.maybeWhen(
      data: (v) => v,
      orElse: () => true, // assume connected unless told otherwise
    );

    // Auto-navigate back to scan if disconnected
    ref.listen(connectionStateProvider, (_, next) {
      next.whenData((connected) {
        if (!connected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Disconnected from Stargate')),
          );
          context.go('/');
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('STARGATE'),
        actions: [
          if (!isConnected)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.bluetooth_disabled, color: Colors.red),
            ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Disconnect',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        backgroundColor: const Color(0xFF023E8A),
        indicatorColor: theme.colorScheme.primary.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.blur_circular_outlined),
            selectedIcon: Icon(Icons.blur_circular),
            label: 'Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outlined),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Lights',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi_outlined),
            selectedIcon: Icon(Icons.wifi),
            label: 'WiFi',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Tests',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stateAsync = ref.watch(stargateStateProvider);
    final connectionAsync = ref.watch(connectionStateProvider);

    final isConnected = connectionAsync.maybeWhen(data: (v) => v, orElse: () => true);

    final gateState = stateAsync.maybeWhen(
      data: (s) => s,
      orElse: () => StargateState.initial(),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? 'CONNECTED' : 'DISCONNECTED',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isConnected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        isConnected ? 'Stargate BLE Link Active' : 'No BLE connection',
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Wormhole status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('WORMHOLE', style: theme.textTheme.titleMedium),
                      _StatusBadge(
                        active: gateState.wormholeActive,
                        activeLabel: 'ACTIVE',
                        inactiveLabel: 'INACTIVE',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('DIALING', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: gateState.lockedChevrons / 7,
                            minHeight: 10,
                            backgroundColor: const Color(0xFF023E8A),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              gateState.dialing
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${gateState.lockedChevrons}/7',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (gateState.dialing) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Dialing in progress...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Lamp status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('LAMP MODE', style: theme.textTheme.titleMedium),
                      _StatusBadge(
                        active: gateState.lampMode,
                        activeLabel: 'ON',
                        inactiveLabel: 'OFF',
                      ),
                    ],
                  ),
                  if (gateState.lampMode) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color.fromARGB(
                              255,
                              gateState.lampColor[0],
                              gateState.lampColor[1],
                              gateState.lampColor[2],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Animation: ${gateState.lampAnimation}',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              'Brightness: ${gateState.lampBrightness}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Quick actions
          Text('QUICK ACTIONS', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.power,
                  label: gateState.wormholeActive ? 'Close\nWormhole' : 'Open\nWormhole',
                  color: gateState.wormholeActive ? Colors.red : Colors.green,
                  onTap: isConnected
                      ? () async {
                          final service = ref.read(stargateServiceProvider);
                          try {
                            if (gateState.wormholeActive) {
                              await service.wormholeOff();
                            } else {
                              await service.wormholeOn();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: gateState.lampMode ? Icons.lightbulb : Icons.lightbulb_outline,
                  label: gateState.lampMode ? 'Lamp\nOFF' : 'Lamp\nON',
                  color: gateState.lampMode ? theme.colorScheme.secondary : theme.colorScheme.primary,
                  onTap: isConnected
                      ? () async {
                          final service = ref.read(stargateServiceProvider);
                          try {
                            if (gateState.lampMode) {
                              await service.lampOff();
                            } else {
                              await service.lampOn();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.cancel_outlined,
                  label: 'Abort\nDial',
                  color: Colors.orange,
                  onTap: isConnected
                      ? () async {
                          final service = ref.read(stargateServiceProvider);
                          try {
                            await service.abortDial();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── DIAL A PLANET ───────────────────────────────────────
          Text(
            'DIAL A PLANET',
            style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          _PlanetList(isConnected: isConnected),
        ],
      ),
    );
  }
}

// ─── Planet list widget ─────────────────────────────────────────────────────

class _PlanetList extends ConsumerStatefulWidget {
  final bool isConnected;
  const _PlanetList({required this.isConnected});

  @override
  ConsumerState<_PlanetList> createState() => _PlanetListState();
}

class _PlanetListState extends ConsumerState<_PlanetList> {
  List<Map<String, dynamic>> _planets = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Small delay so BLE is fully settled after auth before we send commands
    Future.delayed(const Duration(milliseconds: 800), _load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(stargateServiceProvider);
      final planets = await service.getAddresses();
      if (mounted) setState(() { _planets = planets; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.orange, fontSize: 12))),
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('RETRY'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_planets.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('No planets loaded', style: theme.textTheme.bodyMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('LOAD'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ..._planets.map((p) => _PlanetCard(planet: p, isConnected: widget.isConnected)),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Refresh list', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _PlanetCard extends ConsumerWidget {
  final Map<String, dynamic> planet;
  final bool isConnected;
  const _PlanetCard({required this.planet, required this.isConnected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = planet['name'] as String;
    final address = planet['address'] as List<int>;
    final type = planet['type'] as String;
    bool dialing = false;

    return StatefulBuilder(
      builder: (context, setState) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            type == 'lan' ? Icons.lan : Icons.public,
            color: theme.colorScheme.primary,
            size: 22,
          ),
          title: Text(name, style: theme.textTheme.titleMedium),
          subtitle: Text(
            address.join(' - '),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
          ),
          trailing: dialing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : ElevatedButton(
                  onPressed: isConnected
                      ? () async {
                          setState(() => dialing = true);
                          try {
                            final service = ref.read(stargateServiceProvider);
                            await dialPlanet(address, service, context);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          } finally {
                            setState(() => dialing = false);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('DIAL'),
                ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  final String activeLabel;
  final String inactiveLabel;

  const _StatusBadge({
    required this.active,
    required this.activeLabel,
    required this.inactiveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? Colors.green : Colors.grey,
          width: 1,
        ),
      ),
      child: Text(
        active ? activeLabel : inactiveLabel,
        style: TextStyle(
          color: active ? Colors.green : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onTap != null ? color : Colors.grey, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onTap != null ? Colors.white : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
