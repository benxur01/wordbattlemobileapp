import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_effects.dart';
import '../theme.dart';
import 'primary_button.dart';

/// Card for managing game audio effects (mute switch, master volume slider,
/// and quick preview button) using device-local [SoundEffects] state.
class SoundSettingsCard extends StatelessWidget {
  const SoundSettingsCard({super.key, this.soundEffects});

  /// Optional override for testing. Defaults to [SoundEffects.instance].
  final SoundEffects? soundEffects;

  @override
  Widget build(BuildContext context) {
    final sfx = soundEffects ?? SoundEffects.instance;

    return ListenableBuilder(
      listenable: sfx,
      builder: (context, _) {
        final isMuted = sfx.isMuted;
        final volume = sfx.volume;
        final volumePercent = (volume * 100).round();

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: WBColors.whiteA(.045),
            border: Border.all(color: WBColors.whiteA(.09)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isMuted ? WBColors.whiteA(.06) : WBColors.accentA(.14),
                      border: Border.all(
                        color: isMuted ? WBColors.whiteA(.1) : WBColors.accentA(.32),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isMuted || volume <= 0.01
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: 18,
                      color: isMuted ? WBColors.textA(.45) : WBColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ovoz effektlari',
                          style: WBText.grotesk(
                            size: 14.5,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isMuted
                              ? "O'chirilgan · ovozsiz rejim"
                              : 'Yoqilgan · $volumePercent% balandlik',
                          style: WBText.grotesk(
                            size: 12,
                            color: WBColors.textA(.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: 'Ovoz effektlari kaliti',
                    toggled: !isMuted,
                    child: CupertinoSwitch(
                      key: const Key('sound_fx_switch'),
                      value: !isMuted,
                      activeTrackColor: WBColors.green,
                      inactiveTrackColor: WBColors.whiteA(.12),
                      onChanged: (enabled) async {
                        await HapticFeedback.selectionClick();
                        await sfx.setMuted(!enabled);
                        if (enabled) {
                          await sfx.playPreview();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: WBColors.whiteA(.07)),
              const SizedBox(height: 10),
              AnimatedOpacity(
                opacity: isMuted ? 0.42 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Row(
                  children: [
                    Text(
                      'Balandlik',
                      style: WBText.grotesk(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: WBColors.textA(.65),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: WBColors.accent,
                          inactiveTrackColor: WBColors.whiteA(.12),
                          thumbColor: WBColors.accent,
                          overlayColor: WBColors.accentA(.18),
                          disabledActiveTrackColor: WBColors.textA(.3),
                          disabledInactiveTrackColor: WBColors.whiteA(.08),
                          disabledThumbColor: WBColors.textA(.4),
                        ),
                        child: Slider(
                          key: const Key('sound_fx_volume_slider'),
                          value: volume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          onChanged: isMuted ? null : (v) => sfx.setVolume(v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '$volumePercent%',
                        textAlign: TextAlign.right,
                        style: WBText.mono(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: isMuted ? WBColors.textA(.38) : WBColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pressable(
                      key: const Key('sound_fx_preview_btn'),
                      semanticLabel: 'Ovozni sinab ko‘rish',
                      onTap: isMuted
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              sfx.playPreview();
                            },
                      pressScale: .95,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isMuted ? WBColors.whiteA(.04) : WBColors.accentA(.14),
                          border: Border.all(
                            color: isMuted ? WBColors.whiteA(.08) : WBColors.accentA(.32),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Sinash',
                          style: WBText.grotesk(
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: isMuted ? WBColors.textA(.35) : WBColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
