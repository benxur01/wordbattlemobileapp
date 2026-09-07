import 'package:flutter/material.dart';

import 'admin/admin_root.dart';
import 'theme.dart';

/// The admin panel's entry point, built and shipped on its own:
///
///     flutter build web -t lib/main_admin.dart
///
/// It imports neither `main.dart` nor `app_root.dart`, and nothing under
/// `lib/screens/` imports anything under `lib/admin/`. That is what keeps the
/// panel out of the phone bundle entirely — tree shaking is not being relied on
/// here, the two apps simply never reference each other. What they do share is
/// the layer below both: the theme, the wire models, and the REST transport that
/// carries the token and parses the server's errors.
void main() {
  runApp(const WordBattleAdminApp());
}

class WordBattleAdminApp extends StatelessWidget {
  const WordBattleAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Word Battle — Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: WBColors.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: WBColors.amber, brightness: Brightness.dark),
        dividerColor: WBColors.cardBorder,
        // The phone app freezes text scaling because its layout is a fixed-width
        // canvas ported from a design file. This one is an ordinary responsive
        // page, so the browser's font-size setting is left alone.
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: WBColors.amber,
          selectionColor: WBColors.amberA(.3),
          selectionHandleColor: WBColors.amber,
        ),
        tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
      ),
      home: const AdminRoot(),
    );
  }
}
