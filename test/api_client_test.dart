import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:word_battle/api/api_client.dart';
import 'package:word_battle/api/api_config.dart';
import 'package:word_battle/api/api_exception.dart';

/// The client is where a server error becomes something the UI can act on, and
/// where the difference between "this call failed" and "this session is over"
/// is decided. Both were previously untested, and the 401 path in particular
/// was wired up nowhere at all.
void main() {
  ApiClient clientReturning(int status, Object? body) => ApiClient(
        httpClient: MockClient((request) async => http.Response(
              body == null ? '' : jsonEncode(body),
              status,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

  test('a 401 is marked as the end of the session', () async {
    final api = clientReturning(401, {'code': 'unauthorized', 'message': 'Token eskirgan'})..token = 'stale';

    await expectLater(
      api.me(),
      throwsA(isA<ApiException>()
          .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
          .having((e) => e.message, 'message', 'Token eskirgan')),
    );
  });

  test('a deleted account reports user_not_found rather than a generic failure', () async {
    final api = clientReturning(404, {'code': 'user_not_found', 'message': 'Foydalanuvchi topilmadi'})..token = 'x';

    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'user_not_found')),
    );
  });

  test("the server's own error code survives, so screens can branch on it", () async {
    final api = clientReturning(409, {'code': 'nickname_taken', 'message': 'Bu taxallus band'})..token = 'x';

    await expectLater(
      api.claimNickname('malika'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'nickname_taken')
          .having((e) => e.statusCode, 'statusCode', 409)),
    );
  });

  test('a non-JSON error body still produces a usable exception', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async => http.Response('<html>502</html>', 502)),
    )..token = 'x';

    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'http_502')),
    );
  });

  test('a transport failure is reported as a network error, not swallowed', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async => throw const SocketExceptionStub()),
    )..token = 'x';

    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
    );
  });

  test('the token is sent as a bearer header and never in the URL', () async {
    String? seenAuth;
    Uri? seenUri;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        seenAuth = request.headers['Authorization'];
        seenUri = request.url;
        return http.Response(jsonEncode({'id': 1, 'initial': 'A', 'rating': 1200, 'streakDays': 0}), 200,
            headers: {'content-type': 'application/json'});
      }),
    )..token = 'secret-token';

    await api.me();

    expect(seenAuth, 'Bearer secret-token');
    expect(seenUri.toString(), isNot(contains('secret-token')));
  });

  test('the socket URL carries no token: it goes in a header instead', () {
    final uri = ApiConfig.socket();

    expect(uri.path, '/ws');
    expect(uri.queryParameters, isEmpty);
    expect(uri.scheme, anyOf('ws', 'wss'));
  });
}

/// Stands in for a dart:io SocketException without importing dart:io, so the
/// test stays runnable everywhere.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
