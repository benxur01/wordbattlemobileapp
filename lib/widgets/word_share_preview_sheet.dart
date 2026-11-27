import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/word_share_service.dart';
import 'primary_button.dart';
import 'spinner_ring.dart';
import 'word_share_card.dart';

/// Frosted glass modal bottom sheet allowing the player to preview the Word
/// of the Day share card, pick a color theme, copy caption text, or export
/// and share a high-resolution PNG card to Instagram Stories and Telegram.
class WordSharePreviewSheet extends StatefulWidget {
  const WordSharePreviewSheet({
    super.key,
    required this.word,
    this.practicedCount = 0,
  });

  final PracticeWordDto word;
  final int practicedCount;

  /// Presents [WordSharePreviewSheet] over the active scaffold.
  static Future<void> show(
    BuildContext context, {
    required PracticeWordDto word,
    int practicedCount = 0,
  }) {
    HapticFeedback.lightImpact();
    SoundEffects.instance.playTap();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .6),
      builder: (context) => WordSharePreviewSheet(
        word: word,
        practicedCount: practicedCount,
      ),
    );
  }

  @override
  State<WordSharePreviewSheet> createState() => _WordSharePreviewSheetState();
}

class _WordSharePreviewSheetState extends State<WordSharePreviewSheet> {
  final GlobalKey _cardBoundaryKey = GlobalKey();
  WordShareStyle _selectedStyle = WordShareStyle.indigoGlass;
  bool _copySuccess = false;
  bool _sharing = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _selectStyle(WordShareStyle style) {
    if (_selectedStyle == style) return;
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    setState(() => _selectedStyle = style);
  }

  Future<void> _copyCaption() async {
    final text = WordShareService.buildCaption(
      widget.word,
      practicedCount: widget.practicedCount,
    );
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    SoundEffects.instance.playTap();
    if (!mounted) return;
    setState(() => _copySuccess = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copySuccess = false);
    });
  }

  Future<void> _shareImage() async {
    if (_sharing) return;
    HapticFeedback.mediumImpact();
    setState(() => _sharing = true);
    try {
      await WordShareService.shareWordCard(
        boundaryKey: _cardBoundaryKey,
        word: widget.word,
        practicedCount: widget.practicedCount,
      );
      SoundEffects.instance.playWordSuccess();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLight = WBTheme.isLight;
    final previewMaxHeight = (media.size.height * 0.40).clamp(200.0, 320.0);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + media.padding.bottom),
          decoration: BoxDecoration(
            color: WBColors.bgPanel.withValues(alpha: isLight ? .96 : .92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isLight ? WBColors.textA(.10) : Colors.white.withValues(alpha: .16),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: WBColors.textA(.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kartani ulashish',
                              style: WBText.grotesk(size: 18, weight: FontWeight.w700),
                            ),
                            Text(
                              'Instagram va Telegram uchun HD rasm',
                              style: WBText.grotesk(size: 12.5, color: WBColors.textA(.55)),
                            ),
                          ],
                        ),
                      ),
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        pressScale: .92,
                        borderRadius: BorderRadius.circular(11),
                        semanticLabel: 'Yopish',
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: WBColors.whiteA(.06),
                            border: Border.all(color: WBColors.whiteA(.1)),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close_rounded, size: 17, color: WBColors.textA(.7)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: previewMaxHeight),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          key: _cardBoundaryKey,
                          child: WordShareCard(
                            word: widget.word,
                            style: _selectedStyle,
                            practicedCount: widget.practicedCount,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final style in WordShareStyle.values) ...[
                        _stylePill(style, isLight: isLight),
                        if (style != WordShareStyle.values.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Pressable(
                        onTap: _copyCaption,
                        pressScale: .95,
                        borderRadius: BorderRadius.circular(16),
                        semanticLabel: 'Matnni nusxalash',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _copySuccess ? WBColors.greenA(.14) : WBColors.whiteA(.06),
                            border: Border.all(
                              color: _copySuccess ? WBColors.green.withValues(alpha: .5) : WBColors.whiteA(.12),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _copySuccess ? Icons.check_rounded : Icons.copy_rounded,
                                size: 16,
                                color: _copySuccess ? WBColors.green : WBColors.textA(.78),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _copySuccess ? 'Nusxalandi' : 'Matn',
                                style: WBText.grotesk(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: _copySuccess ? WBColors.green : WBColors.textA(.82),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Pressable(
                          onTap: _sharing ? null : _shareImage,
                          pressScale: .97,
                          borderRadius: BorderRadius.circular(16),
                          semanticLabel: 'Rasmni ulashish',
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: wbIndigoGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: WBColors.indigo.withValues(alpha: isLight ? .20 : .28),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: _sharing
                                ? SpinnerRing(
                                    size: 20,
                                    trackColor: Colors.white.withValues(alpha: .25),
                                    activeColor: Colors.white,
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.ios_share, size: 17, color: WBColors.indigoInk),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Rasmni ulashish',
                                        style: WBText.grotesk(
                                          size: 15,
                                          weight: FontWeight.w700,
                                          color: WBColors.indigoInk,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stylePill(WordShareStyle style, {required bool isLight}) {
    final active = style == _selectedStyle;
    final activeLabelColor = isLight && style == WordShareStyle.amberGlow
        ? WBColors.amber
        : style.accent;
    return Semantics(
      selected: active,
      button: true,
      label: '${style.label} karta uslubi',
      child: Pressable(
        onTap: () => _selectStyle(style),
        pressScale: .94,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? style.accent.withValues(alpha: isLight ? .14 : .16) : WBColors.whiteA(.05),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? style.accent.withValues(alpha: .72) : WBColors.whiteA(.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: style.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                style.label,
                style: WBText.grotesk(
                  size: 12,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? activeLabelColor : WBColors.textA(.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
