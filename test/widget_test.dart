import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:word_battle/main.dart';

/// Boot behaviour of the live app. With no saved token the session restore
/// finishes without touching the network, so the app must land on onboarding.
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
  });

  testWidgets('a first launch lands on onboarding', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2352);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WordBattleApp());
    // One frame for the loading screen, then the restore completes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WORD\nBATTLE'), findsOneWidget);
    expect(find.text('Google orqali kirish'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The app owns a periodic ticker; unmount it so the test can finish.
    await tester.pumpWidget(const SizedBox());
  });
}
