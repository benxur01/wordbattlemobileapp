import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/api_exception.dart';
import '../api/google_auth.dart';
import '../theme.dart';
import '../widgets/google_logo.dart';

/// Phone and desktop: the platform can run the account sheet itself, so this is
/// the game's own [GoogleAuth] behind an ordinary button.
///
/// One [GoogleAuth] for the lifetime of the widget rather than one per tap: it
/// initialises the plugin exactly once per launch, which is the plugin's
/// contract, and a fresh object every tap would break that.
class AdminGoogleButton extends StatefulWidget {
  const AdminGoogleButton({
    super.key,
    required this.onIdToken,
    required this.onError,
    this.enabled = true,
  });

  /// Called with a Google idToken the backend can verify. Never called when the
  /// account sheet is simply dismissed — a cancel is not a failure.
  final void Function(String idToken) onIdToken;

  final void Function(ApiException error) onError;

  final bool enabled;

  @override
  State<AdminGoogleButton> createState() => _AdminGoogleButtonState();
}

/// Whether a sign-in has actually gone through on this page. Signing out is
/// otherwise the first call made to a plugin nothing has initialised, which is
/// an error rather than a no-op.
bool _signedIn = false;

/// Forgets the Google account on this device, so "use another account" shows
/// the picker instead of silently returning whoever was last used. Best-effort:
/// a failure here must not stop the panel from dropping its own session.
///
/// Straight at the singleton rather than through [GoogleAuth], whose own
/// initialised-flag belongs to the instance the button holds; [_signedIn] is
/// what says the plugin has been initialised at all.
Future<void> adminGoogleSignOut() async {
  if (!_signedIn) return;
  _signedIn = false;
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // Nothing to do — our own session is being dropped regardless.
  }
}

class _AdminGoogleButtonState extends State<AdminGoogleButton> {
  final GoogleAuth _google = GoogleAuth();
  bool _running = false;

  Future<void> _signIn() async {
    if (_running || !widget.enabled) return;
    setState(() => _running = true);
    try {
      final idToken = await _google.signIn();
      if (idToken != null) {
        _signedIn = true;
        widget.onIdToken(idToken);
      }
    } on ApiException catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_running;
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: enabled ? _signIn : null,
        icon: _running
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const GoogleLogo(size: 18),
        label: Text('Google orqali kirish', style: WBText.grotesk(size: 14, weight: FontWeight.w600)),
        style: FilledButton.styleFrom(
          backgroundColor: WBColors.text,
          foregroundColor: WBColors.bg,
          disabledBackgroundColor: WBColors.textA(.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
