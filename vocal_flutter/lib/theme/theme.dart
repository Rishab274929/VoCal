// Editorial-voice design system — Flutter port of Theme.swift.
// Dark-first, ink + lime + coral, New York-like serif (Newsreader) display
// + system body. Every token is opinionated.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Palette {
  // Surfaces
  static const ink = Color(0xFF0A0A0B); // base canvas
  static const inkRaised = Color(0xFF121214); // first elevation
  static const inkSurface = Color(0xFF18181C); // cards / sheets
  static const inkElevated = Color(0xFF1F1F24); // popovers / chips
  static final hairline = Colors.white.withOpacity(0.07);
  static final hairlineStrong = Colors.white.withOpacity(0.13);

  // Text
  static const bone = Color(0xFFF6F4EC); // primary on dark — warm ivory
  static const ash = Color(0xFFBDBBB2); // secondary on dark
  static const smoke = Color(0xFF86847B); // tertiary on dark

  // Brand voltage
  static const voltage = Color(0xFFE5FF59); // lime — the "voice" accent
  static const voltageDeep = Color(0xFFB7D03A);
  static const pulse = Color(0xFFFF5436); // coral — the "energy" accent
  static const pulseDeep = Color(0xFFE03C1F);

  // Macros
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
  static const voltage = LinearGradient(
    colors: [Color(0xFFF6FF80), Palette.voltage, Palette.voltageDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const pulse = LinearGradient(
    colors: [Color(0xFFFF8264), Palette.pulse, Palette.pulseDeep],
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
    colorScheme: const ColorScheme.dark(
      surface: Palette.ink,
      onSurface: Palette.bone,
      primary: Palette.voltage,
      onPrimary: Palette.ink,
      secondary: Palette.pulse,
      onSecondary: Palette.bone,
      error: Palette.pulse,
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
      focusColor: Palette.voltage,
    ),
    // Disable Material's "page transition" cross-fade on Android since our
    // shell is in a single Scaffold + custom tab swaps.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
