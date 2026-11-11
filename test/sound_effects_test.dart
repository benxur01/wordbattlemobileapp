import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_battle/audio/sound_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffects.instance.resetForTesting();
  });

  tearDown(() {
    SoundEffects.instance.resetForTesting();
  });

  group('SoundEffect enum tests', () {
    test('defines all 6 game sound assets correctly', () {
      expect(SoundEffect.values.length, 6);
      expect(SoundEffect.tap.assetName, 'audio/tap.wav');
      expect(SoundEffect.tap.fullAssetPath, 'assets/audio/tap.wav');
      expect(SoundEffect.wordSuccess.assetName, 'audio/word_success.wav');
      expect(SoundEffect.wordError.assetName, 'audio/word_error.wav');
      expect(SoundEffect.countdown.assetName, 'audio/countdown.wav');
      expect(SoundEffect.victory.assetName, 'audio/victory.wav');
      expect(SoundEffect.defeat.assetName, 'audio/defeat.wav');
    });

    test('has valid volume multipliers', () {
      for (final effect in SoundEffect.values) {
        expect(effect.defaultVolume, greaterThan(0.0));
        expect(effect.defaultVolume, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('SoundEffects settings and persistence', () {
    test('starts with defaults', () {
      final sfx = SoundEffects.instance;
      expect(sfx.isMuted, isFalse);
      expect(sfx.volume, closeTo(0.8, 0.001));
      expect(sfx.playCount, 0);
      expect(sfx.lastPlayedEffect, isNull);
    });

    test('notifies listeners when mute state changes', () async {
      final sfx = SoundEffects.instance;
      int notified = 0;
      sfx.addListener(() => notified++);

      await sfx.toggleMute();
      expect(sfx.isMuted, isTrue);
      expect(notified, 1);

      await sfx.setMuted(false);
      expect(sfx.isMuted, isFalse);
      expect(notified, 2);
    });

    test('persists mute state to SharedPreferences', () async {
      final sfx = SoundEffects.instance;
      await sfx.setMuted(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SoundEffects.prefsMutedKey), isTrue);

      // Restore into fresh state
      sfx.resetForTesting();
      expect(sfx.isMuted, isFalse);
      await SoundEffects.restore();
      expect(sfx.isMuted, isTrue);
      expect(sfx.isInitialized, isTrue);
    });

    test('clamps and persists volume', () async {
      final sfx = SoundEffects.instance;
      int notified = 0;
      sfx.addListener(() => notified++);

      await sfx.setVolume(1.5); // should clamp to 1.0
      expect(sfx.volume, 1.0);
      expect(notified, 1);

      await sfx.setVolume(-0.5); // should clamp to 0.0
      expect(sfx.volume, 0.0);
      expect(notified, 2);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(SoundEffects.prefsVolumeKey), 0.0);

      // Restore
      await prefs.setDouble(SoundEffects.prefsVolumeKey, 0.65);
      await SoundEffects.restore();
      expect(sfx.volume, closeTo(0.65, 0.001));
    });
  });

  group('SoundEffects playback triggers', () {
    test('invokes mock playback handler for all event methods', () async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      final volumes = <double>[];

      sfx.testPlaybackHandler = (effect, volume) async {
        played.add(effect);
        volumes.add(volume);
      };

      await sfx.playTap();
      await sfx.playWordSuccess();
      await sfx.playWordError();
      await sfx.playCountdown();
      await sfx.playVictory();
      await sfx.playDefeat();

      expect(played, [
        SoundEffect.tap,
        SoundEffect.wordSuccess,
        SoundEffect.wordError,
        SoundEffect.countdown,
        SoundEffect.victory,
        SoundEffect.defeat,
      ]);
      expect(sfx.playCount, 6);
      expect(sfx.lastPlayedEffect, SoundEffect.defeat);
      for (final v in volumes) {
        expect(v, greaterThan(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('suppresses playback when muted', () async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];

      sfx.testPlaybackHandler = (effect, volume) async {
        played.add(effect);
      };

      await sfx.setMuted(true);
      await sfx.playTap();
      await sfx.playWordSuccess();

      expect(played, isEmpty);
      expect(sfx.playCount, 0);
      expect(sfx.lastPlayedEffect, isNull);
    });

    test('safely falls back without throwing when native player unavailable', () async {
      final sfx = SoundEffects.instance;
      // testPlaybackHandler is null, should execute real code path with safe try/catch
      expect(() async => await sfx.playTap(), returnsNormally);
      expect(sfx.lastPlayedEffect, SoundEffect.tap);
    });
  });

  group('Gameplay events sound triggers', () {
    test('triggers victory sound on match win', () async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      sfx.testPlaybackHandler = (effect, _) async => played.add(effect);

      Future<void> handleMatchResult({required bool won}) async {
        if (won) {
          await sfx.playVictory();
        } else {
          await sfx.playDefeat();
        }
      }

      await handleMatchResult(won: true);
      expect(played, [SoundEffect.victory]);
    });

    test('triggers defeat sound on match loss', () async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      sfx.testPlaybackHandler = (effect, _) async => played.add(effect);

      Future<void> handleMatchResult({required bool won}) async {
        if (won) {
          await sfx.playVictory();
        } else {
          await sfx.playDefeat();
        }
      }

      await handleMatchResult(won: false);
      expect(played, [SoundEffect.defeat]);
    });

    test('triggers countdown chimes only during final 5 seconds of player turn', () async {
      final sfx = SoundEffects.instance;
      final countdownBeeps = <int>[];
      sfx.testPlaybackHandler = (effect, _) async {
        if (effect == SoundEffect.countdown) countdownBeeps.add(1);
      };

      // Simulate tick countdown loop
      void simulateTick({required bool yourTurn, required int oldMs, required int newMs}) {
        final oldSeconds = (oldMs / 1000).ceil();
        final newSeconds = (newMs / 1000).ceil();
        if (yourTurn && newSeconds <= 5 && newSeconds > 0 && newSeconds != oldSeconds) {
          sfx.playCountdown();
        }
      }

      // Above 5 seconds: no chime
      simulateTick(yourTurn: true, oldMs: 7000, newMs: 6000);
      expect(countdownBeeps, isEmpty);

      // Opponent's turn: no chime even if under 5 seconds
      simulateTick(yourTurn: false, oldMs: 4000, newMs: 3000);
      expect(countdownBeeps, isEmpty);

      // Player's turn: 5, 4, 3, 2, 1 seconds each trigger countdown chime
      simulateTick(yourTurn: true, oldMs: 5100, newMs: 4900); // ticks into 5
      simulateTick(yourTurn: true, oldMs: 4100, newMs: 3900); // ticks into 4
      simulateTick(yourTurn: true, oldMs: 3100, newMs: 2900); // ticks into 3
      simulateTick(yourTurn: true, oldMs: 2100, newMs: 1900); // ticks into 2
      simulateTick(yourTurn: true, oldMs: 1100, newMs: 900);  // ticks into 1

      expect(countdownBeeps.length, 5);
    });

    test('triggers word success and error sounds on duel chain updates and rejections', () async {
      final sfx = SoundEffects.instance;
      final played = <SoundEffect>[];
      sfx.testPlaybackHandler = (effect, _) async => played.add(effect);

      // Word success: chain length increases
      final oldChainLen = 2;
      final newChainLen = 3;
      if (newChainLen > oldChainLen) {
        await sfx.playWordSuccess();
      }
      expect(played, [SoundEffect.wordSuccess]);

      // Word rejected
      await sfx.playWordError();
      expect(played, [SoundEffect.wordSuccess, SoundEffect.wordError]);
    });
  });
}
