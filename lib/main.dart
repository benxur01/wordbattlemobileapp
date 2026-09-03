import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The mockup draws its own dark status bar over the artwork. Match it on a
  // real device: edge-to-edge, fully transparent system bars, light icons.
  // Without this Android paints an opaque bar in a colour the design never has.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Portrait only — the design has no landscape layout, and rotating the phone
  // would stretch the fixed-width canvas into something the design never had.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const WordBattleApp());
}

class WordBattleApp extends StatelessWidget {
  const WordBattleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Word Battle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: WBColors.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: WBColors.accent, brightness: Brightness.dark),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: WBColors.accent,
          selectionColor: Color.fromRGBO(247, 183, 51, .3),
          selectionHandleColor: WBColors.accent,
        ),
      ),
      builder: (context, child) {
        // Every measurement in the design is a fixed pixel value, so an OS-level
        // font-size setting above 100% overflows the layouts instead of scaling
        // them. AppRoot already scales the whole canvas by device width, which
        // is what keeps the UI legible on small phones.
        return MediaQuery.withNoTextScaling(child: child!);
      },
      home: const Scaffold(
        // AppRoot subtracts the keyboard inset from its own canvas; letting the
        // Scaffold resize as well would shrink the layout twice.
        resizeToAvoidBottomInset: false,
        body: AppRoot(),
      ),
    );
  }
}
