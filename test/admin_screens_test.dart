import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:word_battle/admin/admin_api_client.dart';
import 'package:word_battle/admin/admin_login_screen.dart';
import 'package:word_battle/admin/admin_root.dart';
import 'package:word_battle/admin/admin_users_screen.dart';
import 'package:word_battle/api/api_exception.dart';

/// The panel's screens, held to the one promise the whole thing rests on:
/// nothing fails quietly.
///
/// A refused role, a dead token, a server that is down and a nickname that is
/// taken all end up somewhere the admin can read. The failure mode being
/// guarded against is the opposite — a spinner that never resolves, or a ban
/// button that appears to do nothing.
void main() {
  /// Never `pumpAndSettle`: these screens show a `CircularProgressIndicator`
  /// while they load, which schedules frames forever and would time it out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void useDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Map<String, dynamic> userRow({int id = 7, bool banned = false, String? nickname = 'umida_plays'}) => {
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
        'deleted': false,
        'createdAt': '2026-07-01T08:00:00Z',
        'lastSeenAt': '2026-08-10T20:15:00Z',
      };

  Map<String, dynamic> onePage(List<Map<String, dynamic>> items) => {
        'items': items,
        'page': 0,
        'size': 20,
        'total': items.length,
        'totalPages': 1,
      };

  Widget hosting(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('getting into the panel', () {
    testWidgets('with no saved token the panel asks to sign in', (tester) async {
      useDesktopWindow(tester);
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(MaterialApp(
        home: AdminRoot(api: AdminApiClient(httpClient: MockClient((_) async => json({})))),
      ));
      await settle(tester);

      expect(find.text('ADMIN PANEL'), findsOneWidget);
      expect(find.text('Google orqali kirish'), findsOneWidget);
    });

    testWidgets('a signed-in account that is not an admin is told so, not left guessing', (tester) async {
      useDesktopWindow(tester);
      FlutterSecureStorage.setMockInitialValues({'wb_admin_token': 'a-real-token'});

      // The token is perfectly good — `/users/me` answers it — and the admin
      // routes still refuse it. That is the whole case this screen exists for.
      final api = AdminApiClient(httpClient: MockClient((request) async {
        if (request.url.path == '/api/users/me') {
          return json({'id': 5, 'nickname': 'oddiy', 'initial': 'O', 'rating': 1200, 'streakDays': 0});
        }
        return json({'code': 'forbidden', 'message': "Ruxsat yo'q"}, 403);
      }));

      await tester.pumpWidget(MaterialApp(home: AdminRoot(api: api)));
      await settle(tester);

      expect(find.text("Ruxsat yo'q"), findsOneWidget);
      expect(find.textContaining('oddiy'), findsOneWidget);
      // Signing in again would produce the same answer, so the way out is to
      // use a different account rather than to retry this one.
      expect(find.text('Boshqa akkaunt bilan kirish'), findsOneWidget);
    });

    testWidgets('a server that cannot be reached keeps the token and offers a retry', (tester) async {
      useDesktopWindow(tester);
      FlutterSecureStorage.setMockInitialValues({'wb_admin_token': 'a-real-token'});

      // The rule the game's own session restore follows: a network that is down
      // says nothing about whether the token is good, so forgetting it here
      // would log the admin out for a lift or a tunnel.
      final api = AdminApiClient(httpClient: MockClient((_) async => throw const _Offline()));

      await tester.pumpWidget(MaterialApp(home: AdminRoot(api: api)));
      await settle(tester);

      expect(find.text('Qayta urinish'), findsOneWidget);
      expect(find.text('ADMIN PANEL'), findsNothing);
      expect(await const FlutterSecureStorage().read(key: 'wb_admin_token'), 'a-real-token');
    });
  });

  group('what the login screen says when it refuses', () {
    test('a banned account is named as banned, not left to the role screen', () {
      // The server refuses this one at `/auth/google` with the same `403` a
      // non-admin gets from the panel's own routes. Treating them alike would
      // put a banned player on a screen telling them to ask for an admin role
      // they never lacked, and there is nothing in this app that would help.
      final message = adminLoginMessage(ApiException('account_banned', 'Akkaunt bloklangan', statusCode: 403));

      expect(message, contains('bloklangan'));
      expect(message, isNot(contains('admin')));
    });

    test("every other failure keeps the server's own words", () {
      expect(
        adminLoginMessage(ApiException('network', "Serverga ulanib bo'lmadi — internetni tekshiring")),
        "Serverga ulanib bo'lmadi — internetni tekshiring",
      );
    });

    testWidgets('and it is drawn on the login screen rather than swallowed', (tester) async {
      useDesktopWindow(tester);

      await tester.pumpWidget(hosting(AdminLoginScreen(
        notice: adminLoginMessage(ApiException('account_banned', 'Akkaunt bloklangan', statusCode: 403)),
        onIdToken: (_) {},
        onError: (_) {},
      )));
      await settle(tester);

      expect(find.textContaining('bloklangan'), findsOneWidget);
      expect(find.text("Ruxsat yo'q"), findsNothing);
      // Still offered, because a different account may well work.
      expect(find.text('Google orqali kirish'), findsOneWidget);
    });
  });

  group('the user list', () {
    testWidgets('the accounts are drawn, banned ones marked', (tester) async {
      useDesktopWindow(tester);
      final api = AdminApiClient(
        httpClient: MockClient((_) async => json(onePage([
              userRow(),
              userRow(id: 8, nickname: 'ravshan', banned: true),
            ]))),
      );

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      expect(find.text('umida_plays'), findsOneWidget);
      expect(find.text('ravshan'), findsOneWidget);
      expect(find.text('BLOK'), findsOneWidget);
      expect(find.text('faol'), findsOneWidget);
    });

    testWidgets('a ban is confirmed first, then shown on the row it changed', (tester) async {
      useDesktopWindow(tester);
      final posted = <String>[];
      final api = AdminApiClient(httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          posted.add(request.url.path);
          return json(userRow(banned: true));
        }
        return json(onePage([userRow()]));
      }));

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      await tester.tap(find.byTooltip('Bloklash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Nothing has been sent yet: the dialog is the confirmation.
      expect(posted, isEmpty);
      expect(find.text('Akkauntni bloklash'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Bloklash'));
      await settle(tester);

      expect(posted, ['/api/admin/users/7/ban']);
      expect(find.text('BLOK'), findsOneWidget);
      expect(find.textContaining('bloklandi'), findsOneWidget);
    });

    testWidgets('backing out of the confirmation changes nothing', (tester) async {
      useDesktopWindow(tester);
      var posts = 0;
      final api = AdminApiClient(httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return json(userRow(banned: true));
        }
        return json(onePage([userRow()]));
      }));

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      await tester.tap(find.byTooltip('Bloklash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Bekor qilish'));
      await settle(tester);

      expect(posts, 0);
      expect(find.text('BLOK'), findsNothing);
    });

    testWidgets('a nickname the server refuses is shown, not swallowed', (tester) async {
      useDesktopWindow(tester);
      final api = AdminApiClient(httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          return json({'code': 'nickname_taken', 'message': 'Bu taxallus band'}, 409);
        }
        return json(onePage([userRow()]));
      }));

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      await tester.tap(find.byTooltip("Taxallusni o'zgartirish"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).last, 'band_nom');
      await tester.tap(find.widgetWithText(FilledButton, "O'zgartirish"));
      await settle(tester);

      expect(find.text('Bu taxallus band'), findsOneWidget);
    });

    testWidgets('a failed load says what went wrong and offers the way back', (tester) async {
      useDesktopWindow(tester);
      final api = AdminApiClient(
        httpClient: MockClient((_) async => json({'code': 'internal', 'message': 'Server xatosi'}, 500)),
      );

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      expect(find.text('Server xatosi'), findsOneWidget);
      expect(find.text('Qayta urinish'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a body that will not parse becomes a line rather than a spinner', (tester) async {
      useDesktopWindow(tester);
      // A `200` whose shape this client cannot read. Before the plain `catch`
      // in `AdminLoading.guard` this escaped as a `FormatException` and left
      // the screen loading forever with nothing said.
      final api = AdminApiClient(httpClient: MockClient((_) async => json({'items': 'not a list'})));

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (_) {}, onOpenUser: (_) {}),
      ));
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining("Javobni o'qib bo'lmadi"), findsOneWidget);
    });

    testWidgets('a dead token is handed up rather than shown as a banner', (tester) async {
      useDesktopWindow(tester);
      ApiException? handed;
      final api = AdminApiClient(
        httpClient: MockClient((_) async => json({'code': 'unauthorized', 'message': 'Token eskirgan'}, 401)),
      );

      await tester.pumpWidget(hosting(
        AdminUsersScreen(api: api, onAuthFailure: (e) => handed = e, onOpenUser: (_) {}),
      ));
      await settle(tester);

      // The screen cannot fix this one — only the root can, by dropping the
      // session and going back to the login screen.
      expect(handed?.isUnauthorized, isTrue);
      expect(find.text('Token eskirgan'), findsNothing);
    });
  });
}

/// Stands in for a dart:io SocketException without importing dart:io.
class _Offline implements Exception {
  const _Offline();
}
