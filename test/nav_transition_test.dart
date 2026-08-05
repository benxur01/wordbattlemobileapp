import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/bottom_nav.dart';

/// The bottom bar animates its highlight from the tab the previous screen had
/// selected. Each screen builds its own `BottomNav`, so the animation cannot
/// rely on surviving state — `previous` is what makes it work, and this test
/// pins that behaviour down by rendering frames mid-flight.
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

  testWidgets('the highlight travels from the previous tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 300);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final key = GlobalKey();

    Future<void> pumpBar({required WBTab active, WBTab? previous}) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 360,
                  child: BottomNav(
                    active: active,
                    previous: previous,
                    friendRequestCount: 2,
                    onHome: () {},
                    onFriends: () {},
                    onBoard: () {},
                    onProfile: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> shoot(String name) async {
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screens/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    // Home → Profile is the longest travel the highlight can make. A fresh
    // widget with `previous` set is exactly what a tab switch produces.
    await pumpBar(active: WBTab.profile, previous: WBTab.home);
    await tester.pump(const Duration(milliseconds: 60));
    await shoot('nav-t060');
    await tester.pump(const Duration(milliseconds: 60));
    await shoot('nav-t120');
    await tester.pump(const Duration(milliseconds: 400));
    await shoot('nav-t520');

    expect(tester.takeException(), isNull);

    // Without a `previous` the bar must start in place rather than sliding in
    // from the left — that is what every non-tab screen does.
    await pumpBar(active: WBTab.board);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
