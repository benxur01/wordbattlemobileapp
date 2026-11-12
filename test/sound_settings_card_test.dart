import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_battle/audio/sound_effects.dart';
import 'package:word_battle/widgets/sound_settings_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffects.instance.resetForTesting();
  });

  tearDown(() {
    SoundEffects.instance.resetForTesting();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );
  }

  group('SoundSettingsCard widget tests', () {
    testWidgets('renders initial sound controls with defaults', (tester) async {
      final sfx = SoundEffects.instance;

      await tester.pumpWidget(wrap(SoundSettingsCard(soundEffects: sfx)));

      expect(find.text('Ovoz effektlari'), findsOneWidget);
      expect(find.text('Yoqilgan · 80% balandlik'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('Sinash'), findsOneWidget);

      final cupertinoSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const Key('sound_fx_switch')),
      );
      expect(cupertinoSwitch.value, isTrue);

      final slider = tester.widget<Slider>(
        find.byKey(const Key('sound_fx_volume_slider')),
      );
      expect(slider.value, closeTo(0.8, 0.001));
      expect(slider.onChanged, isNotNull);
    });

    testWidgets('toggling switch mutes audio, persists preference, and disables slider', (tester) async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      sfx.testPlaybackHandler = (effect, _) async => played.add(effect);

      await tester.pumpWidget(wrap(SoundSettingsCard(soundEffects: sfx)));

      // Tap switch to turn off sound (mute)
      await tester.tap(find.byKey(const Key('sound_fx_switch')));
      await tester.pumpAndSettle();

      expect(sfx.isMuted, isTrue);
      expect(find.text("O'chirilgan · ovozsiz rejim"), findsOneWidget);

      final disabledSlider = tester.widget<Slider>(
        find.byKey(const Key('sound_fx_volume_slider')),
      );
      expect(disabledSlider.onChanged, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SoundEffects.prefsMutedKey), isTrue);
      expect(played, isEmpty);

      // Tap switch again to re-enable sound -> plays preview chime
      await tester.tap(find.byKey(const Key('sound_fx_switch')));
      await tester.pumpAndSettle();

      expect(sfx.isMuted, isFalse);
      expect(find.text('Yoqilgan · 80% balandlik'), findsOneWidget);
      expect(played, [SoundEffect.wordSuccess]);
    });

    testWidgets('volume slider updates volume and percentage text', (tester) async {
      final sfx = SoundEffects.instance;

      await tester.pumpWidget(wrap(SoundSettingsCard(soundEffects: sfx)));

      final sliderFinder = find.byKey(const Key('sound_fx_volume_slider'));
      final Slider slider = tester.widget(sliderFinder);
      slider.onChanged!(0.5);
      await tester.pumpAndSettle();

      expect(sfx.volume, closeTo(0.5, 0.001));
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Yoqilgan · 50% balandlik'), findsOneWidget);
    });

    testWidgets('Sinash preview button plays sound only when unmuted', (tester) async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      sfx.testPlaybackHandler = (effect, _) async => played.add(effect);

      await tester.pumpWidget(wrap(SoundSettingsCard(soundEffects: sfx)));

      await tester.tap(find.byKey(const Key('sound_fx_preview_btn')));
      await tester.pumpAndSettle();
      expect(played, [SoundEffect.wordSuccess]);

      // Mute and try preview
      await sfx.setMuted(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sound_fx_preview_btn')));
      await tester.pumpAndSettle();
      // Should still be 1 played event
      expect(played.length, 1);
    });
  });
}
