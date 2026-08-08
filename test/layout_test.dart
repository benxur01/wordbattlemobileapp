import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';


/// Without this the test binding measures every string in its placeholder
/// font, where each glyph is a full em square — text comes out ~80% wider than
/// Space Grotesk and every row reports a false overflow.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(File(path).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await loader.load();
  }

  await load('SpaceGrotesk', ['assets/fonts/SpaceGrotesk-VariableFont_wght.ttf']);
  await load('JetBrainsMono', [
    'assets/fonts/JetBrainsMono-Regular.ttf',
    'assets/fonts/JetBrainsMono-Medium.ttf',
    'assets/fonts/JetBrainsMono-SemiBold.ttf',
    'assets/fonts/JetBrainsMono-Bold.ttf',
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final entry in buildScreens().entries) {
    testWidgets('${entry.key} lays out on a 360×784dp phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2352);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(canvas(entry.value));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  }

  // The three screens with a text field, with the keyboard covering 320dp.
  for (final key in ['onb2-idle', 'onb2-taken', 'duel', 'duel-error', 'duel-substituted', 'friends']) {
    testWidgets('$key lays out with the keyboard open', (tester) async {
      tester.view.physicalSize = const Size(1080, 2352);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(canvas(buildScreens()[key]!, keyboardInset: keyboard));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  }
}
