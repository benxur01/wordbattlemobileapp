import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/glow_orb.dart';
import '../widgets/google_logo.dart';
import '../widgets/primary_button.dart';
import '../widgets/spinner_ring.dart';
import '../widgets/synced_text_field.dart';

/// The sign-in button's own colours, deliberately not in [WBColors]: that class
/// is the Word Battle design file ported 1:1, and none of these three came from
/// it. They are Google's published button values, and they are here because the
/// button is the one place in the app that answers to somebody else's spec.
const _googleSurface = Color(0xFFFFFFFF);
const _googleInk = Color(0xFF1F1F1F);
const _googleStroke = Color(0xFFDADCE0);

class Onboarding1Screen extends StatefulWidget {
  const Onboarding1Screen({
    super.key,
    required this.onGoogle,
    this.onDevLogin,
    required this.onRegister,
    required this.onLogin,
    this.showGoogle = true,
    this.googleButton,
    this.googleUnavailableMessage =
        "Google kirish bu build'da sozlanmagan. Taxallus va parol bilan davom eting.",
    this.busy = false,
  });

  final VoidCallback onGoogle;

  /// Null in a properly configured build. Non-null only while the Google
  /// client ID is still a placeholder, so the app can still be opened.
  final VoidCallback? onDevLogin;

  /// The nickname+password form's submit while it is in "Ro'yxatdan o'tish" mode.
  final void Function(String nickname, String password) onRegister;

  /// The nickname+password form's submit while it is in "Kirish" mode.
  final void Function(String nickname, String password) onLogin;

  /// False when Google login is unavailable on this platform or unconfigured.
  final bool showGoogle;

  /// Optional platform-native button, used by the browser's Google flow.
  final Widget? googleButton;

  /// Explains why Google sign-in is unavailable on this build.
  final String googleUnavailableMessage;

  /// True while a login request is in flight — every button here must not fire twice.
  final bool busy;

  @override
  State<Onboarding1Screen> createState() => _Onboarding1ScreenState();
}

class _Onboarding1ScreenState extends State<Onboarding1Screen> {
  bool _registering = false;
  String _nickname = '';
  String _password = '';
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !widget.busy && _nickname.trim().isNotEmpty && _password.isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    final nickname = _nickname.trim();
    if (_registering) {
      widget.onRegister(nickname, _password);
    } else {
      widget.onLogin(nickname, _password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.1,
          colors: [WBColors.accentA(.16), Colors.transparent],
          stops: const [0, .7],
        ),
      ),
      // The password form's keyboard shrinks the space this screen is given —
      // see Onboarding2Screen for the same fix on the same problem. Before the
      // form existed nothing here ever asked for the keyboard, so the fixed
      // Column never had to scroll.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
      child: Column(
        children: [
          const Spacer(),
          GlowOrb(
            glowColor: WBColors.accent,
            borderRadius: BorderRadius.circular(34),
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(34)),
              alignment: Alignment.center,
              child: Text('W', style: WBText.mono(size: 46, weight: FontWeight.w700, color: WBColors.accentInk)),
            ),
          ),
          const SizedBox(height: 26),
          Text('WORD\nBATTLE',
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 36, weight: FontWeight.w700, height: 1.05, letterSpacing: -.02)),
          const SizedBox(height: 12),
          // The subtitle's 250dp measure, written as an inset off the 360dp
          // content width rather than as the usual maxWidth clamp: the
          // IntrinsicHeight above measures this column at its full width, and a
          // clamp is invisible to that measurement — the subtitle would be
          // measured at the two lines it takes at 360dp and then drawn as the
          // three it takes at 250dp. Padding is the one inset it subtracts.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 55),
            child: Text(
              "Ingliz so'zlari bilan jonli jang. Raqibingdan tez o'yla, zanjirni uzma.",
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 15, height: 1.5, color: WBColors.textA(.6)),
            ),
          ),
          // 26px, the outer column's gap — not the 12px gap that sits
          // between the title and its subtitle inside the text group.
          const SizedBox(height: 26),
          Wrap(
            spacing: 8,
            children: [
              _Pill(text: '1v1 REAL-TIME'),
              _Pill(text: 'GLICKO-2'),
            ],
          ),
          const Spacer(),
          // A Spacer has no intrinsic height, so the IntrinsicHeight above
          // measures this column as if the two of them were not there — with
          // the keyboard open there is nothing left for them to take and they
          // collapse, leaving the pills sitting on the first field's border.
          // The outer column's 26px gap, as a floor under the one that closes.
          const SizedBox(height: 26),
          Column(
            children: [
              _passwordForm(),
              if (!widget.showGoogle) ...[
                const SizedBox(height: 12),
                Text(
                  widget.googleUnavailableMessage,
                  textAlign: TextAlign.center,
                  style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)),
                ),
              ],
              if (widget.showGoogle) ...[
                const SizedBox(height: 22),
                _divider(),
                const SizedBox(height: 18),
                widget.googleButton ?? _nativeGoogleButton(),
                const SizedBox(height: 14),
                Text('Tezkor kirish — Google orqali bitta bosishda',
                    textAlign: TextAlign.center, style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5))),
              ],
              if (widget.onDevLogin != null) ...[
                const SizedBox(height: 12),
                Pressable(
                  onTap: widget.busy ? null : widget.onDevLogin,
                  pressScale: .96,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text('Dev login',
                        style: WBText.mono(
                          size: 11,
                          weight: FontWeight.w500,
                          color: WBColors.textA(.38),
                          letterSpacing: .12,
                        )),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: WBColors.whiteA(.08))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('yoki', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.4))),
        ),
        Expanded(child: Container(height: 1, color: WBColors.whiteA(.08))),
      ],
    );
  }

  /// The native Google button. Browsers use Google's rendered button
  /// through [widget.googleButton], as required by the web sign-in plugin.
  Widget _nativeGoogleButton() {
    return Pressable(
      onTap: widget.busy ? null : widget.onGoogle,
      pressScale: .98,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: _googleSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _googleStroke),
          boxShadow: [BoxShadow(color: WBColors.whiteA(.13), blurRadius: 34, offset: const Offset(0, 14))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.busy)
              SpinnerRing(
                size: 22,
                trackColor: _googleInk.withValues(alpha: .2),
                activeColor: _googleInk,
                strokeWidth: 2.5,
              )
            else
              const GoogleLogo(size: 20),
            const SizedBox(width: 10),
            Text(
              widget.busy ? 'Kirilmoqda…' : 'Google orqali kirish',
              style: WBText.grotesk(size: 17, weight: FontWeight.w600, color: _googleInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordForm() {
    final enabled = _canSubmit;
    return Column(
      children: [
        _field(
          label: 'TAXALLUS',
          hint: 'masalan, jasur_07',
          value: _nickname,
          onChanged: (v) => setState(() => _nickname = v),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 10),
        _field(
          label: 'PAROL',
          hint: _registering ? "kamida 6 ta belgi, harf va raqam" : 'parolingiz',
          value: _password,
          onChanged: (v) => setState(() => _password = v),
          obscureText: true,
          focusNode: _passwordFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        Pressable(
          onTap: enabled ? _submit : null,
          pressScale: .98,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: WBColors.whiteA(.05),
              border: Border.all(color: enabled ? WBColors.accentA(.35) : WBColors.whiteA(.09)),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              _registering ? "Ro'yxatdan o'tish" : 'Kirish',
              style: WBText.grotesk(size: 15, weight: FontWeight.w600, color: enabled ? WBColors.accent : WBColors.textA(.3)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: widget.busy ? null : () => setState(() => _registering = !_registering),
          child: Text(
            _registering ? 'Akkountingiz bormi? Kirish' : "Akkountingiz yo'qmi? Ro'yxatdan o'tish",
            style: WBText.grotesk(size: 12.5, weight: FontWeight.w500, color: WBColors.textA(.55)),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
    bool obscureText = false,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.045),
        border: Border.all(color: WBColors.whiteA(.1)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.4), letterSpacing: .14)),
          const SizedBox(height: 6),
          SyncedTextField(
            value: value,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            focusNode: focusNode,
            obscureText: obscureText,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: textInputAction,
            maxLength: obscureText ? 72 : 16,
            style: WBText.grotesk(size: 16, weight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: WBText.grotesk(size: 16, weight: FontWeight.w600, color: WBColors.textA(.3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: WBColors.whiteA(.05),
        border: Border.all(color: WBColors.whiteA(.09)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: WBText.mono(size: 11, weight: FontWeight.w500, color: WBColors.textA(.65))),
    );
  }
}
