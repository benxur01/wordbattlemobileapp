/// The sign-in button, drawn the only way each platform allows.
///
/// On a phone or a desktop the app asks Google for an idToken directly, exactly
/// as the game's onboarding screen does — see `api/google_auth.dart`.
///
/// A browser cannot do that at all: `google_sign_in_web` does not implement
/// `authenticate()`, and the credential arrives instead through a button Google
/// itself renders and an event stream. Same idToken at the end of it, same
/// `/auth/google` call, so the difference stops at this file.
library;

export 'admin_google_button_web.dart' if (dart.library.io) 'admin_google_button_io.dart';
