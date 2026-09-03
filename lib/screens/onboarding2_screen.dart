import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';
import '../widgets/stroke_glyph.dart';
import '../widgets/synced_text_field.dart';

class Onboarding2Screen extends StatelessWidget {
  const Onboarding2Screen({
    super.key,
    required this.nickname,
    required this.nickState,
    required this.nickError,
    required this.suggestions,
    required this.onNickChanged,
    required this.onPickSuggestion,
    required this.onSubmit,
  });

  final String nickname;
  final NickState nickState;
  final String nickError;
  final List<String> suggestions;
  final ValueChanged<String> onNickChanged;
  final ValueChanged<String> onPickSuggestion;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    // With the keyboard open the canvas is barely 450dp tall, and this column
    // is a fixed ~460dp of content: it has to be able to scroll instead of
    // overflowing. IntrinsicHeight keeps the `Spacer` (which pins the CTA to
    // the bottom) working when there *is* enough room.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final free = nickState == NickState.free;
    final taken = nickState == NickState.taken;
    final checking = nickState == NickState.checking;
    final hint = nickState == NickState.idle || checking;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Container(height: 4, decoration: BoxDecoration(color: WBColors.accent, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 4, decoration: BoxDecoration(color: WBColors.accent, borderRadius: BorderRadius.circular(99)))),
          ]),
          const SizedBox(height: 30),
          Text('Arenada qanday\nchaqirilasan?', style: WBText.grotesk(size: 27, weight: FontWeight.w700, height: 1.15, letterSpacing: -.01)),
          const SizedBox(height: 8),
          Text("Bu nom raqiblaringga va liderlar taxtasida ko'rinadi.",
              style: WBText.grotesk(size: 14, height: 1.5, color: WBColors.textA(.55))),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: WBColors.whiteA(.045),
              border: Border.all(color: WBColors.whiteA(.1)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TAXALLUS', style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4), letterSpacing: .14)),
                    Text('${nickname.length}/16', style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.3))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SyncedTextField(
                        value: nickname,
                        onChanged: onNickChanged,
                        onSubmitted: (_) => onSubmit?.call(),
                        // Android's keyboard capitalises and autocorrects by
                        // default, which fights a lowercase-only nickname rule.
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        maxLength: 16,
                        style: WBText.grotesk(size: 20, weight: FontWeight.w600),
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'masalan, jasur_07',
                          hintStyle: WBText.grotesk(size: 20, weight: FontWeight.w600, color: WBColors.textA(.3)),
                        ),
                      ),
                    ),
                    if (checking) const SpinnerRing(size: 18, trackColor: Color.fromRGBO(244, 243, 248, .2), activeColor: Color.fromRGBO(244, 243, 248, .6)),
                    if (free)
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(color: WBColors.greenA(.16), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const StrokeGlyph.check(
                          width: 10,
                          height: 6,
                          thickness: 2.5,
                          color: WBColors.green,
                          offset: Offset(0, -1.5),
                        ),
                      ),
                    if (taken)
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(color: WBColors.redA(.16), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text('×', style: WBText.grotesk(size: 15, color: WBColors.redSoft)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (taken) ...[
            const SizedBox(height: 12),
            Text("Bu taxallus band. Bo'shlari:", style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.redSoft)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in suggestions)
                  GestureDetector(
                    onTap: () => onPickSuggestion(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: WBColors.accentA(.11),
                        border: Border.all(color: WBColors.accentA(.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(s, style: WBText.grotesk(size: 13.5, weight: FontWeight.w600, color: WBColors.accent)),
                    ),
                  ),
              ],
            ),
          ],
          if (hint) ...[
            const SizedBox(height: 12),
            Text('3–16 ta belgi: lotin harflari, raqam va pastki chiziq. Har bir taxallus faqat bitta o\'yinchiga tegishli.',
                style: WBText.grotesk(size: 12.5, height: 1.45, color: WBColors.textA(.5))),
          ],
          if (free) ...[
            const SizedBox(height: 12),
            Text('Bo\'sh — bu nom senga biriktiriladi', style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.green)),
          ],
          if (nickState == NickState.bad) ...[
            const SizedBox(height: 12),
            Text(nickError, style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.redSoft)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: WBColors.whiteA(.03),
              border: Border.all(color: WBColors.whiteA(.08)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: WBColors.greenA(.14), border: Border.all(color: WBColors.greenA(.3)), borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: const StrokeGlyph.check(
                    width: 11,
                    height: 7,
                    thickness: 2.5,
                    color: WBColors.green,
                    offset: Offset(0, -1.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Boshqa hech narsa kerak emas — yosh ham, sinf ham. Keyingi qadam: jang.',
                      style: WBText.grotesk(size: 12.5, height: 1.45, color: WBColors.textA(.55))),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (free)
            Pressable(
              onTap: onSubmit,
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  gradient: wbAccentGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: WBColors.accentA(.26), blurRadius: 34, offset: const Offset(0, 14))],
                ),
                alignment: Alignment.center,
                child: Text('Arenaga kirish', style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.accentInk)),
              ),
            )
          else
            Container(
              height: 62,
              decoration: BoxDecoration(color: WBColors.whiteA(.05), border: Border.all(color: WBColors.whiteA(.09)), borderRadius: BorderRadius.circular(20)),
              alignment: Alignment.center,
              child: Text('Arenaga kirish', style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: WBColors.textA(.3))),
            ),
        ],
      ),
    );
  }
}
