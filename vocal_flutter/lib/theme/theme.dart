// Editorial-voice design system — Flutter port of Theme.swift.
// Dark-first MONOCHROME: ink on bone with pure paper-white as the single
// emphasis signal. Matches the starfield-on-black logo. New York-like
// serif (Newsreader) display + system body.
//
// Design-language pivot notes:
//  - `voltage` (lime) and `pulse` (coral) hex constants are PRESERVED so
//    legacy screen references still compile, but the canonical accent is
//    now `paper` (pure white). Use `bone` for an over-goal / subtle warn.
//  - Macros keep their hues — they're the only color in the system and
//    they map to a tangible thing.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Palette {
  // Surfaces
  static const ink = Color(0xFF0A0A0B); // base canvas — deep black
  static const inkRaised = Color(0xFF121214); // first elevation
  static const inkSurface = Color(0xFF18181C); // cards / sheets
  static const inkElevated = Color(0xFF1F1F24); // popovers / chips
  static const hairline = Color(0xFF1F1E1B); // subtle borders
  static const hairlineStrong = Color(0xFF2E2D29); // visible borders

  // Text
  static const paper = Color(0xFFFFFFFF); // pure white — hero numerals & emphasis
  static const bone = Color(0xFFF5F2EA); // primary on dark — warm off-white
  static const ash = Color(0xFFBDBBB2); // secondary on dark
  static const smoke = Color(0xFF86847B); // tertiary on dark

  // Legacy accent constants — PRESERVED so screens that still reference
  // them compile. New work MUST use `paper` for emphasis.
  static const voltage = Color(0xFFE5FF59); // legacy lime
  static const voltageDeep = Color(0xFFB7D03A);
  static const pulse = Color(0xFFFF5436); // legacy coral
  static const pulseDeep = Color(0xFFE03C1F);

  // Macros — the only chromatic information in the system.
  static const protein = Color(0xFFFF7A8A); // dusty rose
  static const carbs = Color(0xFFFFD466); // amber
  static const fat = Color(0xFF7BB7FF); // soft sky
  static const fiber = Color(0xFFB7D03A); // moss
}

class Spacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 28;
  static const double xl = 44;
  static const double xxl = 64;
}

class Radii {
  static const double xs = 8;
  static const double sm = 14;
  static const double md = 22;
  static const double lg = 30;
  static const double xl = 44;
}

class AppType {
  /// Hero serif numerals (kcal remaining, BF%) — New York analogue.
  static TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w400,
    bool italic = false,
    Color color = Palette.bone,
  }) {
    return GoogleFonts.newsreader(
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      height: 1.05,
    );
  }

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = Palette.bone,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.25,
    );
  }

  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = Palette.bone,
  }) {
    return GoogleFonts.robotoMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Tracked all-caps eyebrow label.
  static TextStyle eyebrow({Color color = Palette.smoke}) {
    return TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
      color: color,
    );
  }
}

class Gradients {
  // Monochrome pivot: voltage/pulse keep their NAMES (legacy callers
  // import them) but render as pure white ramps so the screen reads as
  // one editorial monochrome surface.
  static const voltage = LinearGradient(
    colors: [Palette.paper, Palette.paper, Palette.bone],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const pulse = LinearGradient(
    colors: [Palette.paper, Palette.bone, Palette.ash],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const ink = LinearGradient(
    colors: [Palette.ink, Palette.inkRaised],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Editorial card — soft elevated surface with hairline border.
BoxDecoration cardDecoration({
  double radius = Radii.md,
  Color? fill,
  Color? border,
  double borderWidth = 1,
}) {
  return BoxDecoration(
    color: fill ?? Palette.inkSurface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? Palette.hairline, width: borderWidth),
  );
}

/// Tracked, tiny, all-caps eyebrow text widget.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  const Eyebrow(this.text, {super.key, this.color = Palette.smoke});

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: AppType.eyebrow(color: color));
  }
}

ThemeData buildAppTheme() {
  // Material is intentionally suppressed everywhere we own UI — no ripples,
  // no glow splashes, no AppBar tints, no hover overlays. The editorial
  // design language renders its own state hits via Container/Border swaps.
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Palette.ink,
    canvasColor: Palette.ink,
    // Monochrome pivot: primary and secondary both drive off `paper`.
    // Material 3 sinks (default buttons, switches, focus rings) inherit
    // pure white as the accent. Error stays as bone so a thrown SnackBar
    // doesn't slam coral into the otherwise grayscale surface.
    colorScheme: const ColorScheme.dark(
      surface: Palette.ink,
      onSurface: Palette.bone,
      primary: Palette.paper,
      onPrimary: Palette.ink,
      secondary: Palette.paper,
      onSecondary: Palette.ink,
      error: Palette.bone,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Palette.bone,
          displayColor: Palette.bone,
          decorationColor: Palette.bone,
        ),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    dividerColor: Palette.hairline,
    // Bottom sheets ride on Palette.ink, not Material's default surface
    // tint that bleeds purple over our dark canvas.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.ink,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Palette.ink,
      modalBarrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    // We don't use AppBars but if one slips in (e.g. via a 3p plugin) make
    // sure it doesn't render a Material teal-ish tint.
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.ink,
      foregroundColor: Palette.bone,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    // Suppress Material 3's TextField active outline + label color drift.
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      hintStyle: TextStyle(color: Palette.smoke),
      labelStyle: const TextStyle(color: Palette.ash),
      // Monochrome pivot: focus color is paper.
      focusColor: Palette.paper,
    ),
    // Disable Material's "page transition" cross-fade on Android since our
    // shell is in a single Scaffold + custom tab swaps.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
