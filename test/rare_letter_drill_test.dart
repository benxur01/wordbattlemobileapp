import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_battle/utils/rare_letter_drill.dart';

void main() {
  group('RareLetterProgress', () {
    test('records unique valid words starting with target letter and unlocks mastery at goal', () {
      var progress = const RareLetterProgress(letter: 'x', solvedWords: [], targetCount: 3);
      expect(progress.ratio, 0.0);
      expect(progress.percentage, 0);
      expect(progress.isMastered, isFalse);

      // Ignores wrong starting letter or duplicates
      final wrong = progress.record('quartz');
      expect(wrong.added, isFalse);
      expect(wrong.next.solvedCount, 0);

      final r1 = progress.record(' XRay ');
      expect(r1.added, isTrue);
      expect(r1.justMastered, isFalse);
      progress = r1.next;
      expect(progress.solvedWords, ['xray']);

      final dup = progress.record('xray');
      expect(dup.added, isFalse);

      progress = progress.record('xenon').next;
      expect(progress.isMastered, isFalse);

      final r3 = progress.record('xylem');
      expect(r3.added, isTrue);
      expect(r3.justMastered, isTrue);
      progress = r3.next;
      expect(progress.isMastered, isTrue);
      expect(progress.ratio, 1.0);
      expect(progress.percentage, 100);
      expect(progress.solvedWords, ['xylem', 'xenon', 'xray']);
    });

    test('persists and restores solved X/Q words cleanly and tolerates malformed storage', () async {
      SharedPreferences.setMockInitialValues({});
      final initial = RareLetterDrillHelper.emptyProgressMap();
      final updated = {
        'x': initial['x']!.record('xenon').next.record('xylem').next,
        'q': initial['q']!.record('quartz').next,
      };

      await RareLetterDrillHelper.saveProgress(updated);
      final loaded = await RareLetterDrillHelper.loadProgress();

      expect(loaded['x']!.solvedWords, ['xylem', 'xenon']);
      expect(loaded['q']!.solvedWords, ['quartz']);

      // Corrupted JSON falls back cleanly without throwing
      final corrupt = RareLetterDrillHelper.decodeProgressMap('{broken json');
      expect(corrupt['x']!.solvedWords, isEmpty);
      expect(corrupt['q']!.solvedWords, isEmpty);
    });
  });
}
