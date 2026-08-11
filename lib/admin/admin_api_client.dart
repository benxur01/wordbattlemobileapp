import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import '../api/models.dart';
import '../api/rest_transport.dart';
import 'admin_models.dart';

/// The panel's REST client. Same transport as the game's [ApiClient] — the same
/// bearer header, the same timeout, the same `{code, message}` parsing — over
/// the `/api/admin/**` routes, which are closed to every token but an admin's.
///
/// The two codes worth branching on are both here and neither is a normal
/// failure: a `401` means the token is gone and the panel returns to the login
/// screen, and a `403 forbidden` means the account is signed in but is not an
/// admin, which is a screen of its own rather than a banner. See
/// [ApiException.isUnauthorized] and [isForbidden].
class AdminApiClient {
  AdminApiClient({http.Client? httpClient}) : _rest = RestTransport(httpClient: httpClient);

  final RestTransport _rest;

  /// The JWT sent with every call. Null before login and after logout.
  String? get token => _rest.token;

  set token(String? value) => _rest.token = value;

  // ----------------------------------------------------------------- auth

  /// The same public endpoint the game logs in through: the browser gets an
  /// idToken from Google, the server checks it against Google's public keys and
  /// hands back our own token. Nothing here asks for the admin role — that is
  /// [metrics] a moment later, and a `403` from it is what the panel shows the
  /// "no permission" screen for.
  ///
  /// A banned account is refused right here with `403 account_banned`, which is
  /// a message rather than a permission screen.
  Future<({String token, UserDto user})> loginWithGoogle(String idToken) async {
    final json = await _rest.post('/auth/google', {'idToken': idToken}) as Map<String, dynamic>;
    return (
      token: json['token'] as String,
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  /// Who the token belongs to, for the name in the panel's header.
  Future<UserDto> me() async => UserDto.fromJson(await _rest.get('/users/me') as Map<String, dynamic>);

  // ---------------------------------------------------------------- users

  Future<AdminPage<AdminUserRow>> users({String query = '', int page = 0, int size = 20}) async {
    final json = await _rest.get('/admin/users', {
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'page': page,
      'size': size,
    }) as Map<String, dynamic>;
    return AdminPage.fromJson(json, AdminUserRow.fromJson);
  }

  Future<AdminUserDetail> user(int id) async =>
      AdminUserDetail.fromJson(await _rest.get('/admin/users/$id') as Map<String, dynamic>);

  /// Takes the account away: the player is dropped from any duel and socket
  /// they hold and every token they have stops working. Idempotent on the
  /// server, so a double-tap cannot move the timestamp recording when they
  /// actually lost it.
  Future<AdminUserRow> ban(int id, {String? reason}) async {
    final trimmed = reason?.trim();
    final json = await _rest.post(
      '/admin/users/$id/ban',
      {'reason': trimmed == null || trimmed.isEmpty ? null : trimmed},
    ) as Map<String, dynamic>;
    return AdminUserRow.fromJson(json);
  }

  Future<AdminUserRow> unban(int id) async =>
      AdminUserRow.fromJson(await _rest.post('/admin/users/$id/unban') as Map<String, dynamic>);

  /// Held to the same rules as the onboarding field, because the server runs it
  /// through the same code: `400 nickname_invalid` and `409 nickname_taken` are
  /// both possible and both worth showing as they are.
  Future<AdminUserRow> rename(int id, String nickname) async =>
      AdminUserRow.fromJson(await _rest.put('/admin/users/$id/nickname', {'nickname': nickname}) as Map<String, dynamic>);

  // -------------------------------------------------------------- matches

  Future<AdminPage<AdminMatchRow>> matches({int page = 0, int size = 20}) async {
    final json = await _rest.get('/admin/matches', {'page': page, 'size': size}) as Map<String, dynamic>;
    return AdminPage.fromJson(json, AdminMatchRow.fromJson);
  }

  // ------------------------------------------------------- metrics, audit

  /// Doubles as the role check: any token can be sent, but only an admin's is
  /// answered. The panel calls it once after login for exactly that reason.
  Future<AdminMetrics> metrics() async =>
      AdminMetrics.fromJson(await _rest.get('/admin/metrics') as Map<String, dynamic>);

  Future<AdminPage<AdminAuditEntry>> auditLog({int page = 0, int size = 50}) async {
    final json = await _rest.get('/admin/audit-log', {'page': page, 'size': size}) as Map<String, dynamic>;
    return AdminPage.fromJson(json, AdminAuditEntry.fromJson);
  }

  void close() => _rest.close();
}

/// A signed-in account that may not use the panel. Distinct from
/// [ApiException.isUnauthorized]: the token is perfectly good, so signing in
/// again would only produce the same answer.
extension AdminApiException on ApiException {
  bool get isForbidden => statusCode == 403;

  /// The panel's "no permission" screen is only for the admin routes refusing
  /// the role. `/auth/google` answers `403 account_banned` too, and that one is
  /// a message about the account rather than a verdict on the role.
  bool get isRoleRefusal => isForbidden && code != 'account_banned';
}
