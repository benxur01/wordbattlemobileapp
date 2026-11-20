import '../widgets/word_combo_badge.dart';
import 'transliteration.dart';

/// Information about an awarded combo result for a submitted word.
class WordComboResult {
  const WordComboResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.bonusPoints,
    required this.multiplier,
    required this.rareLetters,
    required this.wordLength,
  });

  /// The achieved combo category.
  final WordComboType type;

  /// Prominent celebratory badge title.
  final String title;

  /// Contextual subtitle explaining why the combo was awarded.
  final String subtitle;

  /// Bonus points added to player's rating or score.
  final int bonusPoints;

  /// Score multiplier factor.
  final double multiplier;

  /// Rare or high-value letters present in the word.
  final List<String> rareLetters;

  /// Total letter count of the word.
  final int wordLength;
}

/// Evaluator that scans played words for length tiers, rare Uzbek alphabet
/// letters, and rapid response times to award celebratory combos.
class WordComboEvaluator {
  WordComboEvaluator._();

  /// Set of rare, high-difficulty letters in Uzbek word games.
  static const Set<String> rareLetters = {'Q', 'X', 'F', 'H', 'J', 'V'};

  /// Extracts all rare letters found in the normalized word.
  static List<String> findRareLetters(String normalizedWord) {
    final found = <String>[];
    for (int i = 0; i < normalizedWord.length; i++) {
      final char = normalizedWord[i];
      if (rareLetters.contains(char)) {
        found.add(char);
      }
    }
    return found;
  }

  /// Evaluates [rawWord] with optional [spentMs] (response time in milliseconds).
  ///
  /// Returns a [WordComboResult] if the word qualifies for a combo, or `null`
  /// if it was an ordinary word below combo thresholds.
  static WordComboResult? evaluateWord(String rawWord, {int spentMs = 0}) {
    final word = transliterateCyrillicToLatin(rawWord, allowApostrophe: true, toLowerCase: false)
        .trim()
        .toUpperCase();

    if (word.length < 4) return null;

    final foundRare = findRareLetters(word);
    final isLightningFast = spentMs > 0 && spentMs <= 2200;

    // Mega Combo: 9+ letters OR (7+ letters with 2+ rare letters)
    if (word.length >= 9 || (word.length >= 7 && foundRare.length >= 2)) {
      final rareDesc = foundRare.isNotEmpty ? ' · ${foundRare.toSet().join(', ')}' : '';
      return WordComboResult(
        type: WordComboType.megaCombo,
        title: "AQLBOVAR QILMAS!",
        subtitle: "${word.length} ta harf$rareDesc",
        bonusPoints: 15 + (word.length >= 9 ? 5 : 0) + (foundRare.length * 2),
        multiplier: 2.0,
        rareLetters: foundRare,
        wordLength: word.length,
      );
    }

    // Long Word: 7-8 letters
    if (word.length >= 7) {
      return WordComboResult(
        type: WordComboType.longWord,
        title: "UZUN SO'Z!",
        subtitle: "${word.length} ta harf",
        bonusPoints: 8 + (word.length - 6) * 2,
        multiplier: 1.5,
        rareLetters: foundRare,
        wordLength: word.length,
      );
    }

    // Rare Letters: 2+ rare letters, or 1 rare letter in a 5+ letter word
    if (foundRare.length >= 2) {
      final letters = foundRare.toSet().join(', ');
      return WordComboResult(
        type: WordComboType.rareLetter,
        title: "NOYOB HARFLAR!",
        subtitle: "$letters harflari qo'llandi",
        bonusPoints: 8 + (foundRare.length * 2),
        multiplier: 1.4,
        rareLetters: foundRare,
        wordLength: word.length,
      );
    } else if (foundRare.length == 1 && word.length >= 5) {
      return WordComboResult(
        type: WordComboType.rareLetter,
        title: "NOYOB HARF!",
        subtitle: "«${foundRare.first}» harfi qo'llandi",
        bonusPoints: 5,
        multiplier: 1.25,
        rareLetters: foundRare,
        wordLength: word.length,
      );
    }

    // Speed Demon: rapid reply within 2.2 seconds for words with 4+ letters
    if (isLightningFast && word.length >= 4) {
      final sec = (spentMs / 1000).toStringAsFixed(1);
      return WordComboResult(
        type: WordComboType.speedDemon,
        title: "CHAQMOQ TEZKOR!",
        subtitle: "$sec soniyada javob",
        bonusPoints: 6,
        multiplier: 1.3,
        rareLetters: foundRare,
        wordLength: word.length,
      );
    }

    return null;
  }
}
