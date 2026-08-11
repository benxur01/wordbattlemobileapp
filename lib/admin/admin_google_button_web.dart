import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../theme.dart';

/// The browser: Google renders the button and the credential arrives through
/// the event stream, because `google_sign_in_web` implements no `authenticate()`
/// for the app to call. This is the documented web flow and the only one there
/// is — the game's [GoogleAuth] would throw `google_unsupported` here.
///
/// The client id is passed as `clientId`, not `serverClientId`, which the web
/// plugin refuses outright. It is the same Web OAuth client either way — the one
/// the backend checks the token's `aud` against — so the value is unchanged; only
/// the parameter it goes in differs.
class AdminGoogleButton extends StatefulWidget {
  const AdminGoogleButton({
    super.key,
    required this.onIdToken,
    required this.onError,
    this.enabled = true,
  });

  final void Function(String idToken) onIdToken;

  final void Function(ApiException error) onError;

  final bool enabled;

  @override
  State<AdminGoogleButton> createState() => _AdminGoogleButtonState();
}

/// Sign-in is initialised once per page load, per the plugin's contract, and
/// this is what holds that promise across a widget that mounts more than once —
/// leaving and returning to the login screen must not initialise it twice.
Future<void>? _initialization;

/// Forgets the Google account in this browser, so "use another account" is
/// offered the chooser rather than silently handed the last one back.
/// Best-effort: a failure here must not stop the panel dropping its session.
Future<void> adminGoogleSignOut() async {
  if (_initialization == null) return;
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // Nothing to do — our own session is being dropped regardless.
  }
}

class _AdminGoogleButtonState extends State<AdminGoogleButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool _ready = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!ApiConfig.googleConfigured) {
      setState(() => _failure = "Google kirish sozlanmagan — ApiConfig.googleServerClientId ni to'ldiring");
      return;
    }
    try {
      _initialization ??= GoogleSignIn.instance.initialize(clientId: ApiConfig.googleServerClientId);
      await _initialization;
      if (!mounted) return;
      // Subscribed after initialize, since that is what wires the platform's
      // events into this stream in the first place.
      _events = GoogleSignIn.instance.authenticationEvents.listen(_onEvent, onError: _onStreamError);
      setState(() => _ready = true);
    } catch (e) {
      // A blocked script, a client id the console does not know: still a login
      // failure, and one the screen has to say out loud rather than leave as a
      // button that never appears.
      if (mounted) setState(() => _failure = "Google kirishni yuklab bo'lmadi ($e)");
    }
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;
    final idToken = event.user.authentication.idToken;
    if (idToken == null) {
      widget.onError(ApiException('google_no_id_token', "Google token bermadi — qayta urinib ko'ring"));
      return;
    }
    widget.onIdToken(idToken);
  }

  void _onStreamError(Object error) {
    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) return;
      widget.onError(ApiException('google_${error.code.name}', "Google orqali kirib bo'lmadi"));
      return;
    }
    widget.onError(ApiException('google_failed', "Google orqali kirib bo'lmadi"));
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Text(failure, style: WBText.grotesk(size: 13, color: WBColors.redSoft));
    }
    if (!_ready) {
      return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    // The rendered button is Google's own and cannot be disabled from here, so
    // while a sign-in is being exchanged it is covered rather than left live.
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : .5,
        child: web.renderButton(
          configuration: web.GSIButtonConfiguration(
            theme: web.GSIButtonTheme.filledBlack,
            size: web.GSIButtonSize.large,
            shape: web.GSIButtonShape.rectangular,
            text: web.GSIButtonText.signinWith,
          ),
        ),
      ),
    );
  }
}
