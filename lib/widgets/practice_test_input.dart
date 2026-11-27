import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../audio/sound_effects.dart';
import '../theme.dart';
import '../utils/practice_word_validator.dart';
import '../utils/transliteration.dart';
import 'primary_button.dart';
import 'spinner_ring.dart';
import 'stroke_glyph.dart';

export '../utils/practice_word_validator.dart';

/// Interactive practice input with real-time soft glow border validation and
/// damped elastic horizontal shake on invalid input.
class PracticeTestInput extends StatefulWidget {
  const PracticeTestInput({
    super.key,
    required this.needLetter,
    required this.triedWords,
    required this.onAcceptedWord,
    this.onCheckWord,
    this.enabled = true,
  });

  /// Lowercase or uppercase required starting letter (null while word loads).
  final String? needLetter;

  /// Words the player already passed in this practice session.
  final Set<String> triedWords;

  /// Called once a word passes both local rules and optional server dictionary check.
  final ValueChanged<String> onAcceptedWord;

  /// Optional remote dictionary check. When null, local chain rules decide validity.
  final Future<PracticeCheckDto> Function(String word)? onCheckWord;

  final bool enabled;

  @override
  State<PracticeTestInput> createState() => PracticeTestInputState();
}

class PracticeTestInputState extends State<PracticeTestInput> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  PracticeInputPhase _phase = PracticeInputPhase.idle;
  String? _statusMessage;
  bool _hasFocus = false;
  bool _translitHintVisible = false;
  Timer? _statusResetTimer;
  Timer? _translitTimer;

  /// Exposes the current validation phase for diagnostics and widget tests.
  PracticeInputPhase get phase => _phase;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant PracticeTestInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.needLetter != widget.needLetter) {
      resetInput();
    }
  }

  @override
  void dispose() {
    _statusResetTimer?.cancel();
    _translitTimer?.cancel();
    _focus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focus.hasFocus);
  }

  /// Programmatically prefills a candidate word (for example when a hint chip is tapped).
  void fillWord(String word) {
    final normalized = transliterateCyrillicToLatin(word).trim().toLowerCase();
    _controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    _onTextChanged(normalized);
    _focus.requestFocus();
  }

  /// Clears the field back to its neutral idle validation state.
  void resetInput() {
    _statusResetTimer?.cancel();
    _controller.clear();
    if (!mounted) return;
    setState(() {
      _phase = PracticeInputPhase.idle;
      _statusMessage = null;
    });
  }

  void _triggerShake() {
    HapticFeedback.vibrate();
    _shakeController.forward(from: 0);
  }

  void _onCyrillicDetected(String _) {
    HapticFeedback.selectionClick();
    _translitTimer?.cancel();
    if (!_translitHintVisible && mounted) {
      setState(() => _translitHintVisible = true);
    }
    _translitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _translitHintVisible = false);
    });
  }

  void _onTextChanged(String value) {
    _statusResetTimer?.cancel();
    final previousPhase = _phase;
    final result = PracticeWordValidator.validateLive(
      value,
      needLetter: widget.needLetter,
      triedWords: widget.triedWords,
    );

    setState(() {
      _phase = result.phase;
      _statusMessage = result.message;
    });

    // Shake immediately when transitioning into invalid on a live keystroke
    // (such as typing the wrong first character), without jerking every extra key.
    if (result.phase == PracticeInputPhase.invalid && previousPhase != PracticeInputPhase.invalid) {
      _triggerShake();
    }
  }

  Future<void> submit() async {
    if (!widget.enabled || _phase == PracticeInputPhase.checking) return;

    _statusResetTimer?.cancel();
    final result = PracticeWordValidator.validateSubmit(
      _controller.text,
      needLetter: widget.needLetter,
      triedWords: widget.triedWords,
    );

    if (result.isInvalid) {
      SoundEffects.instance.playWordError();
      setState(() {
        _phase = PracticeInputPhase.invalid;
        _statusMessage = result.message;
      });
      _triggerShake();
      return;
    }

    final candidate = result.normalizedWord;
    if (widget.onCheckWord != null) {
      setState(() {
        _phase = PracticeInputPhase.checking;
        _statusMessage = "Lug'atdan tekshirilmoqda…";
      });

      final check = await widget.onCheckWord!(candidate);
      if (!mounted) return;

      // Ignore stale responses if the player kept typing while the check was in flight.
      if (_controller.text.trim().toLowerCase() != candidate) {
        _onTextChanged(_controller.text);
        return;
      }

      if (!check.valid) {
        SoundEffects.instance.playWordError();
        setState(() {
          _phase = PracticeInputPhase.invalid;
          _statusMessage = check.reason ?? "Bu so'z ingliz lug'atida yo'q";
        });
        _triggerShake();
        return;
      }
    }

    SoundEffects.instance.playWordSuccess();
    HapticFeedback.lightImpact();
    _controller.clear();
    widget.onAcceptedWord(candidate);

    setState(() {
      _phase = PracticeInputPhase.accepted;
      _statusMessage = "«$candidate» to'g'ri so'z! (+${candidate.length} harf)";
    });

    _statusResetTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted || _controller.text.isNotEmpty) return;
      setState(() {
        _phase = PracticeInputPhase.idle;
        _statusMessage = null;
      });
    });
  }

  Color _borderColor() => switch (_phase) {
        PracticeInputPhase.valid => WBColors.green.withValues(alpha: WBTheme.isLight ? .85 : .78),
        PracticeInputPhase.accepted => WBColors.green,
        PracticeInputPhase.invalid => WBColors.red.withValues(alpha: .85),
        PracticeInputPhase.incomplete => WBColors.cta.withValues(alpha: WBTheme.isLight ? .78 : .72),
        PracticeInputPhase.checking => WBColors.cta.withValues(alpha: .72),
        PracticeInputPhase.idle => _hasFocus ? WBColors.hairlineStrong : WBColors.hairline,
      };

  Color _fillColor() {
    final isLight = WBTheme.isLight;
    return switch (_phase) {
      PracticeInputPhase.valid => WBColors.greenA(isLight ? .09 : .07),
      PracticeInputPhase.accepted => WBColors.greenA(isLight ? .13 : .10),
      PracticeInputPhase.invalid => WBColors.redA(isLight ? .09 : .08),
      PracticeInputPhase.incomplete || PracticeInputPhase.checking || PracticeInputPhase.idle =>
        WBColors.bgElevated,
    };
  }

  List<BoxShadow> _glowShadows() {
    final glowBoost = WBTheme.isLight ? 0.85 : 1.0;
    return switch (_phase) {
      PracticeInputPhase.valid => [
          BoxShadow(
            color: WBColors.green.withValues(alpha: .26 * glowBoost),
            blurRadius: WBTheme.isLight ? 14 : 16,
            spreadRadius: 1,
          ),
        ],
      PracticeInputPhase.accepted => [
          BoxShadow(
            color: WBColors.green.withValues(alpha: .36 * glowBoost),
            blurRadius: WBTheme.isLight ? 16 : 20,
            spreadRadius: 1.5,
          ),
        ],
      PracticeInputPhase.invalid => [
          BoxShadow(
            color: WBColors.red.withValues(alpha: .28 * glowBoost),
            blurRadius: WBTheme.isLight ? 14 : 16,
            spreadRadius: 1,
          ),
        ],
      PracticeInputPhase.incomplete ||
      PracticeInputPhase.checking ||
      PracticeInputPhase.idle =>
        const [],
    };
  }

  Color _statusColor() => switch (_phase) {
        PracticeInputPhase.valid || PracticeInputPhase.accepted => WBColors.green,
        PracticeInputPhase.invalid => WBColors.redSoft,
        PracticeInputPhase.incomplete || PracticeInputPhase.checking => WBColors.indigoText,
        PracticeInputPhase.idle => WBColors.textA(.45),
      };

  @override
  Widget build(BuildContext context) {
    final upperLetter = widget.needLetter?.toUpperCase() ?? '·';
    final hintText = widget.needLetter == null ? "so'z yuklanmoqda…" : "«$upperLetter» dan so'z sinab ko'r…";
    final isChecking = _phase == PracticeInputPhase.checking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final t = _shakeController.value;
            final shakeX = (t == 0.0 || t == 1.0) ? 0.0 : math.sin(t * math.pi * 6) * (1.0 - t) * 10.0;
            return Transform.translate(
              key: const ValueKey('practice_shake_transform'),
              offset: Offset(shakeX, 0),
              child: child,
            );
          },
          child: Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _fillColor(),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _borderColor(),
                      width: _phase == PracticeInputPhase.idle ? 1.2 : 1.6,
                    ),
                    boxShadow: _glowShadows(),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          onChanged: _onTextChanged,
                          onSubmitted: (_) => submit(),
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [],
                          inputFormatters: [
                            CyrillicToLatinFormatter(onCyrillicDetected: _onCyrillicDetected),
                          ],
                          textInputAction: TextInputAction.send,
                          style: WBText.grotesk(size: 18, weight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            hintText: hintText,
                            hintStyle: WBText.grotesk(
                              size: 16.5,
                              weight: FontWeight.w500,
                              color: WBColors.textA(.32),
                            ),
                          ),
                        ),
                      ),
                      if (_controller.text.trim().isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor().withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${_controller.text.trim().length}',
                            style: WBText.mono(
                              size: 11,
                              weight: FontWeight.w700,
                              color: _statusColor(),
                            ),
                          ),
                        ),
                      ],
                      if (_phase == PracticeInputPhase.valid || _phase == PracticeInputPhase.accepted)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_circle_rounded, size: 20, color: WBColors.green),
                        )
                      else if (_phase == PracticeInputPhase.invalid)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.error_outline_rounded, size: 20, color: WBColors.redSoft),
                        ),
                      if (_controller.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Pressable(
                            onTap: resetInput,
                            pressScale: .9,
                            borderRadius: BorderRadius.circular(10),
                            semanticLabel: 'Tozalash',
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: WBColors.whiteA(.08),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(Icons.close_rounded, size: 14, color: WBColors.textA(.65)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: widget.enabled && !isChecking ? submit : null,
                pressScale: .95,
                borderRadius: BorderRadius.circular(18),
                semanticLabel: "So'zni tekshirish",
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: _phase == PracticeInputPhase.valid || _phase == PracticeInputPhase.accepted
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [WBColors.green, WBColors.teal],
                          )
                        : wbCtaGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      if (_phase != PracticeInputPhase.valid && _phase != PracticeInputPhase.accepted)
                        BoxShadow(
                          color: WBColors.ctaLip,
                          offset: const Offset(0, 2.5),
                          blurRadius: 0,
                        ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: isChecking
                      ? SpinnerRing(
                          size: 20,
                          trackColor: Colors.white.withValues(alpha: .25),
                          activeColor: Colors.white,
                        )
                      : StrokeGlyph.chevronRight(
                          size: 14,
                          thickness: 2.8,
                          color: _phase == PracticeInputPhase.valid || _phase == PracticeInputPhase.accepted
                              ? WBColors.greenInk
                              : WBColors.ctaInk,
                          offset: const Offset(-3, 0),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label: _statusMessage,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Row(
                key: ValueKey('${_phase.name}:$_statusMessage'),
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _statusColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(
                        size: 12,
                        weight: FontWeight.w600,
                        color: _statusColor(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_translitHintVisible) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: WBColors.indigoA(.12),
                  border: Border.all(color: WBColors.indigoA(.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.translate_rounded, size: 12, color: WBColors.indigoText),
                    const SizedBox(width: 5),
                    Text(
                      "Kirill harflari avtomat lotinchaga o'tkazildi",
                      style: WBText.grotesk(size: 11, weight: FontWeight.w500, color: WBColors.indigoText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
