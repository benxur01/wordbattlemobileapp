/// Where the backend lives. Override at build time:
///
///   flutter run --dart-define=WB_API=http://192.168.1.10:8080
///
/// The default suits a server running on the development machine with
/// `adb reverse tcp:8080 tcp:8080`, which makes the phone's localhost the
/// computer's localhost.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment('WB_API', defaultValue: 'http://localhost:8080');

  /// True when the app is talking to a plaintext server. Fine against a
  /// development machine over `adb reverse`; anywhere else it means the token
  /// and every duel frame cross the network in the clear, so the release build
  /// refuses cleartext outright (see the Android network security config).
  static bool get isCleartext => baseUrl.startsWith('http://');

  /// TODO: paste the **Web** OAuth client ID here — Google Cloud Console →
  /// APIs & Services → Credentials → the "Web application" entry, ending in
  /// `.apps.googleusercontent.com`.
  ///
  /// It must be the web client, not the Android one: Google mints the idToken
  /// for whoever is named here, and the backend only accepts a token addressed
  /// to itself. The Android client still has to exist (with the app's SHA-1
  /// fingerprints registered) for the sign-in sheet to appear at all — it just
  /// never appears in code.
  ///
  /// The same value goes into `wordbattle.google.web-client-id` on the server.
  /// This is the only place the client keeps it; override at build time with
  /// `--dart-define=WB_GOOGLE_CLIENT_ID=...` if you would rather not commit it.
  static const String googleServerClientId = String.fromEnvironment(
    'WB_GOOGLE_CLIENT_ID',
    defaultValue: 'TODO-PASTE-WEB-CLIENT-ID.apps.googleusercontent.com',
  );

  /// False while the placeholder above is still in place, so the app can say
  /// so instead of opening a sign-in sheet that is bound to fail.
  static bool get googleConfigured => !googleServerClientId.startsWith('TODO');

  static Uri rest(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '/api$path',
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );
  }

  /// The socket endpoint. The token is sent as an `Authorization` header —
  /// see `socket_connect.dart` — so it stays out of URLs and access logs.
  static Uri socket() {
    final base = Uri.parse(baseUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }

  /// Web only: browsers cannot set headers on a WebSocket upgrade.
  static Uri socketWithToken(String token) => socket().replace(queryParameters: {'token': token});
}
