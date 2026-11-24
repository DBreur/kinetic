// kinetic_theme.dart: het Kinetic design system (kinetic-design/) in twee
// varianten met live wisselen:
//  - Dark  = "Kinetic Metabolic Combat" (canvas #0b0f14, kaarten #121820)
//  - Light = "Kinetic" (canvas #f8fafc, witte kaarten, teal #0d9488)
// Geen gradients, glows of decoratieve schaduwen: diepte komt alleen uit
// tonale lagen en 1px haarlijnen.
//
// Gebruik in widgets: `final k = context.k;` voor kleuren en `context.t`
// voor tekststijlen (al ingekleurd voor het actieve thema).

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class KineticColors extends ThemeExtension<KineticColors> {
  const KineticColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.well,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.primaryPressed,
    required this.accent,
    required this.primaryTint,
    required this.success,
    required this.successInk,
    required this.successTint,
    required this.warning,
    required this.warningInk,
    required this.warningTint,
    required this.danger,
    required this.dangerInk,
    required this.dangerTint,
    required this.purple,
    required this.blue,
    required this.scrim,
  });

  final Brightness brightness;

  /// Level 0: de achtergrond van het scherm.
  final Color canvas;

  /// Level 1: kaarten en de navigatiebalk.
  final Color surface;

  /// Level 2: ingezonken "wells" binnen kaarten, neutrale knoppen.
  final Color well;

  /// 1px haarlijn rond kaarten.
  final Color border;
  final Color borderStrong;

  final Color text;
  final Color textSecondary;
  final Color textMuted;

  /// Primaire actie (knoppen, actieve tab, voortgang).
  final Color primary;
  final Color onPrimary;
  final Color primaryPressed;

  /// Teal voor waarden en accenten in tekst.
  final Color accent;
  final Color primaryTint;

  // Klinische statuskleuren: altijd samen met een label of icoon gebruiken.
  final Color success;
  final Color successInk;
  final Color successTint;
  final Color warning;
  final Color warningInk;
  final Color warningTint;
  final Color danger;
  final Color dangerInk;
  final Color dangerTint;

  final Color purple;
  final Color blue;
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  static const dark = KineticColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B0F14),
    surface: Color(0xFF121820),
    well: Color(0xFF1C2430),
    border: Color(0xFF1C2430),
    borderStrong: Color(0xFF283546),
    text: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    primary: Color(0xFF14B8A6),
    onPrimary: Color(0xFF042F2E),
    primaryPressed: Color(0xFF0F766E),
    accent: Color(0xFF2DD4BF),
    primaryTint: Color(0x2614B8A6),
    success: Color(0xFF10B981),
    successInk: Color(0xFF34D399),
    successTint: Color(0x2610B981),
    warning: Color(0xFFF59E0B),
    warningInk: Color(0xFFFBBF24),
    warningTint: Color(0x26F59E0B),
    danger: Color(0xFFEF4444),
    dangerInk: Color(0xFFF87171),
    dangerTint: Color(0x26EF4444),
    purple: Color(0xFFA855F7),
    blue: Color(0xFF3B82F6),
    scrim: Color(0xE60B0F14),
  );

  static const light = KineticColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    well: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    primary: Color(0xFF0D9488),
    onPrimary: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF0F766E),
    accent: Color(0xFF0D9488),
    primaryTint: Color(0x1A0D9488),
    success: Color(0xFF10B981),
    successInk: Color(0xFF065F46),
    successTint: Color(0xFFECFDF5),
    warning: Color(0xFFF59E0B),
    warningInk: Color(0xFF92400E),
    warningTint: Color(0xFFFEF3C7),
    danger: Color(0xFFEF4444),
    dangerInk: Color(0xFF991B1B),
    dangerTint: Color(0xFFFEE2E2),
    purple: Color(0xFF7C3AED),
    blue: Color(0xFF2563EB),
    scrim: Color(0x1A000000),
  );

  @override
  KineticColors copyWith() => this;

  @override
  KineticColors lerp(ThemeExtension<KineticColors>? other, double t) =>
      t < 0.5 ? this : (other as KineticColors? ?? this);
}

/// Tekststijlen, al ingekleurd voor het actieve thema.
class KineticTypography {
  KineticTypography(this.k);
  final KineticColors k;

  static const family = 'Inter';
  static const _tab = [FontFeature.tabularFigures()];

  TextStyle _s(double size, FontWeight w, {double? h, double ls = 0, Color? c, bool tab = false}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: w,
    height: h,
    letterSpacing: ls,
    color: c ?? k.text,
    fontFeatures: tab ? _tab : null,
  );

  /// Grote paginatitel ("Technique Vault", "Good morning").
  TextStyle get headlineLg => _s(30, FontWeight.w700, h: 1.2, ls: -0.6);
  TextStyle get headline => _s(22, FontWeight.w700, h: 1.27, ls: -0.33);
  TextStyle get title => _s(18, FontWeight.w600, h: 1.33);
  TextStyle get subtitle => _s(16, FontWeight.w600, h: 1.35);
  TextStyle get bodyLg => _s(16, FontWeight.w400, h: 1.5, c: k.textSecondary);
  TextStyle get body => _s(14, FontWeight.w400, h: 1.43);
  TextStyle get bodyStrong => _s(14, FontWeight.w600, h: 1.43);
  TextStyle get caption => _s(12, FontWeight.w500, h: 1.33, c: k.textSecondary);

  /// Uppercase labels ("TODAY'S PROTOCOL", "WORK", "REST").
  TextStyle get label => _s(12, FontWeight.w600, h: 1.33, ls: 0.6, c: k.textSecondary);
  TextStyle get labelSm => _s(11, FontWeight.w600, h: 1.27, ls: 0.45, c: k.textSecondary);
  TextStyle get unit => _s(13, FontWeight.w500, h: 1.23, ls: 0.26, c: k.textSecondary);

  /// Live getallen (glucose, gewicht, BPM).
  TextStyle get metric => _s(44, FontWeight.w700, h: 1.09, ls: -1.3, tab: true);
  TextStyle get metricMd => _s(28, FontWeight.w700, h: 1.1, ls: -0.6, tab: true);
  TextStyle get metricSm => _s(20, FontWeight.w700, h: 1.1, ls: -0.3, tab: true);

  /// De rondetimer: leesbaar vanaf een paar meter op de mat.
  TextStyle get timer => _s(88, FontWeight.w800, h: 1.0, ls: -3.5, tab: true);
}

extension KineticThemeX on BuildContext {
  KineticColors get k => Theme.of(this).extension<KineticColors>() ?? KineticColors.dark;
  KineticTypography get t => KineticTypography(k);

  /// Ruimte onderin voor de Android-navigatieknoppen / gesturebalk.
  double get bottomInset => MediaQuery.viewPaddingOf(this).bottom;
}

abstract final class KRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

/// Standaard paginapadding: 16px marges en genoeg ruimte onderin zodat de
/// laatste kaart nooit onder de systeemknoppen valt.
EdgeInsets pagePadding(BuildContext context, {double top = 8, double extraBottom = 32}) =>
    EdgeInsets.fromLTRB(16, top, 16, extraBottom + context.bottomInset);

ThemeData kineticTheme(KineticColors k) {
  final dark = k.isDark;
  final scheme = ColorScheme(
    brightness: k.brightness,
    primary: k.primary,
    onPrimary: k.onPrimary,
    secondary: k.accent,
    onSecondary: k.onPrimary,
    surface: k.surface,
    onSurface: k.text,
    surfaceContainerLowest: k.canvas,
    surfaceContainerLow: k.surface,
    surfaceContainer: k.surface,
    surfaceContainerHigh: k.well,
    surfaceContainerHighest: k.well,
    onSurfaceVariant: k.textSecondary,
    error: k.danger,
    onError: Colors.white,
    outline: k.borderStrong,
    outlineVariant: k.border,
  );
  final t = KineticTypography(k);
  final base = ThemeData(
    useMaterial3: true,
    brightness: k.brightness,
    colorScheme: scheme,
    fontFamily: KineticTypography.family,
    scaffoldBackgroundColor: k.canvas,
    canvasColor: k.canvas,
    extensions: [k],
  );
  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(KRadius.md),
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: k.canvas,
      foregroundColor: k.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t.title,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: k.brightness,
        systemNavigationBarColor: k.surface,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
    ),
    dividerTheme: DividerThemeData(color: k.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? k.well : k.text,
      contentTextStyle: t.body.copyWith(color: dark ? k.text : k.canvas),
      actionTextColor: k.accent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.surface,
      modalBackgroundColor: k.surface,
      modalBarrierColor: dark ? const Color(0xB3000000) : const Color(0x33000000),
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: k.borderStrong,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(KRadius.xl)),
        side: BorderSide(color: k.borderStrong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface,
      elevation: 0,
      titleTextStyle: t.title,
      contentTextStyle: t.body.copyWith(color: k.textSecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.xl),
        side: BorderSide(color: k.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.well,
      labelStyle: t.caption,
      floatingLabelStyle: t.caption.copyWith(color: k.accent),
      hintStyle: t.body.copyWith(color: k.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: outline(k.border),
      enabledBorder: outline(k.border),
      focusedBorder: outline(k.primary, 1.5),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: k.primary, selectionHandleColor: k.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? k.onPrimary : k.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? k.primary : k.well,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? k.primary : k.borderStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? k.primary : const Color(0x00000000),
      ),
      checkColor: WidgetStateProperty.all(k.onPrimary),
      side: BorderSide(color: k.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: k.primary, linearTrackColor: k.well),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: k.primary,
        foregroundColor: k.onPrimary,
        minimumSize: const Size(48, 48),
        textStyle: t.bodyStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: k.accent, minimumSize: const Size(48, 48), textStyle: t.bodyStrong),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: k.text,
        side: BorderSide(color: k.border),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
      ),
    ),
    iconTheme: IconThemeData(color: k.textSecondary),
    listTileTheme: ListTileThemeData(iconColor: k.textSecondary, textColor: k.text),
  );
}

// ---------------------------------------------------------------------------
// Legacy (2.0-eerste-versie). Alleen nog voor schermen die nog niet naar
// context.k / context.t zijn omgezet; wordt verwijderd zodra alles om is.

abstract final class KColor {
  static const bg = Color(0xFF0B0F14);
  static const surface = Color(0xFF121820);
  static const surfaceContainer = Color(0xFF121820);
  static const surfaceHigh = Color(0xFF1C2430);
  static const surfaceElevated = Color(0xFF283546);
  static const teal = Color(0xFF14B8A6);
  static const tealLight = Color(0xFF2DD4BF);
  static const tealGlow = Color(0x4014B8A6);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF10B981);
  static const purple = Color(0xFFA855F7);
  static const blue = Color(0xFF3B82F6);
  static const text = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFF1C2430);
}

abstract final class KText {
  static const family = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];
  static const display = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1, color: KColor.text);
  static const title = TextStyle(fontFamily: family, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: KColor.text);
  static const subtitle = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700, color: KColor.text);
  static const body = TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4, color: KColor.text);
  static const caption = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500, height: 1.35, color: KColor.textSecondary);
  static const eyebrow = TextStyle(fontFamily: family, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: KColor.textMuted);
  static const metric = TextStyle(fontFamily: family, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.0, color: KColor.text, fontFeatures: _tabular);
  static const metricSmall = TextStyle(fontFamily: family, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.0, color: KColor.text, fontFeatures: _tabular);
  static const timer = TextStyle(fontFamily: family, fontSize: 104, fontWeight: FontWeight.w900, letterSpacing: -4, height: 1.0, color: KColor.text, fontFeatures: _tabular);
}
