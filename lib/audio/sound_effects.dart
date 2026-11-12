import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All sound effects available in Word Battle.
enum SoundEffect {
  tap('audio/tap.wav', defaultVolume: 0.5),
  wordSuccess('audio/word_success.wav', defaultVolume: 0.85),
  wordError('audio/word_error.wav', defaultVolume: 0.75),
  countdown('audio/countdown.wav', defaultVolume: 0.7),
  victory('audio/victory.wav', defaultVolume: 0.9),
  defeat('audio/defeat.wav', defaultVolume: 0.8);

  /// Relative path under the audio cache directory (e.g. assets/audio/tap.wav).
  final String assetName;

  /// Default multiplier relative to master volume.
  final double defaultVolume;

  const SoundEffect(this.assetName, {this.defaultVolume = 1.0});

  /// Full asset path as registered in pubspec.yaml.
  String get fullAssetPath => 'assets/$assetName';
}

/// Central audio manager for game sound effects with mute preference
/// persistence, volume normalization, and low-latency playback.
class SoundEffects extends ChangeNotifier {
  static final SoundEffects instance = SoundEffects._internal();

  factory SoundEffects() => instance;

  SoundEffects._internal();

  /// Key used to persist mute state in [SharedPreferences].
  static const String prefsMutedKey = 'wb_sound_muted';

  /// Key used to persist master volume in [SharedPreferences].
  static const String prefsVolumeKey = 'wb_sound_volume';

  bool _isMuted = false;
  double _volume = 0.8;
  bool _isInitialized = false;

  /// Internal [AudioPlayer] instance.
  AudioPlayer? _player;

  /// Optional mock handler for tests or unsupported environments.
  Future<void> Function(SoundEffect effect, double volume)? testPlaybackHandler;

  /// Last played effect (for state inspection and testing).
  SoundEffect? lastPlayedEffect;

  /// Total count of played effects.
  int playCount = 0;

  /// Whether sound playback is currently muted.
  bool get isMuted => _isMuted;

  /// Master volume between 0.0 and 1.0.
  double get volume => _volume;

  /// Whether preferences have been loaded from storage.
  bool get isInitialized => _isInitialized;

  /// Reads stored mute and volume settings from [SharedPreferences].
  static Future<void> restore({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final muted = p.getBool(prefsMutedKey) ?? false;
      final vol = (p.getDouble(prefsVolumeKey) ?? 0.8).clamp(0.0, 1.0);
      instance._isMuted = muted;
      instance._volume = vol;
      instance._isInitialized = true;
      instance.notifyListeners();
    } catch (e) {
      debugPrint('SoundEffects.restore error: $e');
    }
  }

  /// Sets mute state and writes it to [SharedPreferences].
  Future<void> setMuted(bool muted, {SharedPreferences? prefs}) async {
    if (_isMuted == muted) return;
    _isMuted = muted;
    notifyListeners();
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setBool(prefsMutedKey, muted);
    } catch (e) {
      debugPrint('SoundEffects.setMuted error: $e');
    }
  }

  /// Toggles mute state between enabled and disabled.
  Future<void> toggleMute({SharedPreferences? prefs}) async {
    await setMuted(!_isMuted, prefs: prefs);
  }

  /// Sets master volume (clamped between 0.0 and 1.0) and persists it.
  Future<void> setVolume(double volume, {SharedPreferences? prefs}) async {
    final clamped = volume.clamp(0.0, 1.0);
    if ((_volume - clamped).abs() < 0.001) return;
    _volume = clamped;
    notifyListeners();
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setDouble(prefsVolumeKey, clamped);
    } catch (e) {
      debugPrint('SoundEffects.setVolume error: $e');
    }
  }

  /// Returns the lazily initialized [AudioPlayer].
  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  /// Allows injecting a custom [AudioPlayer] for testing.
  void setPlayerForTesting(AudioPlayer? player) {
    _player = player;
  }

  /// Preloads all audio assets into the audio cache to eliminate first-play latency.
  Future<void> preloadAll() async {
    try {
      for (final effect in SoundEffect.values) {
        await AudioCache.instance.load(effect.assetName);
      }
    } catch (e) {
      debugPrint('SoundEffects.preloadAll failed: $e');
    }
  }

  /// Plays a sound effect with safe volume levels and low-latency mode.
  Future<void> play(SoundEffect effect, {double? volumeFactor}) async {
    if (_isMuted) return;

    final factor = volumeFactor ?? effect.defaultVolume;
    final effectiveVolume = (_volume * factor).clamp(0.0, 1.0);
    if (effectiveVolume <= 0.0) return;

    lastPlayedEffect = effect;
    playCount++;

    if (testPlaybackHandler != null) {
      await testPlaybackHandler!(effect, effectiveVolume);
      return;
    }

    try {
      final player = _audioPlayer;
      await player.stop();
      await player.play(
        AssetSource(effect.assetName),
        volume: effectiveVolume,
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      // Safe fallback on platforms or headless test environments without native audio.
      debugPrint('SoundEffects.play(${effect.name}) error: $e');
    }
  }

  /// Plays standard UI tap click sound.
  Future<void> playTap() => play(SoundEffect.tap);

  /// Plays positive chime when a valid word is accepted.
  Future<void> playWordSuccess() => play(SoundEffect.wordSuccess);

  /// Plays error buzz when an invalid word is rejected.
  Future<void> playWordError() => play(SoundEffect.wordError);

  /// Plays short beep during round countdown ticks.
  Future<void> playCountdown() => play(SoundEffect.countdown);

  /// Plays victorious fanfare upon winning a match.
  Future<void> playVictory() => play(SoundEffect.victory);

  /// Plays defeat sound upon match loss.
  Future<void> playDefeat() => play(SoundEffect.defeat);

  /// Plays a preview chime so players can test their current volume level.
  Future<void> playPreview() => play(SoundEffect.wordSuccess);

  /// Releases audio player resources.
  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    super.dispose();
  }

  /// Resets state for testing purposes.
  @visibleForTesting
  void resetForTesting() {
    _isMuted = false;
    _volume = 0.8;
    _isInitialized = false;
    lastPlayedEffect = null;
    playCount = 0;
    testPlaybackHandler = null;
  }
}
