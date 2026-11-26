import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/utils/hint_filter.dart';

void main() {
  group('HintLengthFilter', () {
    test('matches exact length windows for all, short, medium, and long', () {
      expect(HintLengthFilter.all.matches('cat'), isTrue);
      expect(HintLengthFilter.all.matches('encyclopedia'), isTrue);

      expect(HintLengthFilter.short.matches('red'), isTrue);
      expect(HintLengthFilter.short.matches('rain'), isTrue);
      expect(HintLengthFilter.short.matches('river'), isFalse);
      expect(HintLengthFilter.short.matches('no'), isFalse);

      expect(HintLengthFilter.medium.matches('rain'), isFalse);
      expect(HintLengthFilter.medium.matches('river'), isTrue);
      expect(HintLengthFilter.medium.matches('rocket'), isTrue);
      expect(HintLengthFilter.medium.matches('rainbow'), isFalse);

      expect(HintLengthFilter.long.matches('rocket'), isFalse);
      expect(HintLengthFilter.long.matches('rainbow'), isTrue);
      expect(HintLengthFilter.long.matches('revolution'), isTrue);
    });
  });

  group('HintFilterHelper', () {
    const sample = ['red', 'rain', 'river', 'rocket', 'rainbow', 'apple', 'anchor', 'amazing'];

    test('normalizes ASCII starting letters and rejects invalid characters', () {
      expect(HintFilterHelper.normalizeLetter('  R  '), 'r');
      expect(HintFilterHelper.normalizeLetter('a'), 'a');
      expect(HintFilterHelper.normalizeLetter(''), isNull);
      expect(HintFilterHelper.normalizeLetter('123'), isNull);
      expect(HintFilterHelper.normalizeLetter('р'), isNull);
      expect(HintFilterHelper.normalizeLetter(null), isNull);
    });

    test('filters hints by both starting letter and length bucket', () {
      expect(
        HintFilterHelper.apply(sample, startingLetter: 'R', lengthFilter: HintLengthFilter.short),
        ['red', 'rain'],
      );
      expect(
        HintFilterHelper.apply(sample, startingLetter: 'r', lengthFilter: HintLengthFilter.medium),
        ['river', 'rocket'],
      );
      expect(
        HintFilterHelper.apply(sample, startingLetter: 'r', lengthFilter: HintLengthFilter.long),
        ['rainbow'],
      );
      expect(
        HintFilterHelper.apply(sample, startingLetter: 'a', lengthFilter: HintLengthFilter.long),
        ['amazing'],
      );
      expect(
        HintFilterHelper.apply(sample, startingLetter: null, lengthFilter: HintLengthFilter.short),
        ['red', 'rain'],
      );
    });
  });
}
