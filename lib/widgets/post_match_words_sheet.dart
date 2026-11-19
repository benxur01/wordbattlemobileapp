import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/duel_models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import 'primary_button.dart';
import 'word_definition_sheet.dart';

enum WordsFilter { all, mine, opponent }

/// A liquid frosted glass modal bottom sheet displaying an interactive post-match
/// breakdown of every word played in the duel, filterable by player, along with
/// letter counts, response times, and dictionary lookup hooks.
class PostMatchWordsSheet extends StatefulWidget {
  const PostMatchWordsSheet({
    super.key,
    required this.words,
    this.opponentName = 'Raqib',
    this.onWordTap,
  });

  /// All words played during the match chain.
  final List<ChainWord> words;

  /// Display name of the opponent player.
  final String opponentName;

  /// Optional callback when a word row is tapped (e.g. for definition sheet).
  final ValueChanged<String>? onWordTap;

  /// Opens the [PostMatchWordsSheet] as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required List<ChainWord> words,
    String opponentName = 'Raqib',
    ValueChanged<String>? onWordTap,
  }) {
    HapticFeedback.lightImpact();
    SoundEffects.instance.playTap();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => PostMatchWordsSheet(
        words: words,
        opponentName: opponentName,
        onWordTap: onWordTap ??
            (word) {
              WordDefinitionSheet.show(context, word: word);
            },
      ),
    );
  }

  @override
  State<PostMatchWordsSheet> createState() => _PostMatchWordsSheetState();
}

class _PostMatchWordsSheetState extends State<PostMatchWordsSheet> {
  WordsFilter _filter = WordsFilter.all;

  List<ChainWord> get _filteredWords {
    return switch (_filter) {
      WordsFilter.all => widget.words,
      WordsFilter.mine => widget.words.where((w) => w.mine).toList(),
      WordsFilter.opponent => widget.words.where((w) => !w.mine).toList(),
    };
  }

  int get _myWordsCount => widget.words.where((w) => w.mine).length;
  int get _opponentWordsCount => widget.words.where((w) => !w.mine).length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWords;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: WBColors.bgPanel.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: WBColors.whiteA(.22),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Title and Summary Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "JANG SO'ZLARI TAHLILI",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.mono(
                              size: 11,
                              weight: FontWeight.w600,
                              color: WBColors.textA(.45),
                              letterSpacing: .15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "${widget.words.length} ta aytilgan so'z",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(
                              size: 20,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      pressScale: .92,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: WBColors.whiteA(.06),
                          border: Border.all(color: WBColors.whiteA(.12)),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: 14,
                            color: WBColors.textA(.65),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Filter Tabs (Barchasi, Seniki, Raqibniki)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: WBColors.whiteA(.04),
                    border: Border.all(color: WBColors.whiteA(.08)),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      _buildTab(
                        filter: WordsFilter.all,
                        label: 'Barchasi',
                        count: widget.words.length,
                      ),
                      _buildTab(
                        filter: WordsFilter.mine,
                        label: 'Seniki',
                        count: _myWordsCount,
                        badgeColor: WBColors.green,
                      ),
                      _buildTab(
                        filter: WordsFilter.opponent,
                        label: widget.opponentName,
                        count: _opponentWordsCount,
                        badgeColor: WBColors.roseText,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Words List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            "Bu toifada so'z topilmadi",
                            textAlign: TextAlign.center,
                            style: WBText.grotesk(
                              size: 14,
                              color: WBColors.textA(.45),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _buildWordCard(item, index);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab({
    required WordsFilter filter,
    required String label,
    required int count,
    Color? badgeColor,
  }) {
    final active = _filter == filter;

    return Expanded(
      child: Pressable(
        onTap: () {
          if (_filter != filter) {
            HapticFeedback.selectionClick();
            SoundEffects.instance.playTap();
            setState(() => _filter = filter);
          }
        },
        pressScale: .97,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? WBColors.whiteA(.12) : Colors.transparent,
            border: Border.all(
              color: active ? WBColors.whiteA(.16) : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(
                    size: 13,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? WBColors.text : WBColors.textA(.55),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (badgeColor ?? WBColors.accent)
                      .withValues(alpha: active ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: WBText.mono(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: badgeColor ?? WBColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordCard(ChainWord item, int index) {
    final isMe = item.mine;
    final timeLabel = item.spentLabel;

    return Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        SoundEffects.instance.playTap();
        if (widget.onWordTap != null) {
          widget.onWordTap!(item.word);
        } else {
          WordDefinitionSheet.show(context, word: item.word);
        }
      },
      pressScale: .98,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? WBColors.greenA(.05) : WBColors.whiteA(.035),
          border: Border.all(
            color: isMe ? WBColors.greenA(.22) : WBColors.whiteA(.08),
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            // Speaker Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isMe ? WBColors.greenA(.16) : WBColors.roseText.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isMe ? 'SEN' : widget.opponentName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.mono(
                  size: 9.5,
                  weight: FontWeight.w700,
                  color: isMe ? WBColors.green : WBColors.roseText,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Word Name
            Expanded(
              child: Text(
                item.word,
                style: WBText.mono(
                  size: 15.5,
                  weight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
            ),

            // Word length badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.09)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${item.word.length} harf',
                style: WBText.mono(
                  size: 10,
                  weight: FontWeight.w500,
                  color: WBColors.textA(.5),
                ),
              ),
            ),

            if (timeLabel != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: WBColors.accentA(.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  timeLabel,
                  style: WBText.mono(
                    size: 10,
                    weight: FontWeight.w600,
                    color: WBColors.accent,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 16, color: WBColors.textA(.35)),
          ],
        ),
      ),
    );
  }
}
