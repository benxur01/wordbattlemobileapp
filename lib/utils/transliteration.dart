import 'package:flutter/services.dart';

/// Mapping from Cyrillic characters (Uzbek and Slavic) to Latin equivalents.
const Map<String, String> _kCyrillicToLatinWithApostrophe = {
  // Lowercase
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'yo',
  'ж': 'j',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'x',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': "'",
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'ў': "o'",
  'ғ': "g'",
  'ҳ': 'h',
  'қ': 'q',

  // Uppercase
  'А': 'A',
  'Б': 'B',
  'В': 'V',
  'Г': 'G',
  'Д': 'D',
  'Е': 'E',
  'Ё': 'Yo',
  'Ж': 'J',
  'З': 'Z',
  'И': 'I',
  'Й': 'Y',
  'К': 'K',
  'Л': 'L',
  'М': 'M',
  'Н': 'N',
  'О': 'O',
  'П': 'P',
  'Р': 'R',
  'С': 'S',
  'Т': 'T',
  'У': 'U',
  'Ф': 'F',
  'Х': 'X',
  'Ц': 'Ts',
  'Ч': 'Ch',
  'Ш': 'Sh',
  'Щ': 'Sh',
  'Ъ': "'",
  'Ы': 'I',
  'Ь': '',
  'Э': 'E',
  'Ю': 'Yu',
  'Я': 'Ya',
  'Ў': "O'",
  'Ғ': "G'",
  'Ҳ': 'H',
  'Қ': 'Q',
};

final Map<String, String> _kCyrillicToLatinStrict = Map.unmodifiable(
  Map<String, String>.from(_kCyrillicToLatinWithApostrophe)
    ..addAll({
      'ъ': '',
      'Ъ': '',
      'ў': 'o',
      'Ў': 'O',
      'ғ': 'g',
      'Ғ': 'G',
    }),
);

/// Returns true if [input] contains any Cyrillic unicode characters.
bool containsCyrillic(String input) {
  for (final rune in input.runes) {
    // Unicode block for Cyrillic: U+0400 to U+04FF, and supplementary U+0500 to U+052F
    if ((rune >= 0x0400 && rune <= 0x04FF) || (rune >= 0x0500 && rune <= 0x052F)) {
      return true;
    }
  }
  return false;
}

/// Transliterates any Cyrillic characters in [input] to their Latin counterparts.
///
/// When [allowApostrophe] is false (default for word chain gameplay), characters
/// like 'ў', 'ғ', and 'ъ' are mapped to pure Latin letters without apostrophes.
/// When [toLowerCase] is true (default), the returned string is in lowercase.
String transliterateCyrillicToLatin(
  String input, {
  bool allowApostrophe = false,
  bool toLowerCase = true,
}) {
  if (input.isEmpty) return input;
  final map = allowApostrophe ? _kCyrillicToLatinWithApostrophe : _kCyrillicToLatinStrict;

  final buffer = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final char = input[i];
    final replacement = map[char];
    if (replacement != null) {
      buffer.write(replacement);
    } else {
      buffer.write(char);
    }
  }

  final result = buffer.toString();
  return toLowerCase ? result.toLowerCase() : result;
}

/// A [TextInputFormatter] that automatically converts Cyrillic input to Latin
/// in real time while maintaining correct text cursor positioning.
class CyrillicToLatinFormatter extends TextInputFormatter {
  const CyrillicToLatinFormatter({
    this.allowApostrophe = false,
    this.toLowerCase = true,
    this.onCyrillicDetected,
  });

  final bool allowApostrophe;
  final bool toLowerCase;

  /// Optional callback invoked when Cyrillic characters are detected and transliterated.
  final void Function(String cyrillicChunk)? onCyrillicDetected;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    if (!containsCyrillic(rawText)) {
      if (toLowerCase && rawText != rawText.toLowerCase()) {
        return newValue.copyWith(
          text: rawText.toLowerCase(),
          selection: newValue.selection,
        );
      }
      return newValue;
    }

    final map = allowApostrophe ? _kCyrillicToLatinWithApostrophe : _kCyrillicToLatinStrict;
    final buffer = StringBuffer();
    final detectedCyrillic = StringBuffer();
    int newSelectionEnd = 0;
    int newSelectionStart = 0;

    final targetEnd = newValue.selection.end;
    final targetStart = newValue.selection.start;

    for (int i = 0; i < rawText.length; i++) {
      final char = rawText[i];
      final replacement = map[char];

      if (replacement != null) {
        detectedCyrillic.write(char);
        final converted = toLowerCase ? replacement.toLowerCase() : replacement;
        buffer.write(converted);
        if (i < targetStart) {
          newSelectionStart += converted.length;
        }
        if (i < targetEnd) {
          newSelectionEnd += converted.length;
        }
      } else {
        final converted = toLowerCase ? char.toLowerCase() : char;
        buffer.write(converted);
        if (i < targetStart) {
          newSelectionStart += converted.length;
        }
        if (i < targetEnd) {
          newSelectionEnd += converted.length;
        }
      }
    }

    if (detectedCyrillic.isNotEmpty && onCyrillicDetected != null) {
      onCyrillicDetected!(detectedCyrillic.toString());
    }

    final transformedText = buffer.toString();
    final clampedStart = newSelectionStart.clamp(0, transformedText.length);
    final clampedEnd = newSelectionEnd.clamp(0, transformedText.length);

    return TextEditingValue(
      text: transformedText,
      selection: TextSelection(
        baseOffset: clampedStart,
        extentOffset: clampedEnd,
      ),
    );
  }
}
