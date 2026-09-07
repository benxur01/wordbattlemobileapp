import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read back before the first frame, so a player who chose light mode never
  // sees the dark palette flash past on launch.
  await WBTheme.restore();
  WBTheme.followPlatform(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  // The mockup draws its own status bar over the artwork. Match it on a real
  // device: edge-to-edge, fully transparent system bars. Which way the icons
  // point is decided per palette — see [_overlayStyle].
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Portrait only — the design has no landscape layout, and rotating the phone
  // would stretch the fixed-width canvas into something the design never had.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const WordBattleApp());
}

/// Transparent bars with icons that can be seen against whichever palette is
/// drawn behind them.
SystemUiOverlayStyle _overlayStyle() {
  final icons = WBTheme.isLight ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: WBTheme.brightness,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}

ThemeData _theme() {
  final brightness = WBTheme.brightness;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: WBColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: WBColors.accent, brightness: brightness),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: WBColors.accent,
      selectionColor: WBColors.amberA(.3),
      selectionHandleColor: WBColors.accent,
    ),
  );
}

class WordBattleApp extends StatefulWidget {
  const WordBattleApp({super.key});

  @override
  State<WordBattleApp> createState() => _WordBattleAppState();
}

class _WordBattleAppState extends State<WordBattleApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Only reaches the screens while the player's choice is
  /// [WBThemeMode.system] — [WBTheme.followPlatform] decides that.
  @override
  void didChangePlatformBrightness() {
    WBTheme.followPlatform(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WBTheme.instance,
      builder: (context, _) => MaterialApp(
        title: 'Word Battle',
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        builder: (context, child) {
          // Every measurement in the design is a fixed pixel value, so an OS-level
          // font-size setting above 100% overflows the layouts instead of scaling
          // them. AppRoot already scales the whole canvas by device width, which
          // is what keeps the UI legible on small phones.
          return MediaQuery.withNoTextScaling(child: child!);
        },
        // A second listener, because the first one cannot reach this: `home` is
        // handed to the navigator once and the route caches the page it built,
        // so rebuilding MaterialApp with a new `home` leaves the screens
        // untouched. Everything below here reads WBColors, so it has to be
        // rebuilt from inside the route instead.
        home: ListenableBuilder(
          listenable: WBTheme.instance,
          builder: (context, _) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: _overlayStyle(),
            child: Scaffold(
              // AppRoot subtracts the keyboard inset from its own canvas; letting
              // the Scaffold resize as well would shrink the layout twice.
              resizeToAvoidBottomInset: false,
              body: AppRoot(),
            ),
          ),
        ),
      ),
    );
  }
}
