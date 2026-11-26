/// Predefined word length buckets for practice mode hint filtering.
enum HintLengthFilter {
  all(label: 'Barchasi', rangeBadge: null, minLength: null, maxLength: null),
  short(label: 'Qisqa', rangeBadge: '3–4', minLength: 3, maxLength: 4),
  medium(label: "O'rta", rangeBadge: '5–6', minLength: 5, maxLength: 6),
  long(label: 'Uzun', rangeBadge: '7+', minLength: 7, maxLength: null);

  const HintLengthFilter({
    required this.label,
    required this.rangeBadge,
    required this.minLength,
    required this.maxLength,
  });

  final String label;
  final String? rangeBadge;
  final int? minLength;
  final int? maxLength;

  bool matches(String word) {
    final len = word.trim().length;
    if (minLength != null && len < minLength!) return false;
    if (maxLength != null && len > maxLength!) return false;
    return true;
  }

  String get semanticDescription =>
      rangeBadge == null ? label : '$label, $rangeBadge ta harf';
}

/// Client-side hint filter helper used alongside server hint queries so
/// offline previews, fallback filters, and local lists stay responsive.
class HintFilterHelper {
  HintFilterHelper._();

  static const List<String> alphabet = [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ];

  /// Normalizes a candidate starting letter into a single lowercase ASCII
  /// character `a..z`, or returns null when invalid.
  static String? normalizeLetter(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final code = trimmed.codeUnitAt(0);
    if (code < 0x61 || code > 0x7A) return null;
    return trimmed[0];
  }

  /// Filters [hints] by optional [startingLetter] and [lengthFilter].
  static List<String> apply(
    List<String> hints, {
    String? startingLetter,
    HintLengthFilter lengthFilter = HintLengthFilter.all,
  }) {
    final target = normalizeLetter(startingLetter);
    return hints.where((raw) {
      final word = raw.trim().toLowerCase();
      if (word.isEmpty) return false;
      if (target != null && !word.startsWith(target)) return false;
      return lengthFilter.matches(word);
    }).toList();
  }
}
