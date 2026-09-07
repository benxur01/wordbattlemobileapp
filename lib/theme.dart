import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The appearance the player picked in their profile.
enum WBThemeMode { system, light, dark }

/// Which palette [WBColors] resolves against, and the player's standing choice
/// behind it.
///
/// The colours are read as plain statics from every screen, so the brightness
/// they resolve against has to live somewhere global rather than in an
/// [InheritedWidget]. The trade-off is that nothing rebuilds by itself when it
/// flips: whoever draws the app has to listen to this notifier, and a widget
/// built `const` will keep the palette it was first built with until something
/// else rebuilds it. Hence the missing `const` on anything that reads a colour.
class WBTheme extends ChangeNotifier {
  WBTheme._();

  static final WBTheme instance = WBTheme._();

  static const _prefsKey = 'wb_theme_mode';

  WBThemeMode _mode = WBThemeMode.system;
  Brightness _platform = Brightness.dark;

  /// What the player chose. [WBThemeMode.system] follows [_platform].
  static WBThemeMode get mode => instance._mode;

  /// The palette actually being drawn.
  static Brightness get brightness => switch (instance._mode) {
        WBThemeMode.light => Brightness.light,
        WBThemeMode.dark => Brightness.dark,
        WBThemeMode.system => instance._platform,
      };

  static bool get isLight => brightness == Brightness.light;

  /// Reads back the stored choice. Awaited before the first frame so the app
  /// never opens in the wrong palette and flips a moment later.
  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final restored = WBThemeMode.values.where((m) => m.name == stored).firstOrNull;
    if (restored != null) instance._mode = restored;
  }

  /// The profile screen's appearance picker.
  static Future<void> select(WBThemeMode next) async {
    if (instance._mode != next) {
      instance._mode = next;
      instance.notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.name);
  }

  /// The phone's own light/dark setting, which [WBThemeMode.system] follows.
  static void followPlatform(Brightness platform) {
    if (instance._platform == platform) return;
    instance._platform = platform;
    if (instance._mode == WBThemeMode.system) instance.notifyListeners();
  }
}

/// Colors and text styles ported 1:1 from the Word Battle design file's
/// inline CSS (hex/rgba values kept identical) for the dark palette, with a
/// light counterpart for each token in the same role.
class WBColors {
  WBColors._();

  static Color _pick(Color dark, Color light) => WBTheme.isLight ? light : dark;

  static Color get bg => _pick(const Color(0xFF262626), const Color(0xFFF5F3ED));
  static Color get bgPanel => _pick(const Color(0xFF2C2C2A), const Color(0xFFFFFFFF));

  /// The phone body colour behind the screens (`#1F1F1E`), used where the
  /// design punches a ring out of a badge.
  static Color get bgDeep => _pick(const Color(0xFF1F1F1E), const Color(0xFFE4E1D7));
  static Color get text => _pick(const Color(0xFFEDEBE4), const Color(0xFF1F1E1A));

  /// Amber reads as a fill on the dark palette and as a label on the light one,
  /// so the light value is deep enough to be read at 9.5px rather than being
  /// the same yellow at a different lightness.
  static Color get amber => _pick(const Color(0xFFF7B733), const Color(0xFF8F5405));
  static Color get amberDark => _pick(const Color(0xFFE0921A), const Color(0xFF6E3F03));
  static Color get amberInk => _pick(const Color(0xFF120B01), const Color(0xFFFFF7E8));

  /// Primary action / self / active-state accent, used for CTAs, own-turn
  /// indicators, active nav/tabs, and self-highlighted rows.
  static Color get accent => blue;
  static Color get accentDark => blueDark;
  static Color get accentInk => blueText;
  static Color accentA(double a) => blueA(a);

  static Color get green => _pick(const Color(0xFF35D07F), const Color(0xFF0B7A42));
  static Color get greenInk => _pick(const Color(0xFF06170F), const Color(0xFFF1FFF7));

  static Color get red => _pick(const Color(0xFFF2545B), const Color(0xFFC0303A));
  static Color get redSoft => _pick(const Color(0xFFFF8A8F), const Color(0xFFA8232C));

  static Color get flameTop => _pick(const Color(0xFFFF8A3C), const Color(0xFFE2621A));
  static Color get flameBottom => _pick(const Color(0xFFF2545B), const Color(0xFFC0303A));
  static Color get flameText => _pick(const Color(0xFFFF9A55), const Color(0xFFA83C0C));

  static Color get purple => _pick(const Color(0xFF4A3AA8), const Color(0xFF4A3AA8));
  static Color get purpleDark => _pick(const Color(0xFF2A1F6B), const Color(0xFF2A1F6B));
  static Color get purpleText => _pick(const Color(0xFFCFC7FF), const Color(0xFFEFECFF));

  /// The one accent family that is drawn straight on the background as a label
  /// (the practice screen, the 2v2 tag), so its light value is a deep indigo
  /// rather than the dark palette's pastel.
  static Color get indigo => _pick(const Color(0xFF7C8AFF), const Color(0xFF414ECB));
  static Color get indigoDark => _pick(const Color(0xFF4C58D8), const Color(0xFF2B34A0));
  static Color get indigoText => _pick(const Color(0xFF9AA6FF), const Color(0xFF2E37A8));
  static Color get indigoInk => _pick(const Color(0xFF0B0B16), const Color(0xFFEEF0FF));

  static Color get rose => _pick(const Color(0xFFB0355E), const Color(0xFFA32A55));
  static Color get roseDark => _pick(const Color(0xFF6B1E3C), const Color(0xFF6B1E3C));
  static Color get roseText => _pick(const Color(0xFFFFD0DF), const Color(0xFFFFE4EC));

  static Color get teal => _pick(const Color(0xFF2E7D6B), const Color(0xFF1F6B5A));
  static Color get tealDark => _pick(const Color(0xFF12463C), const Color(0xFF12463C));
  static Color get tealText => _pick(const Color(0xFFB9F0E2), const Color(0xFFE3FBF4));

  static Color get grey => _pick(const Color(0xFF5B5B6B), const Color(0xFF565663));
  static Color get greyDark => _pick(const Color(0xFF2C2C38), const Color(0xFF2C2C38));
  static Color get greyText => _pick(const Color(0xFFD9D9E6), const Color(0xFFEDEDF5));

  static Color get blue => _pick(const Color(0xFF3A6DB0), const Color(0xFF2F5C99));
  static Color get blueDark => _pick(const Color(0xFF17325E), const Color(0xFF1D3F6E));
  static Color get blueText => _pick(const Color(0xFFC3DDFF), const Color(0xFFEAF3FF));

  static Color get amber8 => _pick(const Color(0xFF8A5A2B), const Color(0xFF7A4C22));
  static Color get amber8Dark => _pick(const Color(0xFF4A2E12), const Color(0xFF4A2E12));
  static Color get amber8Text => _pick(const Color(0xFFF2D6B3), const Color(0xFFFBEEDC));

  /// What darkens the screen behind a sheet, and the surface of the sheet
  /// itself. The scrim has to darken in both palettes — a light wash over a
  /// light screen would leave the sheet floating on nothing.
  static Color get scrim => _pick(bgDeep.withValues(alpha: .82), const Color.fromRGBO(24, 22, 18, .5));

  /// The tint over the bottom nav's blur, and the shadow it is lifted by.
  static Color get glass => _pick(const Color.fromRGBO(22, 21, 31, .12), const Color.fromRGBO(255, 255, 255, .55));
  static Color get shadow => _pick(const Color.fromRGBO(0, 0, 0, .45), const Color.fromRGBO(31, 30, 26, .14));

  /// The error strip's own surface — a red-tinted panel rather than a wash, so
  /// it stays readable over whatever screen it covers.
  static Color get bannerFill => _pick(const Color(0xFF241B1D), const Color(0xFFFDEAEB));

  /// Muted text. Mid-grey sits far closer to white than to black in luminance,
  /// so the same alpha that gives 4:1 against the dark background gives barely
  /// 3:1 against the light one — the light palette leans on a little more ink
  /// to hold the design's own contrast.
  static Color textA(double a) => text.withValues(alpha: WBTheme.isLight ? math.min(1.0, a * 1.2) : a);

  /// A wash of the foreground over the app surface: card fills, hairlines and
  /// borders. White on the dark palette, ink on the light one — the name is the
  /// design's, the role is "whatever lifts a surface off the background".
  static Color whiteA(double a) => _pick(Colors.white, const Color(0xFF1F1E1A)).withValues(alpha: a);

  static Color amberA(double a) => amber.withValues(alpha: a);
  static Color greenA(double a) => green.withValues(alpha: a);
  static Color redA(double a) => red.withValues(alpha: a);
  static Color indigoA(double a) => indigo.withValues(alpha: a);
  static Color blueA(double a) => blue.withValues(alpha: a);
  static Color tealA(double a) => teal.withValues(alpha: a);

  static Color get cardFill => textA(.045);
  static Color get cardBorder => textA(.09);
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
    Color? color,
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
        color: color ?? WBColors.text,
        height: height,
        letterSpacing: letterSpacing == null ? null : letterSpacing * size,
      );

  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: weight,
        color: color ?? WBColors.text,
        height: height,
        letterSpacing: letterSpacing == null ? null : letterSpacing * size,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

LinearGradient _gradient(Color from, Color to) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [from, to],
    );

LinearGradient get wbAmberGradient => _gradient(WBColors.amber, WBColors.amberDark);

LinearGradient get wbAccentGradient => wbBlueGradient;

LinearGradient get wbPurpleGradient => _gradient(WBColors.purple, WBColors.purpleDark);

LinearGradient get wbTealGradient => _gradient(WBColors.teal, WBColors.tealDark);

LinearGradient get wbRoseGradient => _gradient(WBColors.rose, WBColors.roseDark);

LinearGradient get wbGreyGradient => _gradient(WBColors.grey, WBColors.greyDark);

LinearGradient get wbBlueGradient => _gradient(WBColors.blue, WBColors.blueDark);

LinearGradient get wbAmber8Gradient => _gradient(WBColors.amber8, WBColors.amber8Dark);

LinearGradient get wbIndigoGradient => _gradient(WBColors.indigo, WBColors.indigoDark);

LinearGradient get wbFlameGradient => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [WBColors.flameTop, WBColors.flameBottom],
    );

/// The surface of the screens that slide up over another one — the incoming
/// invite, the tournament invite.
LinearGradient get wbSheetGradient => WBTheme.isLight
    ? _gradient(const Color.fromRGBO(255, 255, 255, .98), const Color.fromRGBO(241, 239, 232, .98))
    : _gradient(const Color.fromRGBO(30, 28, 44, .98), const Color.fromRGBO(12, 12, 20, .98));
