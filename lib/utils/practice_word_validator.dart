/// Live validation phases for practice word testing.
enum PracticeInputPhase {
  idle,
  incomplete,
  valid,
  invalid,
  checking,
  accepted,
}

/// Result of validating a candidate practice word against chain rules.
class PracticeValidationResult {
  const PracticeValidationResult({
    required this.phase,
    required this.normalizedWord,
    this.message,
  });

  final PracticeInputPhase phase;
  final String normalizedWord;
  final String? message;

  bool get isValid => phase == PracticeInputPhase.valid;
  bool get isInvalid => phase == PracticeInputPhase.invalid;
}

/// Pure rules for real-time and submit-time validation in Solo Practice.
class PracticeWordValidator {
  PracticeWordValidator._();

  static const int defaultMinLength = 3;
  static final RegExp _lettersOnly = RegExp(r'^[a-z]+$');

  /// Evaluates keystroke input before the player submits, keeping short valid
  /// prefixes in [PracticeInputPhase.incomplete] instead of flashing red while
  /// the first two letters are still being typed.
  static PracticeValidationResult validateLive(
    String rawText, {
    required String? needLetter,
    Set<String> triedWords = const {},
    int minLength = defaultMinLength,
  }) {
    final word = rawText.trim().toLowerCase();
    if (word.isEmpty) {
      return const PracticeValidationResult(
        phase: PracticeInputPhase.idle,
        normalizedWord: '',
      );
    }

    if (!_lettersOnly.hasMatch(word)) {
      return PracticeValidationResult(
        phase: PracticeInputPhase.invalid,
        normalizedWord: word,
        message: 'Faqat ingliz harflari',
      );
    }

    final target = needLetter?.trim().toLowerCase();
    if (target != null && target.isNotEmpty && word[0] != target[0]) {
      return PracticeValidationResult(
        phase: PracticeInputPhase.invalid,
        normalizedWord: word,
        message: '«${target[0].toUpperCase()}» harfi bilan boshlanishi kerak',
      );
    }

    if (triedWords.contains(word)) {
      return PracticeValidationResult(
        phase: PracticeInputPhase.invalid,
        normalizedWord: word,
        message: "Bu so'z allaqachon sinab ko'rildi",
      );
    }

    if (word.length < minLength) {
      return PracticeValidationResult(
        phase: PracticeInputPhase.incomplete,
        normalizedWord: word,
        message: 'Kamida $minLength ta harf (${word.length}/$minLength)',
      );
    }

    return PracticeValidationResult(
      phase: PracticeInputPhase.valid,
      normalizedWord: word,
      message: "Qoidaga mos — tekshirish uchun yuboring",
    );
  }

  /// Strict validation run when the player presses submit. Empty and short
  /// inputs promote to [PracticeInputPhase.invalid] so the field shakes.
  static PracticeValidationResult validateSubmit(
    String rawText, {
    required String? needLetter,
    Set<String> triedWords = const {},
    int minLength = defaultMinLength,
  }) {
    final live = validateLive(
      rawText,
      needLetter: needLetter,
      triedWords: triedWords,
      minLength: minLength,
    );
    if (live.phase == PracticeInputPhase.idle) {
      return const PracticeValidationResult(
        phase: PracticeInputPhase.invalid,
        normalizedWord: '',
        message: "Avval so'z yozing",
      );
    }
    if (live.phase == PracticeInputPhase.incomplete) {
      return PracticeValidationResult(
        phase: PracticeInputPhase.invalid,
        normalizedWord: live.normalizedWord,
        message: 'Kamida $minLength ta harf yozing',
      );
    }
    return live;
  }
}
