import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_google_button.dart';
import 'admin_widgets.dart';

/// What the login screen says about a failed sign-in.
///
/// The server's own message is used for almost everything, since it is written
/// for the person reading it. `account_banned` is the exception worth naming:
/// it is refused at `/auth/google` itself with a `403`, the same status a
/// non-admin gets from the panel's routes, and the two mean completely
/// different things. A banned account never got in at all — so there is no
/// session to end and no role to be missing, and sending it to the "not an
/// admin" screen would be telling it to go and ask for something that would not
/// help. See [AdminApiException.isRoleRefusal], which excludes this code for the
/// same reason rather than testing the status alone.
String adminLoginMessage(ApiException e) => switch (e.code) {
      'account_banned' => 'Bu akkaunt bloklangan — u bilan kirib bo‘lmaydi.',
      _ => e.message,
    };

/// The way in. One button, and the same Google account the game itself uses —
/// the panel has no password of its own to lose.
///
/// Nothing here asks whether the account is an admin. Signing in and being
/// allowed in are two separate questions, and the second one is only ever
/// answered by the server: the panel calls an admin route straight afterwards
/// and shows [AdminDeniedScreen] if it comes back `403`.
class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({
    super.key,
    required this.onIdToken,
    required this.onError,
    this.busy = false,
    this.notice,
  });

  final void Function(String idToken) onIdToken;
  final void Function(ApiException error) onError;
  final bool busy;

  /// Why the panel is showing this screen rather than the panel: an expired
  /// session, a login that was refused. Never empty just because the last
  /// attempt failed silently — a failure that is not shown is a failure the
  /// admin retries forever.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'WORD BATTLE',
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 26, weight: FontWeight.w700, letterSpacing: .08),
              ),
              const SizedBox(height: 4),
              Text(
                'ADMIN PANEL',
                textAlign: TextAlign.center,
                style: WBText.mono(size: 12, weight: FontWeight.w600, color: WBColors.amber, letterSpacing: .3),
              ),
              const SizedBox(height: 28),
              if (notice != null) ...[
                AdminBanner(message: notice!),
                const SizedBox(height: 16),
              ],
              AdminGoogleButton(onIdToken: onIdToken, onError: onError, enabled: !busy),
              if (busy) ...[
                const SizedBox(height: 16),
                const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              ],
              const SizedBox(height: 24),
              Text(
                'Server: ${ApiConfig.baseUrl}',
                textAlign: TextAlign.center,
                style: WBText.mono(size: 11, color: WBColors.textA(.35)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed in, and not allowed in. A separate screen rather than a banner on the
/// login one, because signing in again would only produce the same answer: the
/// token is perfectly good, the account simply is not an admin.
///
/// The role is granted by `ADMIN_BOOTSTRAP_USER_ID` on the server and by nothing
/// else — deliberately, since a panel that can create admins is a panel one
/// compromised account keeps forever — so the way out of this screen is not in
/// this app.
class AdminDeniedScreen extends StatelessWidget {
  const AdminDeniedScreen({super.key, required this.who, required this.onSignOut});

  /// The account that was refused, so an admin who has two Google accounts can
  /// see at a glance that they used the wrong one.
  final String who;

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 40, color: WBColors.red),
              const SizedBox(height: 16),
              Text(
                "Ruxsat yo'q",
                style: WBText.grotesk(size: 22, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '$who akkaunti admin emas. Bu panel faqat admin roli berilgan '
                'akkauntlar uchun ochiq.',
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 14, color: WBColors.textA(.7)),
              ),
              const SizedBox(height: 6),
              Text(
                'Rol serverda ADMIN_BOOTSTRAP_USER_ID orqali beriladi — panelning o‘zi hech kimga admin bera olmaydi.',
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 12, color: WBColors.textA(.4)),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Boshqa akkaunt bilan kirish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
