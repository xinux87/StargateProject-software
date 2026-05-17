import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/stargate_state.dart';
import '../providers/connection_provider.dart';
import '../providers/stargate_provider.dart';

class ControlScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const ControlScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _sendSymbol(int symbol, bool isConnected) async {
    if (!isConnected) return;
    try {
      final service = ref.read(stargateServiceProvider);
      await service.dhdPress(symbol);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _wormholeAction(bool isActive, bool isConnected) async {
    if (!isConnected) return;
    try {
      final service = ref.read(stargateServiceProvider);
      if (isActive) {
        await service.wormholeOff();
      } else {
        await service.wormholeOn();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _abort(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).abortDial();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _simulateIncoming(bool isConnected) async {
    if (!isConnected) return;
    try {
      await ref.read(stargateServiceProvider).simulateIncoming();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incoming wormhole simulated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateAsync = ref.watch(stargateStateProvider);
    final connectionAsync = ref.watch(connectionStateProvider);

    final isConnected = connectionAsync.maybeWhen(data: (v) => v, orElse: () => true);
    final gateState = stateAsync.maybeWhen(
      data: (s) => s,
      orElse: () => StargateState.initial(),
    );

    final body = Column(
      children: [
        // Wormhole status indicator
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: gateState.wormholeActive
                    ? const Color(0xFF00B4D8).withOpacity(_pulseAnimation.value * 0.3)
                    : const Color(0xFF023E8A).withOpacity(0.5),
                border: Border(
                  bottom: BorderSide(
                    color: gateState.wormholeActive
                        ? const Color(0xFF00B4D8)
                        : const Color(0xFF0077B6),
                    width: gateState.wormholeActive ? 2 : 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.blur_circular,
                        color: gateState.wormholeActive
                            ? const Color(0xFF00B4D8)
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        gateState.wormholeActive ? 'WORMHOLE ACTIVE' : 'STANDBY',
                        style: TextStyle(
                          color: gateState.wormholeActive
                              ? const Color(0xFF00B4D8)
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  // Chevron progress
                  Row(
                    children: [
                      ...List.generate(7, (i) {
                        final locked = i < gateState.lockedChevrons;
                        return Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: locked
                                ? const Color(0xFF00B4D8)
                                : const Color(0xFF023E8A),
                            border: Border.all(
                              color: locked ? const Color(0xFF00B4D8) : const Color(0xFF0077B6),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      Text(
                        '${gateState.lockedChevrons}/7',
                        style: const TextStyle(
                          color: Color(0xFF90E0EF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        // DHD Symbol grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: 39,
            itemBuilder: (context, index) {
              final symbol = index + 1;
              return _SymbolButton(
                symbol: symbol,
                enabled: isConnected && !gateState.wormholeActive,
                onTap: () => _sendSymbol(symbol, isConnected),
              );
            },
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Wormhole open/close
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: isConnected
                      ? () => _wormholeAction(gateState.wormholeActive, isConnected)
                      : null,
                  icon: Icon(gateState.wormholeActive ? Icons.power_off : Icons.power),
                  label: Text(
                    gateState.wormholeActive ? 'CLOSE WORMHOLE' : 'OPEN WORMHOLE',
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gateState.wormholeActive
                        ? Colors.red.shade800
                        : Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isConnected ? () => _abort(isConnected) : null,
                      icon: const Icon(Icons.cancel, color: Colors.orange),
                      label: const Text('ABORT', style: TextStyle(color: Colors.orange)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isConnected
                          ? () => _simulateIncoming(isConnected)
                          : null,
                      icon: const Icon(Icons.call_received),
                      label: const Text('INCOMING'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),

              // Not connected warning
              if (!isConnected)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Not connected to Stargate',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('DHD CONTROL')),
      body: body,
    );
  }
}

class _SymbolButton extends StatelessWidget {
  final int symbol;
  final bool enabled;
  final VoidCallback onTap;

  const _SymbolButton({
    required this.symbol,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? const Color(0xFF023E8A) : const Color(0xFF011A47),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        splashColor: const Color(0xFF00B4D8).withOpacity(0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? const Color(0xFF0077B6) : const Color(0xFF011A47),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/symbols/${symbol.toString().padLeft(3, '0')}.svg',
                  width: 32,
                  height: 32,
                  colorFilter: ColorFilter.mode(
                    enabled ? const Color(0xFF00B4D8) : const Color(0xFF023E8A),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$symbol',
                  style: const TextStyle(fontSize: 9, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
