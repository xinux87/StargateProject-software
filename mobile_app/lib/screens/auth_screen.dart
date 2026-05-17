import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/connection_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final List<String> _pin = [];
  bool _loading = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  static const int _pinLength = 4;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _addDigit(String digit) {
    if (_pin.length >= _pinLength || _loading) return;
    setState(() => _pin.add(digit));
    if (_pin.length == _pinLength) {
      _authenticate();
    }
  }

  void _removeDigit() {
    if (_pin.isEmpty || _loading) return;
    setState(() => _pin.removeLast());
  }

  Future<void> _authenticate() async {
    if (_pin.length != _pinLength) return;
    setState(() => _loading = true);

    final pin = _pin.join();
    try {
      final service = ref.read(stargateServiceProvider);
      final ok = await service.authenticate(pin);
      if (!mounted) return;

      if (ok) {
        await ref.read(authStateProvider.notifier).setSaved(pin);
        if (mounted) context.go('/home');
      } else {
        _shake();
        _showError('Incorrect PIN. Try again.');
      }
    } catch (e) {
      if (mounted) {
        _shake();
        _showError('Authentication failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _pin.clear();
        });
      }
    }
  }

  void _shake() {
    _shakeController.reset();
    _shakeController.forward();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ACCESS CODE'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(bleServiceProvider).disconnect();
            context.go('/');
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'ENTER PIN',
                style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 3),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your Stargate access code',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),

              // PIN dots with shake animation
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  final offset =
                      sin(_shakeAnimation.value * pi * 6) * 12 * (1 - _shakeAnimation.value);
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pinLength, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? theme.colorScheme.primary : Colors.transparent,
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 48),

              // Numpad
              if (_loading)
                const CircularProgressIndicator()
              else
                _Numpad(
                  onDigit: _addDigit,
                  onDelete: _removeDigit,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Numpad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _Numpad({required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Column(
      children: digits.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) {
              return const SizedBox(width: 80, height: 80, child: SizedBox());
            }
            if (key == 'del') {
              return _NumpadButton(
                child: Icon(Icons.backspace_outlined, color: theme.colorScheme.primary),
                onPressed: onDelete,
              );
            }
            return _NumpadButton(
              child: Text(
                key,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () => onDigit(key),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

class _NumpadButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;

  const _NumpadButton({required this.child, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.all(8),
      child: Material(
        color: const Color(0xFF023E8A),
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(40),
          child: Center(child: child),
        ),
      ),
    );
  }
}
