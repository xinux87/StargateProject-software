import 'dart:async';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stargate_state.dart';
import '../providers/connection_provider.dart';
import '../providers/stargate_provider.dart';

class LightsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const LightsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<LightsScreen> createState() => _LightsScreenState();
}

class _LightsScreenState extends ConsumerState<LightsScreen> {
  bool _lampOn = false;
  Color _selectedColor = const Color(0xFFFFFFFF);
  double _brightness = 255;
  String _selectedAnimation = 'static';
  Timer? _debounce;
  bool _sending = false;
  DateTime? _lastInteraction;

  static const _animations = [
    {'id': 'static', 'name': 'Static'},
    {'id': 'wormhole', 'name': 'Wormhole'},
    {'id': 'black_hole', 'name': 'Black Hole'},
    {'id': 'kawoosh', 'name': 'Kawoosh'},
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _syncFromState(StargateState state) {
    // Only sync if we're not in the middle of sending
    if (_sending) return;
    _lampOn = state.lampMode;
    // Only sync color/brightness/animation if user hasn't interacted recently
    final recentInteraction = _lastInteraction != null &&
        DateTime.now().difference(_lastInteraction!).inSeconds < 5;
    if (!recentInteraction) {
      if (state.lampColor.length >= 3) {
        _selectedColor = Color.fromARGB(
          255,
          state.lampColor[0],
          state.lampColor[1],
          state.lampColor[2],
        );
      }
      _brightness = state.lampBrightness.toDouble();
      _selectedAnimation = state.lampAnimation;
    }
  }

  Future<void> _toggleLamp(bool value, bool isConnected) async {
    if (!isConnected) return;
    final service = ref.read(stargateServiceProvider);
    try {
      if (value) {
        await service.lampOn(
          color: [_selectedColor.red, _selectedColor.green, _selectedColor.blue],
          brightness: _brightness.round(),
          animation: _selectedAnimation,
        );
      } else {
        await service.lampOff();
      }
      setState(() => _lampOn = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _scheduleUpdate(bool isConnected) {
    if (!isConnected || !_lampOn) return;
    _lastInteraction = DateTime.now();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _applyChanges(isConnected);
    });
  }

  Future<void> _applyChanges(bool isConnected) async {
    if (!isConnected || !_lampOn) return;
    setState(() => _sending = true);
    try {
      final service = ref.read(stargateServiceProvider);
      await service.lampSet(
        color: [_selectedColor.red, _selectedColor.green, _selectedColor.blue],
        brightness: _brightness.round(),
        animation: _selectedAnimation,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying lamp settings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateAsync = ref.watch(stargateStateProvider);
    final connectionAsync = ref.watch(connectionStateProvider);
    final isConnected = connectionAsync.maybeWhen(data: (v) => v, orElse: () => true);

    stateAsync.whenData((state) => _syncFromState(state));

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ON/OFF toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LAMP MODE', style: theme.textTheme.titleMedium),
                      Text(
                        _lampOn ? 'Active' : 'Inactive',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _lampOn ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _lampOn,
                    onChanged: isConnected
                        ? (v) => _toggleLamp(v, isConnected)
                        : null,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Color preview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('COLOR PREVIEW', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _lampOn ? _selectedColor.withOpacity(_brightness / 255) : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0077B6)),
                      boxShadow: _lampOn
                          ? [
                              BoxShadow(
                                color: _selectedColor.withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: _lampOn
                        ? null
                        : const Center(
                            child: Text(
                              'LAMP OFF',
                              style: TextStyle(color: Colors.grey, letterSpacing: 2),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Color picker
          AbsorbPointer(
            absorbing: !_lampOn || !isConnected,
            child: Opacity(
              opacity: (_lampOn && isConnected) ? 1.0 : 0.4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COLOR', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      ColorPicker(
                        color: _selectedColor,
                        onColorChanged: (color) {
                          setState(() => _selectedColor = color);
                          _scheduleUpdate(isConnected);
                        },
                        width: 36,
                        height: 36,
                        borderRadius: 18,
                        spacing: 5,
                        runSpacing: 5,
                        wheelDiameter: 180,
                        heading: null,
                        subheading: Text(
                          'Select shade',
                          style: theme.textTheme.bodyMedium,
                        ),
                        pickerTypeLabels: const {
                          ColorPickerType.primary: 'Colors',
                          ColorPickerType.wheel: 'Custom',
                        },
                        pickersEnabled: const {
                          ColorPickerType.primary: true,
                          ColorPickerType.accent: false,
                          ColorPickerType.bw: true,
                          ColorPickerType.both: false,
                          ColorPickerType.wheel: true,
                          ColorPickerType.custom: false,
                          ColorPickerType.customSecondary: false,
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Brightness
          AbsorbPointer(
            absorbing: !_lampOn || !isConnected,
            child: Opacity(
              opacity: (_lampOn && isConnected) ? 1.0 : 0.4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('BRIGHTNESS', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
                          Text(
                            _brightness.round().toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Slider(
                        value: _brightness,
                        min: 0,
                        max: 255,
                        divisions: 255,
                        onChanged: (v) {
                          setState(() => _brightness = v);
                          _scheduleUpdate(isConnected);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Animation selector
          AbsorbPointer(
            absorbing: !_lampOn || !isConnected,
            child: Opacity(
              opacity: (_lampOn && isConnected) ? 1.0 : 0.4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ANIMATION', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      ..._animations.map((anim) => RadioListTile<String>(
                            value: anim['id']!,
                            groupValue: _selectedAnimation,
                            title: Text(anim['name']!, style: theme.textTheme.bodyLarge),
                            activeColor: theme.colorScheme.primary,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (_lampOn && isConnected)
                                ? (v) {
                                    if (v == null) return;
                                    setState(() => _selectedAnimation = v);
                                    _scheduleUpdate(isConnected);
                                  }
                                : null,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sending indicator
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: LinearProgressIndicator()),
            ),

          if (!isConnected)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Not connected to Stargate',
                style: TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('LAMP CONTROL')),
      body: body,
    );
  }
}
