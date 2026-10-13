import 'package:flutter/foundation.dart';

/// Where the backend lives. Override at build time:
///
///   flutter run --dart-define=WB_API=http://192.168.1.10:8080
///
/// The default suits a server running on the development machine with
/// `adb reverse tcp:8080 tcp:8080`, which makes the phone's localhost the
/// computer's localhost. A release build has to be given an `https://` one;
/// `RestTransport` refuses to make any call on a cleartext address in release:
///
///   flutter build appbundle --release --dart-define=WB_API=https://<domain>
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment('WB_API', defaultValue: 'http://localhost:8080');

  /// The host shared tournament links point at. There is no production domain
  /// yet, so the default is a placeholder, and a release build is given the
  /// real one with `--dart-define=WB_LINK_HOST=<domain>`.
  ///
  /// It has to be the same string as the `wbLinkHost` Gradle property the
  /// Android manifest's App Links filter is built from (see
  /// android/app/build.gradle.kts): otherwise the app shares links that it
  /// does not open itself. The server at that host answers
  /// `/.well-known/assetlinks.json` from its `ASSETLINKS_SHA256`.
  static const String linkHost = String.fromEnvironment('WB_LINK_HOST', defaultValue: 'wordbattle.example.uz');

  /// The address a tournament is shared as — what `app_root.dart` opens the
  /// bracket from when Android hands the app one of these links.
  static String tournamentLink(int tournamentId) => 'https://$linkHost/t/$tournamentId';

  /// The privacy policy and the terms of use: pages the server itself serves,
  /// outside `/api`, so a correction reaches every installed build at once and
  /// the stores can be given the same two addresses.
  static Uri get privacyPolicyUrl => Uri.parse(baseUrl).replace(path: '/privacy');

  static Uri get termsUrl => Uri.parse(baseUrl).replace(path: '/terms');

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

  /// Empty and placeholder client IDs both mean the provider is unavailable;
  /// don't show a button that can only fail during plugin initialization.
  static bool get googleConfigured {
    final clientId = googleServerClientId.trim();
    return clientId.isNotEmpty && !clientId.startsWith('TODO');
  }

  /// Google sign-in is currently disabled on iOS because Sign in with Apple
  /// has not been implemented yet. If Google is offered on iOS, Apple requires
  /// an equivalent sign-in option. Nickname/password login remains available.
  /// Google Sign-In's supported app platforms are Android, macOS and web.
  /// Nickname/password login remains available on the other platforms.
  static bool get googleSupportedOnPlatform {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.macOS => true,
      TargetPlatform.iOS || TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.fuchsia => false,
    };
  }

  static bool get googleConfiguredForPlatform =>
      googleConfigured && googleSupportedOnPlatform && (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);

  static String get googleUnavailableMessage {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return "iOS'da Google kirish Apple bilan teng kirish usuli qo'shilguncha o'chirilgan. "
          "Taxallus va parol bilan davom eting.";
    }
    if (!googleSupportedOnPlatform) {
      return "Google kirish bu platformada mavjud emas. Taxallus va parol bilan davom eting.";
    }
    return "Google kirish bu build'da sozlanmagan. Taxallus va parol bilan davom eting.";
  }

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
