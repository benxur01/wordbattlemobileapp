import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Visual themes available for the Word of the Day shareable image card.
enum WordShareStyle {
  indigoGlass(
    label: 'Indigo',
    backgroundStart: Color(0xFF15182B),
    backgroundEnd: Color(0xFF0E1019),
    accent: Color(0xFF7C8AFF),
    secondaryAccent: Color(0xFF4F5EE8),
  ),
  amberGlow(
    label: 'Oltin',
    backgroundStart: Color(0xFF211A12),
    backgroundEnd: Color(0xFF12100E),
    accent: Color(0xFFF7B733),
    secondaryAccent: Color(0xFFE0921A),
  ),
  emeraldNight(
    label: 'Zumrad',
    backgroundStart: Color(0xFF10221C),
    backgroundEnd: Color(0xFF0D1412),
    accent: Color(0xFF35D07F),
    secondaryAccent: Color(0xFF1F6B5A),
  );

  const WordShareStyle({
    required this.label,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.accent,
    required this.secondaryAccent,
  });

  final String label;
  final Color backgroundStart;
  final Color backgroundEnd;
  final Color accent;
  final Color secondaryAccent;

  Color get chipTextColor => WBColors.text;
}

/// Formats and dispatches shareable "Word of the Day" social captions and images.
class WordShareService {
  WordShareService._();

  /// Builds a concise bilingual share caption for Telegram and Instagram.
  static String buildCaption(
    PracticeWordDto word, {
    int practicedCount = 0,
  }) {
    final buffer = StringBuffer()..write('✨ Word Battle — Kun so\'zi: ${word.word.toUpperCase()}');
    if (word.ipa.trim().isNotEmpty) {
      buffer.write(' ${word.ipa.trim()}');
    }
    buffer
      ..writeln()
      ..writeln("📖 Ma'nosi: ${word.meaning}");
    if (practicedCount > 0) {
      buffer.writeln("🔥 Bugungi mashqda $practicedCount ta so'z topdim!");
    }
    final last = word.word.trim().isEmpty
        ? '?'
        : word.word.trim().substring(word.word.trim().length - 1).toUpperCase();
    buffer.write("Siz «$last» harfi bilan nechta so'z topa olasiz?");
    return buffer.toString();
  }
}
