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

  /// The **Web** OAuth client, which stands for the backend rather than for any
  /// website — Google's name for "a client that runs on a server". Sign-In is
  /// asked to mint the idToken for whoever is named here, and the backend
  /// accepts only a token addressed to itself, so this value and the server's
  /// `wordbattle.google.web-client-id` have to be the same string.
  ///
  /// Not the Android client id: that one exists so the sign-in sheet trusts the
  /// app at all (it is matched by package name and signing SHA-1), and it never
  /// appears in code. Putting it here instead yields a token whose `aud` names
  /// the phone app, which the server refuses.
  ///
  /// Committed on purpose. A client id is not a secret — it ships inside every
  /// build and is visible in the traffic — and keeping it here means a plain
  /// `flutter run` works. `--dart-define=WB_GOOGLE_CLIENT_ID=...` still wins,
  /// which is how a second Google project (staging, a fork) is pointed at.
  static const String googleServerClientId = String.fromEnvironment(
    'WB_GOOGLE_CLIENT_ID',
    defaultValue: '238943789457-tgpjf2jamd6r8m0ottqn0ik9ce76gpe2.apps.googleusercontent.com',
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
