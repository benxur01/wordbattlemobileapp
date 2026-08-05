import 'package:flutter/material.dart';

/// Colors and text styles ported 1:1 from the Word Battle design file's
/// inline CSS (hex/rgba values kept identical).
class WBColors {
  WBColors._();

  static const bg = Color(0xFF08080D);
  static const bgPanel = Color(0xFF0A0A11);
  /// The phone body colour behind the screens (`#050508`), used where the
  /// design punches a ring out of a badge.
  static const bgDeep = Color(0xFF050508);
  static const text = Color(0xFFF4F3F8);

  static const amber = Color(0xFFF7B733);
  static const amberDark = Color(0xFFE0921A);
  static const amberDark2 = Color(0xFFDE7F16);
  static const amberDark3 = Color(0xFFDE8016);
  static const amberInk = Color(0xFF120B01);
  static const amberInk2 = Color(0xFF100C02);

  static const green = Color(0xFF35D07F);
  static const greenInk = Color(0xFF06170F);

  static const red = Color(0xFFF2545B);
  static const redSoft = Color(0xFFFF8A8F);

  static const flameTop = Color(0xFFFF8A3C);
  static const flameBottom = Color(0xFFF2545B);
  static const flameText = Color(0xFFFF9A55);

  static const purple = Color(0xFF4A3AA8);
  static const purpleDark = Color(0xFF2A1F6B);
  static const purpleText = Color(0xFFCFC7FF);

  static const indigo = Color(0xFF7C8AFF);
  static const indigoDark = Color(0xFF4C58D8);
  static const indigoText = Color(0xFF9AA6FF);

  static const rose = Color(0xFFB0355E);
  static const roseDark = Color(0xFF6B1E3C);
  static const roseText = Color(0xFFFFD0DF);

  static const teal = Color(0xFF2E7D6B);
  static const tealDark = Color(0xFF12463C);
  static const tealText = Color(0xFFB9F0E2);

  static const grey = Color(0xFF5B5B6B);
  static const greyDark = Color(0xFF2C2C38);
  static const greyText = Color(0xFFD9D9E6);

  static const blue = Color(0xFF3A6DB0);
  static const blueDark = Color(0xFF17325E);
  static const blueText = Color(0xFFC3DDFF);

  static const amber8 = Color(0xFF8A5A2B);
  static const amber8Dark = Color(0xFF4A2E12);
  static const amber8Text = Color(0xFFF2D6B3);

  static Color textA(double a) => text.withValues(alpha: a);
  static Color amberA(double a) => amber.withValues(alpha: a);
  static Color greenA(double a) => green.withValues(alpha: a);
  static Color redA(double a) => red.withValues(alpha: a);
  static Color whiteA(double a) => Colors.white.withValues(alpha: a);
  static Color indigoA(double a) => indigo.withValues(alpha: a);

  static const cardFill = Color.fromRGBO(255, 255, 255, .045);
  static const cardBorder = Color.fromRGBO(255, 255, 255, .09);
}

class WBText {
  WBText._();

  /// Neither bundled face covers the IPA marks in the practice screen's
  /// transcription (ˈ, ɑ, ː), so the platform font takes those glyphs instead
  /// of drawing tofu.
  static const _fallback = ['Roboto', 'sans-serif'];

  /// `letterSpacing` is given in **em**, exactly as the design's CSS writes it
  /// (`letter-spacing:.2em`), and is converted to logical pixels here. Passing
  /// the CSS number straight into [TextStyle.letterSpacing] — which is in
  /// pixels — silently dropped nearly all of the design's tracking (.2em on an
  /// 11px label is 2.2px, not 0.2px), which is why the mono caps labels looked
  /// tight compared to the source.
  static TextStyle grotesk({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = WBColors.text,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontFamilyFallback: _fallback,
        // Space Grotesk is bundled as a variable font: the weight axis has to
        // be driven explicitly, otherwise every weight renders as Regular.
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing == null ? null : letterSpacing * size,
      );

  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = WBColors.text,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing == null ? null : letterSpacing * size,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

const wbAmberGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.amber, WBColors.amberDark],
);

const wbPurpleGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.purple, WBColors.purpleDark],
);

const wbTealGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.teal, WBColors.tealDark],
);

const wbRoseGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.rose, WBColors.roseDark],
);

const wbGreyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.grey, WBColors.greyDark],
);

const wbBlueGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.blue, WBColors.blueDark],
);

const wbAmber8Gradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.amber8, WBColors.amber8Dark],
);

const wbIndigoGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [WBColors.indigo, WBColors.indigoDark],
);

const wbFlameGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [WBColors.flameTop, WBColors.flameBottom],
);
