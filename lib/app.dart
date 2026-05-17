import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

const kPrimary = Color(0xFF188BFF);
const kPrimaryDark = Color(0xFF0D6FD8);
const kPrimaryLight = Color(0xFFDCEEFF);
const kSurface = Color(0xFFF5F8FF);

class StoryApp extends ConsumerWidget {
  const StoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'SELISE Story Automation',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: _buildTheme(Brightness.light),
      home: auth.isAuthenticated ? const DashboardScreen() : const LoginScreen(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: brightness,
  ).copyWith(
    primary: kPrimary,
    onPrimary: Colors.white,
    primaryContainer: kPrimaryLight,
    onPrimaryContainer: const Color(0xFF001E3C),
    surface: brightness == Brightness.light ? Colors.white : const Color(0xFF1A1C1E),
    surfaceContainerLow: brightness == Brightness.light ? kSurface : const Color(0xFF1E2124),
  );

  final textTheme = GoogleFonts.interTextTheme(
    brightness == Brightness.light ? ThemeData.light().textTheme : ThemeData.dark().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    textTheme: textTheme,
    scaffoldBackgroundColor: brightness == Brightness.light ? kSurface : const Color(0xFF1A1C1E),
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.light ? Colors.white : const Color(0xFF1E2124),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      systemOverlayStyle: brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: brightness == Brightness.light ? Colors.white : const Color(0xFF1E2124),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: brightness == Brightness.light
              ? const Color(0xFFE0E8F0)
              : const Color(0xFF2E3238),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light ? kSurface : const Color(0xFF2A2D31),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: brightness == Brightness.light ? const Color(0xFFD0DCE8) : const Color(0xFF3A3D41)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: brightness == Brightness.light ? const Color(0xFFD0DCE8) : const Color(0xFF3A3D41)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: brightness == Brightness.light ? Colors.white : const Color(0xFF1E2124),
      surfaceTintColor: Colors.transparent,
      indicatorColor: kPrimaryLight,
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
  );
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
