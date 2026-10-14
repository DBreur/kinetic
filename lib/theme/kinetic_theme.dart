// kinetic_theme.dart
//
// Design tokens + ThemeData voor Kinetic ("Kinetic Sambo Metric", zie
// design/stitch_sambo_diabetic_fitness_tracker/kinetic_sambo_metric/DESIGN.md).
//
// De namen in AppColor/AppText zijn bewust gelijk aan die van Uchivo, zodat
// alle bestaande schermen meteen in de Kinetic-stijl renderen:
//   green  = Electric Ice  — in bereik, stabiel, glucose, herstel
//   teal   = Kinetic Pink  — techniek / training / belasting
//   amber  = afwijking glucose (alleen glucose)
//   red    = hypo-alarm (alleen hypo)
// Nieuwe Kinetic-schermen gebruiken daarnaast de expliciete tokens
// (coral, ice, slate, surfaceHigh, …).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColor {
  // Ondergronden — matte carbon, diepte via kleurstappen, geen schaduw.
  static const bg = Color(0xFF10141A); // surface
  static const bgDeep = Color(0xFF0A0E14); // surface-container-lowest
  static const surface = Color(0xFF181C22); // surface-container-low (kaart)
  static const surfaceRaised = Color(0xFF1C2026); // surface-container
  static const surfaceMuted = Color(0xFF262A31); // surface-container-high
  static const surfaceHigh = Color(0xFF262A31);
  static const surfaceHighest = Color(0xFF31353C);
  static const navBar = Color(0xFF0D1117);

  // Lijnen — haarlijnen, spaarzaam.
  static const line = Color(0x14FFFFFF);
  static const lineSoft = Color(0x0DFFFFFF);
  static const lineStrong = Color(0x24FFFFFF);

  // Inkt
  static const ink = Color(0xFFDFE2EB); // on-surface
  static const inkMuted = Color(0xFFB9C8DE); // tertiary
  static const inkFaint = Color(0xFF8392A6); // tertiary-container
  static const inkGhost = Color(0xFF5A6577);

  // Kinetic-tokens
  static const coral = Color(0xFFFF516A); // primary-container — kernactie
  static const coralSoft = Color(0xFFFFB2B7); // primary
  static const coralFixed = Color(0xFFFFDADB); // primary-fixed
  static const coralInk = Color(0xFF40000D); // tekst op koraal/roze
  static const coralWash = Color(0x33FF516A);
  static const ice = Color(0xFF7BD0FF); // secondary
  static const iceDeep = Color(0xFF00A6E0); // secondary-container
  static const iceInk = Color(0xFF001E2C);
  static const slate = Color(0xFFB9C8DE);
  static const slateDim = Color(0xFF8392A6);

  // Status — in bereik (Electric Ice)
  static const green = iceDeep;
  static const greenBright = ice;
  static const greenInk = iceInk;
  static const greenWash = Color(0x1A38BDF8); // 10% vulling
  static const greenEdge = Color(0x5938BDF8); // 35% rand

  // Secundair — techniek / training (Kinetic Pink)
  static const teal = coralSoft;
  static const tealBright = coralFixed;
  static const tealWash = Color(0x1FFFB2B7);

  // Waarschuwing — alleen glucose
  static const amber = Color(0xFFF5B83D);
  static const amberBright = Color(0xFFFFD27A);
  static const amberInk = Color(0xFF2A1C05);
  static const amberWash = Color(0x17F5B83D);

  // Alarm — alleen hypo
  static const red = Color(0xFFFF3B4E);
  static const redBright = Color(0xFFFF8A95);
  static const redGround = Color(0xFF2A0D12); // volledige alarm-sheet
}

class AppRadius {
  static const chip = 99.0; // statuspillen
  static const sm = 4.0; // tags, inputvelden
  static const md = 8.0; // knoppen, compacte rijen
  static const lg = 8.0;
  static const xl = 12.0; // standaard kaart
  static const xxl = 12.0;
  static const sheet = 16.0; // bottom sheet
}

class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const gutter = 16.0; // horizontale schermmarge
  static const lg = 24.0;
  static const xl = 40.0;
}

/// Typografie.
///
/// Space Grotesk = cijfers, koppen, alles wat je van een meter afleest.
/// Geist = lopende tekst, labels en knoppen. Cijfers altijd tabulair.
class AppText {
  static const _tnum = [FontFeature.tabularFigures()];

  /// Glucosewaarde op het dashboard.
  static TextStyle get reading => GoogleFonts.spaceGrotesk(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.7,
    color: AppColor.ink,
    fontFeatures: _tnum,
  );

  /// Glucosewaarde in de alarm-sheet.
  static TextStyle get readingAlarm => GoogleFonts.spaceGrotesk(
    fontSize: 76,
    fontWeight: FontWeight.w700,
    height: 0.9,
    letterSpacing: -2.5,
    color: Colors.white,
    fontFeatures: _tnum,
  );

  /// headline-lg-mobile
  static TextStyle get display => GoogleFonts.spaceGrotesk(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.6,
    color: AppColor.ink,
  );

  /// headline-md
  static TextStyle get title => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.33,
    letterSpacing: -0.24,
    color: AppColor.ink,
  );

  /// headline-sm
  static TextStyle get cardTitle => GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.33,
    color: AppColor.ink,
  );

  /// label-metric — grote meetwaarde in een tegel.
  static TextStyle get metric => GoogleFonts.spaceGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.28,
    color: AppColor.ink,
    fontFeatures: _tnum,
  );

  static TextStyle get bodyLarge => GoogleFonts.geist(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColor.ink,
  );

  /// body-md
  static TextStyle get body => GoogleFonts.geist(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    color: AppColor.ink,
  );

  static TextStyle get bodyStrong => GoogleFonts.geist(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColor.ink,
  );

  /// body-sm
  static TextStyle get caption => GoogleFonts.geist(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.12,
    color: AppColor.inkFaint,
  );

  /// label-mono: klein, hoofdletters, ruime letterafstand.
  static TextStyle get overline => GoogleFonts.geist(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.27,
    letterSpacing: 1.3,
    color: AppColor.inkFaint,
    fontFeatures: _tnum,
  );

  static TextStyle get button => GoogleFonts.spaceGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.0,
    color: AppColor.coralInk,
  );

  static TextStyle get tab => GoogleFonts.geist(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.0,
  );
}

class KineticTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColor.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColor.bg,
        surfaceContainerLowest: AppColor.bgDeep,
        surfaceContainerLow: AppColor.surface,
        surfaceContainer: AppColor.surfaceRaised,
        surfaceContainerHigh: AppColor.surfaceHigh,
        surfaceContainerHighest: AppColor.surfaceHighest,
        primary: AppColor.coral,
        onPrimary: AppColor.coralInk,
        secondary: AppColor.ice,
        onSecondary: AppColor.iceInk,
        tertiary: AppColor.slate,
        error: AppColor.red,
        onError: AppColor.redGround,
        onSurface: AppColor.ink,
        onSurfaceVariant: AppColor.inkMuted,
        outline: AppColor.lineStrong,
        outlineVariant: AppColor.line,
      ),
      textTheme: GoogleFonts.geistTextTheme(
        base.textTheme,
      ).apply(bodyColor: AppColor.ink, displayColor: AppColor.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColor.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppText.cardTitle,
        foregroundColor: AppColor.ink,
      ),
      cardTheme: const CardThemeData(
        color: AppColor.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.coral,
          foregroundColor: AppColor.coralInk,
          disabledBackgroundColor: AppColor.surfaceHigh,
          minimumSize: const Size.fromHeight(52), // >= 44 dp raakvlak
          textStyle: AppText.button,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColor.ice,
          backgroundColor: AppColor.surface,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColor.ice),
          textStyle: AppText.bodyStrong,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColor.inkMuted,
          textStyle: AppText.bodyStrong,
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColor.bgDeep,
        labelStyle: AppText.body.copyWith(color: AppColor.inkFaint),
        hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          borderSide: BorderSide(color: AppColor.surfaceHighest),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          borderSide: BorderSide(color: AppColor.surfaceHighest),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          borderSide: BorderSide(color: AppColor.ice),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColor.iceInk
              : AppColor.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColor.ice
              : AppColor.surfaceHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColor.coralSoft,
        inactiveTrackColor: AppColor.surfaceHighest,
        thumbColor: AppColor.coralSoft,
        trackHeight: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColor.surfaceRaised,
        side: BorderSide.none,
        labelStyle: AppText.body,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColor.coral,
        foregroundColor: AppColor.coralInk,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColor.line,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColor.surfaceHighest,
        contentTextStyle: AppText.body,
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColor.navBar,
        indicatorColor: Colors.transparent,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? AppColor.coral
                : AppColor.inkFaint,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppText.tab.copyWith(
            color: s.contains(WidgetState.selected)
                ? AppColor.coral
                : AppColor.inkFaint,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColor.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColor.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
        ),
      ),
    );
  }
}

/// Hoort een waarde binnen bereik, aan de rand, of is het alarm?
/// Eén functie zodat kleurkeuze nooit per scherm afwijkt.
enum GlucoseState { low, warning, inRange, high }

GlucoseState glucoseStateFor(double mmol) {
  if (mmol < 3.9) return GlucoseState.low;
  if (mmol < 5.0) return GlucoseState.warning;
  if (mmol <= 10.0) return GlucoseState.inRange;
  return GlucoseState.high;
}

Color glucoseColor(GlucoseState s) => switch (s) {
  GlucoseState.low => AppColor.red,
  GlucoseState.warning => AppColor.amber,
  GlucoseState.inRange => AppColor.ice,
  GlucoseState.high => AppColor.amber,
};
