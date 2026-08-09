import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_battle/api/api_client.dart';
import 'package:word_battle/api/api_exception.dart';
import 'package:word_battle/api/session.dart';

/// Restoring a saved login is the one place the app decides, before the player
/// can say anything, whether they are still signed in. It used to answer that
/// question with a bare `catch`, so every failure meant the same thing: the
/// token was deleted. Opening the app on a train, or a second before the server
/// finished restarting, therefore signed the player out for good.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Session sessionWith(http.Client client) => Session(ApiClient(httpClient: client));

  Session sessionReturning(int status, Object? body) => sessionWith(
        MockClient((request) async => http.Response(
              body == null ? '' : jsonEncode(body),
              status,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

  Future<String?> storedToken() async => (await SharedPreferences.getInstance()).getString('wb_token');

  setUp(() => SharedPreferences.setMockInitialValues({'wb_token': 'saved-token'}));

  test('an unreachable server keeps the token and reports the failure', () async {
    final session = sessionWith(MockClient((_) => Future.error(const SocketException())));

    await expectLater(session.restore(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')));
    expect(await storedToken(), 'saved-token', reason: 'an offline launch must not sign the player out');
    expect(session.token, 'saved-token', reason: 'the client still needs it for the retry');
  });

  test('a server error keeps the token too — it says nothing about the session', () async {
    final session = sessionReturning(500, {'code': 'server_error', 'message': 'Server xatosi'});

    await expectLater(session.restore(), throwsA(isA<ApiException>()));
    expect(await storedToken(), 'saved-token');
  });

  test('a rejected token is forgotten', () async {
    final session = sessionReturning(401, {'code': 'unauthorized', 'message': 'Token eskirgan'});

    expect(await session.restore(), isFalse);
    expect(await storedToken(), isNull);
    expect(session.token, isNull);
  });

  test('a deleted account is forgotten as well', () async {
    final session = sessionReturning(404, {'code': 'user_not_found', 'message': 'Topilmadi'});

    expect(await session.restore(), isFalse);
    expect(await storedToken(), isNull);
  });

  test('an accepted token restores the player', () async {
    final session = sessionReturning(200, {
      'id': 7,
      'nickname': 'benxur',
      'displayName': 'Benxur',
      'initial': 'B',
      'city': null,
      'rating': 1200,
      'streakDays': 0,
    });

    expect(await session.restore(), isTrue);
    expect(session.user?.nickname, 'benxur');
    expect(await storedToken(), 'saved-token');
  });

  test('no saved token is not a failure', () async {
    SharedPreferences.setMockInitialValues({});
    final session = sessionReturning(200, null);

    expect(await session.restore(), isFalse);
  });
}

/// Stands in for the dart:io exception the http client throws with no network;
/// the client turns anything it cannot send into `ApiException.network`.
class SocketException implements Exception {
  const SocketException();
}
