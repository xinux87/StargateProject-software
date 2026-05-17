import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/scan_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/wifi_screen.dart';
import 'screens/control_screen.dart';
import 'screens/lights_screen.dart';
import 'screens/test_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ScanScreen(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/wifi',
      builder: (context, state) => const WifiScreen(),
    ),
    GoRoute(
      path: '/control',
      builder: (context, state) => const ControlScreen(),
    ),
    GoRoute(
      path: '/lights',
      builder: (context, state) => const LightsScreen(),
    ),
    GoRoute(
      path: '/tests',
      builder: (context, state) => const TestScreen(),
    ),
  ],
);

class StargateApp extends ConsumerWidget {
  const StargateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Stargate Controller',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: _buildTheme(),
    );
  }

  ThemeData _buildTheme() {
    const primaryColor = Color(0xFF00B4D8);
    const backgroundColor = Color(0xFF03045E);
    const cardColor = Color(0xFF0077B6);
    const surfaceColor = Color(0xFF023E8A);
    const onSurfaceColor = Color(0xFFCAF0F8);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: Color(0xFF90E0EF),
        tertiary: Color(0xFF48CAE4),
        surface: surfaceColor,
        onPrimary: Color(0xFF03045E),
        onSecondary: Color(0xFF03045E),
        onSurface: onSurfaceColor,
        error: Color(0xFFFF6B6B),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundColor,
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: primaryColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF0096C7), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: primaryColor),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, letterSpacing: 2),
        headlineMedium: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: onSurfaceColor, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: onSurfaceColor, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: onSurfaceColor),
        bodyLarge: TextStyle(color: onSurfaceColor),
        bodyMedium: TextStyle(color: Color(0xFF90E0EF)),
        labelLarge: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold),
      ),
      dividerColor: const Color(0xFF0096C7),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor.withOpacity(0.4);
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: primaryColor,
        thumbColor: primaryColor,
        inactiveTrackColor: Color(0xFF0096C7),
        overlayColor: Color(0x2900B4D8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceColor,
        contentTextStyle: const TextStyle(color: onSurfaceColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
