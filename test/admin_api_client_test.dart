import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:word_battle/admin/admin_api_client.dart';
import 'package:word_battle/api/api_exception.dart';

/// The panel's client, where the two answers that mean something other than
/// "this call failed" are decided.
///
/// A `401` ends the session. A `403` is the account not being an admin — except
/// when it is `account_banned`, which arrives with the same status from a
/// different door and means something else entirely. Getting those two mixed up
/// would either show a banned player a "you are not an admin" screen or hand a
/// non-admin a retry loop, so both are pinned here.
void main() {
  AdminApiClient clientReturning(int status, Object? body) => AdminApiClient(
        httpClient: MockClient((request) async => http.Response(
              body == null ? '' : jsonEncode(body),
              status,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      )..token = 'admin-token';

  Map<String, dynamic> userRow({
    int id = 7,
    String? nickname = 'umida_plays',
    bool banned = false,
    bool deleted = false,
  }) =>
      {
        'id': id,
        'nickname': nickname,
        'displayName': 'Umida',
        'city': 'Toshkent',
        'rating': 1310,
        'battles': 40,
        'wins': 23,
        'admin': false,
        'banned': banned,
        'bannedAt': banned ? '2026-08-11T09:00:00Z' : null,
        'deleted': deleted,
        'createdAt': '2026-07-01T08:00:00Z',
        'lastSeenAt': '2026-08-10T20:15:00Z',
      };

  group('the role check', () {
    test('a 403 from an admin route is the account not being an admin', () async {
      final api = clientReturning(403, {'code': 'forbidden', 'message': "Ruxsat yo'q"});

      await expectLater(
        api.metrics(),
        throwsA(isA<ApiException>()
            .having((e) => e.isForbidden, 'isForbidden', isTrue)
            .having((e) => e.isRoleRefusal, 'isRoleRefusal', isTrue)),
      );
    });

    test('a banned account is a 403 that is not a role refusal', () async {
      // Same status, different door: `/auth/google` refuses the sign-in itself.
      // Treating this as a role refusal would tell a banned player they are
      // merely not an admin, and would leave them on a screen whose only advice
      // is to ask for a role they were never missing.
      final api = clientReturning(403, {'code': 'account_banned', 'message': 'Akkaunt bloklangan'});

      await expectLater(
        api.loginWithGoogle('id-token'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'account_banned')
            .having((e) => e.isForbidden, 'isForbidden', isTrue)
            .having((e) => e.isRoleRefusal, 'isRoleRefusal', isFalse)),
      );
    });

    test('a 401 is the end of the session, not a permission problem', () async {
      final api = clientReturning(401, {'code': 'unauthorized', 'message': 'Token eskirgan'});

      await expectLater(
        api.users(),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
            .having((e) => e.isRoleRefusal, 'isRoleRefusal', isFalse)),
      );
    });
  });

  group('the user list', () {
    test('a page is read whole, paging included', () async {
      final api = clientReturning(200, {
        'items': [userRow(), userRow(id: 8, nickname: null, banned: true)],
        'page': 1,
        'size': 20,
        'total': 42,
        'totalPages': 3,
      });

      final page = await api.users(page: 1);

      expect(page.items, hasLength(2));
      expect(page.total, 42);
      expect(page.hasPrevious, isTrue);
      expect(page.hasNext, isTrue);
      expect(page.items.first.nickname, 'umida_plays');
      expect(page.items.first.wins, 23);
      expect(page.items.last.banned, isTrue);
      expect(page.items.last.bannedAt, isNotNull);
      // No nickname and no display name would leave nothing to print; the id is
      // what the server falls back to as well.
      expect(page.items.last.label, 'Umida');
    });

    test('the search text and the page go in the query, and a blank one is left out', () async {
      final seen = <Uri>[];
      final api = AdminApiClient(
        httpClient: MockClient((request) async {
          seen.add(request.url);
          return http.Response(jsonEncode({'items': [], 'page': 0, 'size': 20, 'total': 0, 'totalPages': 0}), 200);
        }),
      )..token = 'admin-token';

      await api.users(query: '  umida  ', page: 2, size: 50);
      await api.users();

      expect(seen.first.queryParameters, {'q': 'umida', 'page': '2', 'size': '50'});
      expect(seen.last.queryParameters.containsKey('q'), isFalse);
    });

    test('the token is a bearer header and never reaches the URL', () async {
      String? auth;
      Uri? url;
      final api = AdminApiClient(
        httpClient: MockClient((request) async {
          auth = request.headers['Authorization'];
          url = request.url;
          return http.Response(jsonEncode({'items': [], 'page': 0, 'size': 20, 'total': 0, 'totalPages': 0}), 200);
        }),
      )..token = 'secret-token';

      await api.users();

      expect(auth, 'Bearer secret-token');
      expect(url.toString(), isNot(contains('secret-token')));
    });
  });

  group('what a changed shape costs', () {
    test('a date the client cannot read costs the cell, not the row', () async {
      // The ordinary cost of a rolling deploy. The row is what the admin came
      // for; a creation date they cannot read is a dash in one column.
      final api = clientReturning(200, {
        'items': [userRow()..['createdAt'] = 'yesterday'],
        'page': 0,
        'size': 20,
        'total': 1,
        'totalPages': 1,
      });

      final page = await api.users();

      expect(page.items.single.createdAt, isNull);
      expect(page.items.single.id, 7);
      expect(page.items.single.rating, 1310);
    });

    test('a field the server stopped sending falls back rather than throwing', () async {
      final api = clientReturning(200, {
        'items': [
          {'id': 9, 'nickname': 'sardor'},
        ],
        'page': 0,
      });

      final page = await api.users();

      expect(page.items.single.rating, 0);
      expect(page.items.single.banned, isFalse);
      expect(page.totalPages, 0);
    });
  });

  group('the actions', () {
    test('a ban carries its reason, and no reason is sent as none', () async {
      final bodies = <String?>[];
      final api = AdminApiClient(
        httpClient: MockClient((request) async {
          bodies.add(request.body);
          return http.Response(jsonEncode(userRow(banned: true)), 200);
        }),
      )..token = 'admin-token';

      final banned = await api.ban(7, reason: '  haqoratli taxallus  ');
      await api.ban(7, reason: '   ');

      expect(jsonDecode(bodies.first!), {'reason': 'haqoratli taxallus'});
      expect(jsonDecode(bodies.last!), {'reason': null});
      expect(banned.banned, isTrue);
    });

    test('the row the server answers with is the one that comes back', () async {
      final api = clientReturning(200, userRow(banned: false, nickname: 'ravshan_out'));

      expect((await api.unban(7)).nickname, 'ravshan_out');
    });

    test("a nickname the server refuses keeps its own code, so the screen can say why", () async {
      final api = clientReturning(409, {'code': 'nickname_taken', 'message': 'Bu taxallus band'});

      await expectLater(
        api.rename(7, 'umida'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'nickname_taken')
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.isRoleRefusal, 'isRoleRefusal', isFalse)),
      );
    });
  });

  group('the rest of the panel', () {
    test('the metrics arrive with the ratio the dashboard draws', () async {
      final api = clientReturning(200, {
        'totalUsers': 120,
        'bannedUsers': 3,
        'battlesToday': 18,
        'botBattles': 40,
        'humanBattles': 60,
      });

      final metrics = await api.metrics();

      expect(metrics.totalUsers, 120);
      expect(metrics.totalBattles, 100);
      expect(metrics.botPercent, 40);
    });

    test('an audit row about a nobody still names the admin who acted', () async {
      final api = clientReturning(200, {
        'items': [
          {
            'id': 3,
            'adminUserId': 1,
            'admin': 'feruz_admin',
            'action': 'user_ban',
            'targetUserId': 7,
            'target': 'umida_plays',
            'detail': 'haqoratli taxallus',
            'createdAt': '2026-08-11T09:00:00Z',
          },
          {'id': 4, 'adminUserId': 1, 'admin': 'feruz_admin', 'action': 'user_unban'},
        ],
        'page': 0,
        'size': 50,
        'total': 2,
        'totalPages': 1,
      });

      final page = await api.auditLog();

      expect(page.items.first.actionLabel, 'Bloklandi');
      expect(page.items.first.targetLabel, 'umida_plays');
      expect(page.items.last.targetLabel, '—');
      expect(page.items.last.actionLabel, 'Blok olindi');
    });

    test('a bot duel has no second account, and says so', () async {
      final api = clientReturning(200, {
        'items': [
          {
            'id': 12,
            'playerOneId': 7,
            'playerOne': 'umida_plays',
            'playerTwoId': null,
            'playerTwo': null,
            'botOpponent': true,
            'winnerId': 7,
            'endReason': 'timeout',
            'chainLength': 14,
            'startedAt': '2026-08-11T09:00:00Z',
            'finishedAt': '2026-08-11T09:04:00Z',
          },
        ],
        'page': 0,
        'size': 20,
        'total': 1,
        'totalPages': 1,
      });

      final match = (await api.matches()).items.single;

      expect(match.playerOneLabel, 'umida_plays');
      expect(match.playerTwoLabel, 'BOT');
      expect(match.chainLength, 14);
    });
  });
}
