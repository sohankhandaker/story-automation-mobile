// sera_theme.dart
// ─────────────────────────────────────────────────────────────────────────
// Builds a Material 3 ThemeData from SeraTokens, plus reusable TextStyles.
// Wire it up in your MaterialApp:  theme: buildSeraTheme()
// Requires: google_fonts (already in pubspec.yaml).
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'sera_tokens.dart';

// ── Semantic text styles (mirror colors_and_type.css type scale) ──────────
class SeraText {
  SeraText._();
  static TextStyle get display   => GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1, color: SeraTokens.fg1);
  static TextStyle get h1        => GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: SeraTokens.fg1);
  static TextStyle get h2        => GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: SeraTokens.fg1);
  static TextStyle get title     => GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: SeraTokens.fg1);
  static TextStyle get cardTitle => GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: SeraTokens.fg1);
  static TextStyle get bodyStrong=> GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: SeraTokens.fg1);
  static TextStyle get body      => GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.4, color: SeraTokens.fg1);
  static TextStyle get secondary => GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4, color: SeraTokens.fg3);
  static TextStyle get caption   => GoogleFonts.plusJakartaSans(fontSize: 11, color: SeraTokens.muted);
  static TextStyle get overline  => GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: SeraTokens.muted);
  static TextStyle get chip      => GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600);
}

ThemeData buildSeraTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: SeraTokens.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: SeraTokens.primary,
    onPrimary: Colors.white,
    primaryContainer: SeraTokens.primaryLight,
    surface: Colors.white,
    surfaceContainerLow: SeraTokens.surface,
    outline: SeraTokens.borderStrong,
    outlineVariant: SeraTokens.border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: SeraTokens.surface,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),

    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SeraTokens.rXl),
        side: const BorderSide(color: SeraTokens.border),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SeraTokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: _inputBorder(SeraTokens.borderStrong),
      enabledBorder: _inputBorder(SeraTokens.borderStrong),
      focusedBorder: _inputBorder(SeraTokens.primary, width: 1.8),
      errorBorder: _inputBorder(SeraTokens.error),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SeraTokens.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SeraTokens.rLg)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: SeraText.bodyStrong.copyWith(fontSize: 15),
        elevation: 0,
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: SeraText.title.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      iconTheme: const IconThemeData(color: SeraTokens.fg1),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SeraTokens.rLg)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        side: const BorderSide(color: SeraTokens.borderStrong),
        textStyle: SeraText.bodyStrong.copyWith(fontSize: 15),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: SeraTokens.primaryLight,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SeraTokens.rMd)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final sel = states.contains(WidgetState.selected);
        return SeraText.caption.copyWith(
          fontSize: 11,
          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
          color: sel ? SeraTokens.primary : SeraTokens.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final sel = states.contains(WidgetState.selected);
        return IconThemeData(size: 22, color: sel ? SeraTokens.primary : SeraTokens.muted);
      }),
    ),

    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SeraTokens.rPill)),
      side: BorderSide.none,
      labelStyle: SeraText.chip,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SeraTokens.rMd)),
      backgroundColor: SeraTokens.fg1,
      contentTextStyle: SeraText.secondary.copyWith(color: Colors.white, fontSize: 13),
    ),

    dividerTheme: const DividerThemeData(color: SeraTokens.divider, thickness: 1, space: 1),
  );
}

OutlineInputBorder _inputBorder(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(SeraTokens.rLg),
      borderSide: BorderSide(color: c, width: width),
    );

// ── Reusable status chip widget (mirror _StatusChip) ──────────────────────
class SeraStatusChip extends StatelessWidget {
  final String status;
  const SeraStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = SeraTokens.statusColors[status] ?? SeraTokens.statusDraft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SeraTokens.rPill),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(status, style: SeraText.chip.copyWith(color: c)),
    );
  }
}
