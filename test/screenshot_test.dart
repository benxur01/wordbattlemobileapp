@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

/// Renders every screen to `build/screens/<name>.png` at the test phone's
/// resolution, for eyeballing against the design file. Run with:
///   flutter test test/screenshot_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final grotesk = FontLoader('SpaceGrotesk')
      ..addFont(File('assets/fonts/SpaceGrotesk-VariableFont_wght.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await grotesk.load();

    final mono = FontLoader('JetBrainsMono');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      mono.addFont(File('assets/fonts/JetBrainsMono-$f.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await mono.load();

    Directory('build/screens').createSync(recursive: true);
  });

  for (final entry in buildScreens().entries) {
    testWidgets('render ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2352);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: canvas(entry.value)));
      await tester.pump(const Duration(milliseconds: 500));

      // toImage/toByteData need the real event loop, not fake_async.
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screens/${entry.key}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
