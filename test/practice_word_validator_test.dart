import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/utils/practice_word_validator.dart';

void main() {
  group('PracticeWordValidator edge cases', () {
    test('trims whitespace and folds uppercase input before validation', () {
      final result = PracticeWordValidator.validateLive(
        '   RAINBOW  ',
        needLetter: 'R',
      );
      expect(result.phase, PracticeInputPhase.valid);
      expect(result.normalizedWord, 'rainbow');
      expect(result.isValid, isTrue);
      expect(result.isInvalid, isFalse);
    });

    test('treats whitespace-only input as idle live and invalid on submit', () {
      final live = PracticeWordValidator.validateLive('   ', needLetter: 'r');
      expect(live.phase, PracticeInputPhase.idle);
      expect(live.normalizedWord, '');
      expect(live.message, isNull);

      final submit = PracticeWordValidator.validateSubmit('   ', needLetter: 'r');
      expect(submit.phase, PracticeInputPhase.invalid);
      expect(submit.isInvalid, isTrue);
      expect(submit.message, "Avval so'z yozing");
    });

    test('rejects digits, spaces inside words, hyphens, and punctuation', () {
      for (final bad in ['r1ver', 'rock star', 're-act', 'rain!']) {
        final result = PracticeWordValidator.validateLive(bad, needLetter: 'r');
        expect(result.phase, PracticeInputPhase.invalid, reason: 'Failed for $bad');
        expect(result.message, 'Faqat ingliz harflari');
      }
    });

    test('supports custom minLength constraints on live and submit checks', () {
      final shortLive = PracticeWordValidator.validateLive('rain', needLetter: 'r', minLength: 5);
      expect(shortLive.phase, PracticeInputPhase.incomplete);
      expect(shortLive.message, 'Kamida 5 ta harf (4/5)');

      final shortSubmit = PracticeWordValidator.validateSubmit('rain', needLetter: 'r', minLength: 5);
      expect(shortSubmit.phase, PracticeInputPhase.invalid);
      expect(shortSubmit.message, 'Kamida 5 ta harf yozing');

      final longEnough = PracticeWordValidator.validateSubmit('river', needLetter: 'r', minLength: 5);
      expect(longEnough.phase, PracticeInputPhase.valid);
    });

    test('handles null or empty needLetter gracefully without wrong-letter error', () {
      final result = PracticeWordValidator.validateLive('apple', needLetter: null);
      expect(result.phase, PracticeInputPhase.valid);

      final blankTarget = PracticeWordValidator.validateLive('apple', needLetter: '   ');
      expect(blankTarget.phase, PracticeInputPhase.valid);
    });
  });
}
