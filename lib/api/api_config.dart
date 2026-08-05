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

  static Uri rest(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '/api$path',
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );
  }

  static Uri socket(String token) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {'token': token},
    );
  }
}
