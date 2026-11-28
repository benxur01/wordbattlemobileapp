import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/hint_filter.dart';
import '../utils/rare_letter_drill.dart';
import '../widgets/hint_filter_bar.dart';
import '../widgets/practice_test_input.dart';
import '../widgets/primary_button.dart';
import '../widgets/rare_letter_drill_panel.dart';
import '../widgets/stroke_glyph.dart';
import '../widgets/word_share_preview_sheet.dart';

enum _PracticeMode { daily, rareDrills }

/// The practice screen: switches seamlessly between the server's word of the
/// day and specialized rare-letter X & Q mastery drills.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.word,
    required this.hints,
    required this.onHint,
    required this.onBack,
    this.onCheckWord,
    this.selectedHintLetter,
    this.selectedLengthFilter = HintLengthFilter.all,
    this.onHintFilterChanged,
    this.rareDrills = const [],
    this.selectedDrillLetter = 'x',
    this.onSelectDrillLetter,
    this.onRotateDrillPrompt,
    this.onCheckDrillWord,
  });

  /// Null while the request is in flight.
  final PracticeWordDto? word;
  final List<String> hints;
  final VoidCallback onHint;
  final VoidCallback onBack;

  /// Optional async dictionary check against the server.
  final Future<PracticeCheckDto> Function(String word)? onCheckWord;

  /// Active starting letter filter for hints (`a`..`z`), defaulting to the
  /// ending letter of [word] when null.
  final String? selectedHintLetter;

  /// Active word-length filter bucket for hints.
  final HintLengthFilter selectedLengthFilter;

  /// Called when the player switches either the hint starting letter or length
  /// filter chip so the parent can fetch fresh filtered hints.
  final void Function(String letter, HintLengthFilter length)? onHintFilterChanged;

  /// Rare-letter X & Q drills fetched from the server (falls back locally).
  final List<RareLetterDrillDto> rareDrills;

  /// Parent-driven selected rare letter (`'x'` or `'q'`).
  final String selectedDrillLetter;

  /// Called when the player switches between X and Q drill tiles.
  final ValueChanged<String>? onSelectDrillLetter;

  /// Rotates the active drill's prompt word sample.
  final VoidCallback? onRotateDrillPrompt;

  /// Optional server validation specifically for rare-letter drill inputs.
  final Future<PracticeCheckDto> Function(String letter, String word)? onCheckDrillWord;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final GlobalKey<PracticeTestInputState> _inputKey = GlobalKey<PracticeTestInputState>();
  final List<String> _testedWords = [];
  String? _localHintLetter;
  HintLengthFilter _localLengthFilter = HintLengthFilter.all;
  _PracticeMode _mode = _PracticeMode.daily;
  String _localDrillLetter = 'x';
  int _localDrillOffset = 0;
  Map<String, RareLetterProgress> _drillProgress = RareLetterDrillHelper.emptyProgressMap();
  final Map<String, int> _drillBurstNonce = {'x': 0, 'q': 0};

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDrillProgress());
  }

  Future<void> _restoreDrillProgress() async {
    final loaded = await RareLetterDrillHelper.loadProgress();
    if (!mounted) return;
    setState(() => _drillProgress = loaded);
  }

  @override
  void didUpdateWidget(covariant PracticeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word?.word != widget.word?.word) {
      _testedWords.clear();
      _localHintLetter = null;
      _localLengthFilter = HintLengthFilter.all;
      _inputKey.currentState?.resetInput();
    }
    if (oldWidget.selectedDrillLetter != widget.selectedDrillLetter) {
      _inputKey.currentState?.resetInput();
    }
  }

  String? get _needLetter {
    final raw = widget.word?.word;
    if (raw == null || raw.isEmpty) return null;
    return raw.substring(raw.length - 1).toLowerCase();
  }

  String get _activeDrillLetter =>
      RareLetterDrillHelper.normalizeLetter(
        widget.onSelectDrillLetter != null ? widget.selectedDrillLetter : _localDrillLetter,
      ) ??
      'x';

  List<RareLetterDrillDto> get _resolvedDrills {
    if (widget.rareDrills.isNotEmpty) return widget.rareDrills;
    final base = RareLetterDrillHelper.fallbackDrills();
    if (_localDrillOffset == 0) return base;
    const altX = [
      ('apex', '/ˈeɪpeks/', "cho'qqi — eng yuqori nuqta"),
      ('matrix', '/ˈmeɪtrɪks/', 'matritsa — qator va ustunlar jadvali'),
      ('vortex', '/ˈvɔːteks/', 'girdob — kuchli aylanma oqim'),
    ];
    const altQ = [
      ('quartz', '/kwɔːts/', 'kvars — shaffof va qattiq mineral tosh'),
      ('quest', '/kwest/', 'izlanish, maqsadli safar'),
      ('quorum', '/ˈkwɔːrəm/', 'kvorum — qaror qabul qilish uchun yetarli son'),
    ];
    return [
      for (final d in base)
        RareLetterDrillDto(
          letter: d.letter,
          badge: d.badge,
          title: d.title,
          subtitle: d.subtitle,
          tip: d.tip,
          promptWord: d.normalizedLetter == 'x'
              ? altX[_localDrillOffset % altX.length].$1
              : altQ[_localDrillOffset % altQ.length].$1,
          promptIpa: d.normalizedLetter == 'x'
              ? altX[_localDrillOffset % altX.length].$2
              : altQ[_localDrillOffset % altQ.length].$2,
          promptMeaning: d.normalizedLetter == 'x'
              ? altX[_localDrillOffset % altX.length].$3
              : altQ[_localDrillOffset % altQ.length].$3,
          targetCount: d.targetCount,
          hints: d.hints,
        ),
    ];
  }

  void _selectDrillLetter(String letter) {
    final clean = RareLetterDrillHelper.normalizeLetter(letter);
    if (clean == null) return;
    setState(() => _localDrillLetter = clean);
    widget.onSelectDrillLetter?.call(clean);
    _inputKey.currentState?.resetInput();
  }

  void _rotateDrillPrompt() {
    if (widget.onRotateDrillPrompt != null) {
      widget.onRotateDrillPrompt!();
      return;
    }
    setState(() => _localDrillOffset++);
  }

  void _onAcceptedWord(String word) {
    if (_mode == _PracticeMode.rareDrills) {
      final key = _activeDrillLetter;
      final current = _drillProgress[key] ?? RareLetterProgress(letter: key, solvedWords: const []);
      final res = current.record(word);
      if (res.added) {
        HapticFeedback.lightImpact();
        setState(() {
          _drillProgress = {..._drillProgress, key: res.next};
          _drillBurstNonce[key] = (_drillBurstNonce[key] ?? 0) + 1;
        });
        if (res.justMastered) {
          HapticFeedback.mediumImpact();
          SoundEffects.instance.playVictory();
        }
        unawaited(RareLetterDrillHelper.saveProgress(_drillProgress));
      }
      return;
    }
    setState(() {
      if (!_testedWords.contains(word)) {
        _testedWords.insert(0, word);
      }
    });
  }

  void _resetActiveDrillProgress() {
    final key = _activeDrillLetter;
    final current = _drillProgress[key];
    if (current == null || current.solvedWords.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _drillProgress = {..._drillProgress, key: current.cleared()};
    });
    unawaited(RareLetterDrillHelper.saveProgress(_drillProgress));
  }

  void _clearTestedWords() {
    setState(() => _testedWords.clear());
  }

  int get _totalTestedCharacters => _testedWords.fold(0, (sum, w) => sum + w.length);

  String? get _activeHintLetter =>
      HintFilterHelper.normalizeLetter(widget.selectedHintLetter) ??
      HintFilterHelper.normalizeLetter(_localHintLetter) ??
      _needLetter;

  HintLengthFilter get _activeLengthFilter =>
      widget.onHintFilterChanged != null ? widget.selectedLengthFilter : _localLengthFilter;

  void _updateHintFilter({String? letter, HintLengthFilter? length}) {
    final nextLetter = HintFilterHelper.normalizeLetter(letter ?? _activeHintLetter);
    final nextLength = length ?? _activeLengthFilter;
    if (widget.onHintFilterChanged != null && nextLetter != null) {
      widget.onHintFilterChanged!(nextLetter, nextLength);
      return;
    }
    setState(() {
      _localHintLetter = nextLetter;
      _localLengthFilter = nextLength;
    });
  }

  void _resetHintFilters() {
    final fallback = _needLetter ?? 'a';
    _updateHintFilter(letter: fallback, length: HintLengthFilter.all);
  }

  void _shareWordCard(PracticeWordDto word) {
    WordSharePreviewSheet.show(
      context,
      word: word,
      practicedCount: _testedWords.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final isDrillMode = _mode == _PracticeMode.rareDrills;
    final drills = _resolvedDrills;
    final activeDrillKey = _activeDrillLetter;
    final activeDrill = drills.firstWhere(
      (d) => d.normalizedLetter == activeDrillKey,
      orElse: () => drills.first,
    );
    final effectiveNeedLetter = isDrillMode ? activeDrill.normalizedLetter : _needLetter;
    final needUpper = effectiveNeedLetter?.toUpperCase() ?? '·';
    final shareWord = word ??
        (isDrillMode
            ? PracticeWordDto(
                word: activeDrill.promptWord,
                ipa: activeDrill.promptIpa,
                meaning: activeDrill.promptMeaning,
              )
            : null);
    final activeLetter = _activeHintLetter;
    final activeLength = _activeLengthFilter;
    final visibleHints = HintFilterHelper.apply(
      widget.hints,
      startingLetter: activeLetter,
      lengthFilter: activeLength,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: WBColors.hairline)),
          ),
          child: Row(
            children: [
              Pressable(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(12),
                semanticLabel: 'Orqaga',
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: WBColors.bgSurface,
                    border: Border.all(color: WBColors.hairline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: StrokeGlyph.chevronLeft(
                    size: 11,
                    thickness: 2,
                    color: WBColors.textA(.8),
                    offset: const Offset(2, 0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildModeSwitcher()),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                    decoration: BoxDecoration(
                      color: WBColors.bgSurface,
                      border: Border.all(color: WBColors.hairline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isDrillMode
                          ? '${_drillProgress[activeDrill.normalizedLetter]?.solvedCount ?? 0}/${activeDrill.targetCount}'
                          : (word == null ? '…' : '${word.word.length}'),
                      style: WBText.mono(size: 12.5, weight: FontWeight.w700, color: WBColors.text),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Pressable(
                    onTap: shareWord == null ? null : () => _shareWordCard(shareWord),
                    pressScale: .94,
                    borderRadius: BorderRadius.circular(12),
                    semanticLabel: 'Kun so\'zini ulashish',
                    child: Opacity(
                      opacity: shareWord == null ? .38 : 1,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: WBColors.bgSurface,
                          border: Border.all(color: WBColors.hairline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.ios_share, size: 16, color: WBColors.textA(.8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (isDrillMode)
                RareLetterDrillPanel(
                  drills: drills,
                  activeLetter: activeDrill.normalizedLetter,
                  progressMap: _drillProgress,
                  burstNonceMap: _drillBurstNonce,
                  onSelectLetter: _selectDrillLetter,
                  onRotatePrompt: _rotateDrillPrompt,
                  onResetProgress: _resetActiveDrillProgress,
                  onTapWordChip: (hint) => _inputKey.currentState?.fillWord(hint),
                )
              else ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: WBColors.bgSurface,
                  border: Border.all(color: WBColors.hairline),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "YANGI SO'Z",
                          style: WBText.mono(
                            size: 10,
                            weight: FontWeight.w600,
                            color: WBColors.textA(.48),
                            letterSpacing: .12,
                          ),
                        ),
                        if (word != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: WBColors.bgElevated,
                              border: Border.all(color: WBColors.hairlineStrong),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OXIRGI HARF: $needUpper',
                              style: WBText.mono(
                                size: 9.5,
                                weight: FontWeight.w700,
                                color: WBColors.text,
                                letterSpacing: .07,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            word?.word ?? '…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WBText.grotesk(size: 27, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Text(word?.ipa ?? '', style: WBText.mono(size: 13, color: WBColors.textA(.45))),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      word?.meaning ?? '',
                      style: WBText.grotesk(size: 14.5, height: 1.5, color: WBColors.textA(.72)),
                    ),
                  ],
                ),
              ),
              if (_testedWords.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      "SINALGAN SO'ZLAR",
                      style: WBText.mono(
                        size: 10,
                        weight: FontWeight.w600,
                        color: WBColors.green,
                        letterSpacing: .12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: WBColors.greenA(.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_testedWords.length} · +$_totalTestedCharacters harf',
                        style: WBText.mono(size: 10.5, weight: FontWeight.w700, color: WBColors.green),
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: _clearTestedWords,
                      pressScale: .94,
                      borderRadius: BorderRadius.circular(8),
                      semanticLabel: "Sinalgan so'zlarni tozalash",
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Tozalash',
                          style: WBText.grotesk(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final tested in _testedWords) _testedChip(tested)],
                ),
              ],
              const SizedBox(height: 14),
              if (word != null) ...[
                HintFilterBar(
                  selectedLetter: activeLetter,
                  defaultLetter: _needLetter,
                  selectedLength: activeLength,
                  onLetterSelected: (letter) => _updateHintFilter(letter: letter),
                  onLengthSelected: (length) => _updateHintFilter(length: length),
                ),
                const SizedBox(height: 14),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.hints.isEmpty
                    ? Align(
                        key: const ValueKey('hints_empty'),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Bu so'z bilan boshlanadigan so'zlarni ko'rish uchun «?» tugmasini bosing",
                          style: WBText.grotesk(size: 13, height: 1.5, color: WBColors.textA(.5)),
                        ),
                      )
                    : visibleHints.isEmpty
                        ? Container(
                            key: ValueKey('hints_filtered_empty_${activeLetter}_${activeLength.name}'),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: WBColors.whiteA(.035),
                              border: Border.all(color: WBColors.whiteA(.08)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "Ushbu filtr bo'yicha maslahat topilmadi",
                                    style: WBText.grotesk(size: 12.5, color: WBColors.textA(.55)),
                                  ),
                                ),
                                Pressable(
                                  onTap: _resetHintFilters,
                                  pressScale: .95,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Text(
                                      'Filtrni tiklash',
                                      style: WBText.grotesk(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: WBColors.indigoText,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            key: ValueKey('hints_${activeLetter}_${activeLength.name}_${visibleHints.length}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "MASLAHAT SO'ZLAR",
                                    style: WBText.mono(
                                      size: 10,
                                      weight: FontWeight.w500,
                                      color: WBColors.textA(.45),
                                      letterSpacing: .12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (activeLetter != null)
                                    Text(
                                      '${activeLetter.toUpperCase()} · ${activeLength.label}',
                                      style: WBText.mono(
                                        size: 10,
                                        weight: FontWeight.w600,
                                        color: WBColors.indigoText,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 9,
                                runSpacing: 9,
                                children: [for (final hint in visibleHints) _hintChip(hint)],
                              ),
                            ],
                          ),
              ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          decoration: BoxDecoration(
            color: WBColors.bg.withValues(alpha: .96),
            border: Border(top: BorderSide(color: WBColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: WBColors.bgElevated,
                      border: Border.all(color: WBColors.hairlineStrong),
                      borderRadius: BorderRadius.circular(7.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      needUpper,
                      style: WBText.mono(size: 12.5, weight: FontWeight.w700, color: WBColors.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "harfi bilan boshlanadigan so'zlar",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 12.5, color: WBColors.textA(.52)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: isDrillMode ? _rotateDrillPrompt : widget.onHint,
                    pressScale: .95,
                    borderRadius: BorderRadius.circular(11),
                    semanticLabel: isDrillMode
                        ? "Keyingi namuna so'zni olish"
                        : "Maslahat so'zlarni olish",
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: WBColors.bgElevated,
                        border: Border.all(color: WBColors.hairlineStrong),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isDrillMode ? '↻' : '?',
                            style: WBText.mono(size: 12, weight: FontWeight.w700, color: WBColors.indigoText),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isDrillMode ? 'Keyingi' : 'Maslahat',
                            style: WBText.grotesk(size: 12, weight: FontWeight.w600, color: WBColors.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PracticeTestInput(
                key: _inputKey,
                needLetter: effectiveNeedLetter,
                triedWords: isDrillMode
                    ? (_drillProgress[activeDrill.normalizedLetter]?.solvedWords.toSet() ?? const {})
                    : _testedWords.toSet(),
                enabled: isDrillMode || word != null,
                onCheckWord: isDrillMode
                    ? (widget.onCheckDrillWord != null
                        ? (candidate) => widget.onCheckDrillWord!(activeDrill.normalizedLetter, candidate)
                        : null)
                    : widget.onCheckWord,
                onAcceptedWord: _onAcceptedWord,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _testedChip(String word) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('tested_$word'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.86 + (0.14 * value),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: WBColors.greenA(.10),
          border: Border.all(color: WBColors.green.withValues(alpha: .42)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 14, color: WBColors.green),
            const SizedBox(width: 6),
            Text(
              word,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600, color: WBColors.text),
            ),
            const SizedBox(width: 6),
            Text(
              '${word.length}',
              style: WBText.mono(size: 11, weight: FontWeight.w600, color: WBColors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintChip(String word) {
    final head = word.substring(0, word.length - 1);
    final last = word.substring(word.length - 1);
    return Pressable(
      onTap: () => _inputKey.currentState?.fillWord(word),
      pressScale: .96,
      borderRadius: BorderRadius.circular(14),
      semanticLabel: "$word so'zini sinov maydoniga kiritish",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.05),
          border: Border.all(color: WBColors.whiteA(.1)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: RichText(
          text: TextSpan(
            style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.textA(.85)),
            children: [
              TextSpan(text: head),
              TextSpan(
                text: last,
                style: TextStyle(color: WBColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    final anyMastered = _drillProgress.values.any((p) => p.isMastered);
    return Container(
      key: const Key('practice_mode_switcher'),
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WBColors.bgDeep,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WBColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTabButton(
              label: "Kun so'zi",
              selected: _mode == _PracticeMode.daily,
              onTap: () {
                if (_mode == _PracticeMode.daily) return;
                HapticFeedback.selectionClick();
                SoundEffects.instance.playTap();
                setState(() => _mode = _PracticeMode.daily);
                _inputKey.currentState?.resetInput();
              },
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ModeTabButton(
              label: 'X · Q',
              badgeColor: anyMastered ? WBColors.green : WBColors.amber,
              selected: _mode == _PracticeMode.rareDrills,
              onTap: () {
                if (_mode == _PracticeMode.rareDrills) return;
                HapticFeedback.selectionClick();
                SoundEffects.instance.playTap();
                setState(() => _mode = _PracticeMode.rareDrills);
                _inputKey.currentState?.resetInput();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final isLight = WBTheme.isLight;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        pressScale: .97,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? (isLight ? Colors.white : WBColors.bgPressed) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected ? Border.all(color: WBColors.hairlineStrong) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeColor != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(
                    size: 12.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? WBColors.text : WBColors.textA(.58),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
