import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/utils/transliteration.dart';

void main() {
  group('containsCyrillic tests', () {
    test('returns true when string has Cyrillic characters', () {
      expect(containsCyrillic('салом'), isTrue);
      expect(containsCyrillic('китоб'), isTrue);
      expect(containsCyrillic('ўзбекистон'), isTrue);
      expect(containsCyrillic('қўл'), isTrue);
      expect(containsCyrillic('ғоз'), isTrue);
      expect(containsCyrillic('aпple'), isTrue); // mixed with Cyrillic 'п'
    });

    test('returns false when string has only Latin or punctuation', () {
      expect(containsCyrillic('hello'), isFalse);
      expect(containsCyrillic('word-battle'), isFalse);
      expect(containsCyrillic('12345'), isFalse);
      expect(containsCyrillic(''), isFalse);
      expect(containsCyrillic('   '), isFalse);
    });
  });

  group('transliterateCyrillicToLatin function tests', () {
    test('transliterates basic everyday words correctly', () {
      expect(transliterateCyrillicToLatin('салом'), 'salom');
      expect(transliterateCyrillicToLatin('китоб'), 'kitob');
      expect(transliterateCyrillicToLatin('олма'), 'olma');
      expect(transliterateCyrillicToLatin('баҳор'), 'bahor');
      expect(transliterateCyrillicToLatin('дарахт'), 'daraxt');
    });

    test('transliterates multi-character combinations', () {
      expect(transliterateCyrillicToLatin('чой'), 'choy');
      expect(transliterateCyrillicToLatin('шаҳар'), 'shahar');
      expect(transliterateCyrillicToLatin('ёшлик'), 'yoshlik');
      expect(transliterateCyrillicToLatin('юлдуз'), 'yulduz');
      expect(transliterateCyrillicToLatin('яшил'), 'yashil');
      expect(transliterateCyrillicToLatin('цирк'), 'tsirk');
    });

    test('handles Uzbek letters with strict and apostrophe modes', () {
      // Strict mode (default for word chain gameplay: pure [a-z])
      expect(transliterateCyrillicToLatin('ўрик'), 'orik');
      expect(transliterateCyrillicToLatin('ғоз'), 'goz');
      expect(transliterateCyrillicToLatin('қўл'), 'qol');
      expect(transliterateCyrillicToLatin('маъно'), 'mano');

      // Apostrophe mode
      expect(transliterateCyrillicToLatin('ўрик', allowApostrophe: true), "o'rik");
      expect(transliterateCyrillicToLatin('ғоз', allowApostrophe: true), "g'oz");
      expect(transliterateCyrillicToLatin('қўл', allowApostrophe: true), "qo'l");
      expect(transliterateCyrillicToLatin('маъно', allowApostrophe: true), "ma'no");
    });

    test('handles mixed Latin/Cyrillic inputs and case normalization', () {
      // User typed "apple" with Cyrillic 'п' (common keyboard slip)
      expect(transliterateCyrillicToLatin('aпple'), 'apple');
      expect(transliterateCyrillicToLatin('САЛОМ'), 'salom');
      expect(transliterateCyrillicToLatin('Hello Дўст'), 'hello dost');
    });
  });

  group('CyrillicToLatinFormatter TextInputFormatter tests', () {
    const formatter = CyrillicToLatinFormatter();

    test('leaves pure Latin text untouched', () {
      const oldVal = TextEditingValue(
        text: 'hel',
        selection: TextSelection.collapsed(offset: 3),
      );
      const newVal = TextEditingValue(
        text: 'hell',
        selection: TextSelection.collapsed(offset: 4),
      );

      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'hell');
      expect(result.selection.end, 4);
    });

    test('transliterates Cyrillic while advancing cursor accurately for multi-char replacements', () {
      // User types 'ш' (transliterates to 'sh', length 2)
      const oldVal = TextEditingValue.empty;
      const newVal = TextEditingValue(
        text: 'ш',
        selection: TextSelection.collapsed(offset: 1),
      );

      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'sh');
      expect(result.selection.end, 2);
    });

    test('positions cursor correctly when inserting in the middle of text', () {
      // User has "ba", types 'ч' in middle -> "bcha"
      const oldVal = TextEditingValue(
        text: 'ba',
        selection: TextSelection.collapsed(offset: 1),
      );
      const newVal = TextEditingValue(
        text: 'bча', // 'ч' inserted at index 1
        selection: TextSelection.collapsed(offset: 2),
      );

      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, 'bcha');
      // 'b' (1) + 'ch' (2) = 3
      expect(result.selection.end, 3);
    });

    test('invokes onCyrillicDetected callback when Cyrillic is entered', () {
      String? detected;
      final notifyingFormatter = CyrillicToLatinFormatter(
        onCyrillicDetected: (chunk) => detected = chunk,
      );

      // Typing Latin: callback not invoked
      notifyingFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'cat',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(detected, isNull);

      // Typing Cyrillic: callback invoked with detected chunk
      notifyingFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'кун',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(detected, 'кун');
    });
  });
}
