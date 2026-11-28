import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Tracks player mastery progress and persisted solved words for rare-letter
/// drills (`x` and `q`).
class RareLetterProgress {
  const RareLetterProgress({
    required this.letter,
    required this.solvedWords,
    this.targetCount = RareLetterDrillHelper.defaultTargetCount,
  });

  final String letter;
  final List<String> solvedWords;
  final int targetCount;

  int get solvedCount => solvedWords.length;

  double get ratio => targetCount <= 0 ? 1.0 : (solvedWords.length / targetCount).clamp(0.0, 1.0);

  int get percentage => (ratio * 100).round();

  bool get isMastered => targetCount > 0 && solvedWords.length >= targetCount;

  /// Records [rawWord] if it cleanly starts with [letter] and has not been
  /// counted yet, returning updated progress plus whether this word unlocked mastery.
  ({RareLetterProgress next, bool added, bool justMastered}) record(String rawWord) {
    final normalized = RareLetterDrillHelper.normalizeWord(rawWord);
    final keyLetter = RareLetterDrillHelper.normalizeLetter(letter);
    if (keyLetter == null || normalized == null || !normalized.startsWith(keyLetter)) {
      return (next: this, added: false, justMastered: false);
    }
    if (solvedWords.contains(normalized)) {
      return (next: this, added: false, justMastered: false);
    }
    final updated = RareLetterProgress(
      letter: keyLetter,
      solvedWords: List<String>.unmodifiable([normalized, ...solvedWords]),
      targetCount: targetCount,
    );
    return (
      next: updated,
      added: true,
      justMastered: !isMastered && updated.isMastered,
    );
  }

  RareLetterProgress cleared() => RareLetterProgress(
        letter: letter,
        solvedWords: const [],
        targetCount: targetCount,
      );
}

class RareLetterDrillHelper {
  static const int defaultTargetCount = 5;
  static const List<String> supportedLetters = ['x', 'q'];
  static const String prefsKey = 'wb_rare_letter_drills_v1';

  /// Normalizes a candidate rare-letter filter (`'X'` -> `'x'`), returning null
  /// when unsupported.
  static String? normalizeLetter(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().toLowerCase();
    if (clean.length != 1) return null;
    return supportedLetters.contains(clean) ? clean : null;
  }

  /// Normalizes a solved candidate word (`'  XRay '` -> `'xray'`), ensuring plain
  /// ASCII lowercase letters only.
  static String? normalizeWord(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().toLowerCase();
    if (clean.length < 2) return null;
    if (!RegExp(r'^[a-z]+$').hasMatch(clean)) return null;
    return clean;
  }

  /// Offline-resilient fallback catalog used before the API responds or in tests.
  static List<RareLetterDrillDto> fallbackDrills() => const [
        RareLetterDrillDto(
          letter: 'x',
          badge: 'NOYOB · X',
          title: 'X harfi hujumi',
          subtitle: "Raqib X bilan tugagan so'z tashlaganda tez javob bering",
          tip: 'X bilan boshlanadigan so\'zlar kam: xenon, xylem, xerox, xray, xylophone ni yodda tuting.',
          promptWord: 'apex',
          promptIpa: '/ˈeɪpeks/',
          promptMeaning: "cho'qqi — eng yuqori nuqta",
          targetCount: defaultTargetCount,
          hints: ['xray', 'xenon', 'xylem', 'xerox', 'xanthic', 'xylophone'],
        ),
        RareLetterDrillDto(
          letter: 'q',
          badge: 'NOYOB · Q',
          title: 'Q harfi strategiyasi',
          subtitle: "«Qu-» birikmali tezkor so'z zanjirini mustahkamlang",
          tip: 'Q dan keyin deyarli doim U keladi: quest, quartz, quench, quiver, quorum — kuchli javoblar.',
          promptWord: 'quartz',
          promptIpa: '/kwɔːts/',
          promptMeaning: 'kvars — shaffof va qattiq mineral tosh',
          targetCount: defaultTargetCount,
          hints: ['queen', 'quest', 'quartz', 'quench', 'quiver', 'quorum'],
        ),
      ];

  /// Builds empty progress entries keyed by `'x'` and `'q'`.
  static Map<String, RareLetterProgress> emptyProgressMap({
    int xTarget = defaultTargetCount,
    int qTarget = defaultTargetCount,
  }) =>
      {
        'x': RareLetterProgress(letter: 'x', solvedWords: const [], targetCount: xTarget),
        'q': RareLetterProgress(letter: 'q', solvedWords: const [], targetCount: qTarget),
      };

  /// Serializes solved words map into JSON string for [SharedPreferences].
  static String encodeProgressMap(Map<String, RareLetterProgress> map) {
    final raw = <String, List<String>>{};
    for (final letter in supportedLetters) {
      raw[letter] = map[letter]?.solvedWords ?? const [];
    }
    return jsonEncode(raw);
  }

  /// Parses stored JSON safely, ignoring corrupted entries cleanly.
  static Map<String, RareLetterProgress> decodeProgressMap(
    String? rawJson, {
    int xTarget = defaultTargetCount,
    int qTarget = defaultTargetCount,
  }) {
    final base = emptyProgressMap(xTarget: xTarget, qTarget: qTarget);
    if (rawJson == null || rawJson.trim().isEmpty) return base;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return base;
      for (final letter in supportedLetters) {
        final rawList = decoded[letter];
        if (rawList is! List) continue;
        var entry = base[letter]!;
        for (final item in rawList.reversed) {
          if (item is String) {
            entry = entry.record(item).next;
          }
        }
        base[letter] = entry;
      }
    } catch (_) {
      // Ignore malformed stored payloads and keep clean empty progress.
    }
    return base;
  }

  static Future<Map<String, RareLetterProgress>> loadProgress({
    SharedPreferences? prefs,
    int xTarget = defaultTargetCount,
    int qTarget = defaultTargetCount,
  }) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      return decodeProgressMap(
        store.getString(prefsKey),
        xTarget: xTarget,
        qTarget: qTarget,
      );
    } catch (_) {
      return emptyProgressMap(xTarget: xTarget, qTarget: qTarget);
    }
  }

  static Future<void> saveProgress(
    Map<String, RareLetterProgress> map, {
    SharedPreferences? prefs,
  }) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      await store.setString(prefsKey, encodeProgressMap(map));
    } catch (_) {
      // Persistence failure should never interrupt active practice.
    }
  }
}
