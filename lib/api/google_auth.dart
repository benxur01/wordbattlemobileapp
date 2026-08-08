import 'package:google_sign_in/google_sign_in.dart';

import 'api_config.dart';
import 'api_exception.dart';

/// Google Sign-In reduced to what the app actually needs: an idToken the
/// backend can verify, or an [ApiException] the banner already knows how to
/// show — the same failure type every other call in `api/` throws.
///
/// The token is minted for [ApiConfig.googleServerClientId], the **Web** OAuth
/// client. Passing the Android client id instead yields a token the server
/// refuses, because its `aud` names the phone app rather than the backend.
class GoogleAuth {
  bool _initialized = false;

  /// Runs the account sheet and returns the idToken, or null when the player
  /// dismissed it — a cancel is not an error worth a banner.
  Future<String?> signIn() async {
    if (!ApiConfig.googleConfigured) {
      throw ApiException('google_not_configured',
          "Google kirish sozlanmagan — ApiConfig.googleServerClientId ni to'ldiring");
    }

    try {
      if (!_initialized) {
        // Exactly once per launch, per the plugin's contract.
        await GoogleSignIn.instance.initialize(serverClientId: ApiConfig.googleServerClientId);
        _initialized = true;
      }
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw ApiException('google_unsupported', "Bu platformada Google kirish mavjud emas");
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw ApiException('google_no_id_token', "Google token bermadi — qayta urinib ko'ring");
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ApiException('google_${e.code.name}', _messageFor(e.code));
    } on ApiException {
      rethrow;
    } catch (_) {
      // A missing plugin or a broken platform channel: still a login failure,
      // so the caller can show it and reset — never a button left spinning.
      throw ApiException('google_failed', "Google orqali kirib bo'lmadi");
    }
  }

  /// Forgets the Google account on this device, so the next sign-in shows the
  /// account picker instead of silently returning whoever was last used.
  /// Best-effort: a failure here must not stop the app from signing out.
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to do — our own session is being dropped regardless.
    }
  }

  static String _messageFor(GoogleSignInExceptionCode code) => switch (code) {
        // Android reports a bad SHA-1 or client id this way — worth naming,
        // because the fix is in the console rather than in the app.
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          "Google sozlamalari noto'g'ri — client ID va SHA-1 ni tekshiring",
        GoogleSignInExceptionCode.uiUnavailable => "Google oynasini ochib bo'lmadi",
        _ => "Google orqali kirib bo'lmadi",
      };
}
