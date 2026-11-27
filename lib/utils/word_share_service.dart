import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

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

  /// Optional test hook intercepting outgoing PNG share payloads without
  /// invoking platform share sheets during automated tests.
  @visibleForTesting
  static Future<void> Function(Uint8List pngBytes, String caption, String word)? testShareHandler;

  /// Captures a mounted [RepaintBoundary] identified by [boundaryKey] into
  /// high-resolution PNG bytes suitable for Instagram Stories and Telegram.
  static Future<Uint8List?> captureBoundaryToPng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Renders [boundaryKey] to PNG bytes and shares it via the OS share sheet
  /// (falling back to caption-only sharing if image capture returns null).
  static Future<bool> shareWordCard({
    required GlobalKey boundaryKey,
    required PracticeWordDto word,
    int practicedCount = 0,
    double pixelRatio = 3.0,
  }) async {
    final caption = buildCaption(word, practicedCount: practicedCount);
    final pngBytes = await captureBoundaryToPng(boundaryKey, pixelRatio: pixelRatio);

    if (pngBytes == null) {
      await SharePlus.instance.share(ShareParams(text: caption));
      return false;
    }

    if (testShareHandler != null) {
      await testShareHandler!(pngBytes, caption, word.word);
      return true;
    }

    final safeSlug = word.word.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final file = XFile.fromData(
      pngBytes,
      mimeType: 'image/png',
      name: 'word_battle_${safeSlug.isEmpty ? 'card' : safeSlug}.png',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        text: caption,
      ),
    );
    return true;
  }

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
