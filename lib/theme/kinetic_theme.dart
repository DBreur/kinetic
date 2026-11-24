// kinetic_theme.dart: het Kinetic Dark Palette uit de spec, één-op-één als
// Dart-constanten, plus de ThemeData en tekststijlen die alle schermen delen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Design tokens (zie CLAUDE.md §3).
abstract final class KColor {
  // Achtergrond & surface (obsidian)
  static const bg = Color(0xFF101419);
  static const surface = Color(0xFF181C21);
  static const surfaceContainer = Color(0xFF1E2329);
  static const surfaceHigh = Color(0xFF262C33);
  static const surfaceElevated = Color(0xFF2D333B);

  // Primary kinetic teal
  static const teal = Color(0xFF14B8A6);
  static const tealLight = Color(0xFF5EEAD4);
  static const tealGlow = Color(0x4014B8A6); // rgba(20,184,166,0.25)

  // Biometrische & status-alerts
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF10B981);
  static const purple = Color(0xFFA855F7);
  static const blue = Color(0xFF3B82F6);

  // Typografie & randen
  static const text = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFF262C33);
}

abstract final class KRadius {
  static const md = 12.0;
  static const lg = 16.0;
  static const full = 9999.0;
}

abstract final class KText {
  static const family = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: family,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.1,
    color: KColor.text,
  );
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: KColor.text,
  );
  static const subtitle = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: KColor.text,
  );
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: KColor.text,
  );
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: KColor.textSecondary,
  );

  /// Kleine uppercase-labels boven kaarten ("DEXCOM G7", "POLAR H10").
  static const eyebrow = TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: KColor.textMuted,
  );
  static const metric = TextStyle(
    fontFamily: family,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.0,
    color: KColor.text,
    fontFeatures: _tabular,
  );
  static const metricSmall = TextStyle(
    fontFamily: family,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.0,
    color: KColor.text,
    fontFeatures: _tabular,
  );

  /// De grote rondetimer: leesbaar van een paar meter afstand op de mat.
  static const timer = TextStyle(
    fontFamily: family,
    fontSize: 104,
    fontWeight: FontWeight.w900,
    letterSpacing: -4,
    height: 1.0,
    color: KColor.text,
    fontFeatures: _tabular,
  );
}

ThemeData kineticTheme() {
  const scheme = ColorScheme.dark(
    primary: KColor.teal,
    onPrimary: KColor.bg,
    secondary: KColor.tealLight,
    onSecondary: KColor.bg,
    surface: KColor.surface,
    onSurface: KColor.text,
    surfaceContainerLowest: KColor.bg,
    surfaceContainerLow: KColor.surface,
    surfaceContainer: KColor.surfaceContainer,
    surfaceContainerHigh: KColor.surfaceHigh,
    surfaceContainerHighest: KColor.surfaceElevated,
    error: KColor.danger,
    onError: KColor.text,
    outline: KColor.border,
    outlineVariant: KColor.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: KText.family,
    scaffoldBackgroundColor: KColor.bg,
    canvasColor: KColor.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: KColor.bg,
      foregroundColor: KColor.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: KText.title,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: KColor.surface,
      ),
    ),
    dividerTheme: const DividerThemeData(color: KColor.border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KColor.surfaceElevated,
      contentTextStyle: KText.body,
      actionTextColor: KColor.tealLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.md),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColor.surface,
      modalBackgroundColor: KColor.surface,
      showDragHandle: true,
      dragHandleColor: KColor.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColor.surfaceContainer,
      titleTextStyle: KText.title,
      contentTextStyle: KText.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.lg),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColor.surfaceContainer,
      labelStyle: KText.caption,
      hintStyle: KText.body.copyWith(color: KColor.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KRadius.md),
        borderSide: const BorderSide(color: KColor.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KRadius.md),
        borderSide: const BorderSide(color: KColor.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KRadius.md),
        borderSide: const BorderSide(color: KColor.teal, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? KColor.bg
            : KColor.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? KColor.teal
            : KColor.surfaceHigh,
      ),
      trackOutlineColor: WidgetStateProperty.all(const Color(0x00000000)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? KColor.teal
            : const Color(0x00000000),
      ),
      checkColor: WidgetStateProperty.all(KColor.bg),
      side: const BorderSide(color: KColor.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: KColor.teal,
      linearTrackColor: KColor.surfaceHigh,
    ),
  );
}
