import 'package:http/http.dart' as http;

import 'models.dart';
import 'rest_transport.dart';

/// Thin REST client. Every call carries the JWT and turns a non-2xx response
/// into an [ApiException] with the server's own error code, so screens can
/// react to `nickname_taken` or a 401 without parsing strings.
///
/// The header, the timeout and the error rule live in [RestTransport], which the
/// admin panel's client shares — see `lib/admin/admin_api_client.dart`.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _rest = RestTransport(httpClient: httpClient);

  final RestTransport _rest;

  /// The JWT sent with every call. Null before login and after logout.
  String? get token => _rest.token;

  set token(String? value) => _rest.token = value;

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) => _rest.get(path, query);

  Future<dynamic> _post(String path, [Object? body]) => _rest.post(path, body);

  Future<dynamic> _put(String path, Object body) => _rest.put(path, body);

  Future<dynamic> _delete(String path) => _rest.delete(path);

  // ---------------------------------------------------------------- auth

  /// Production login. The idToken comes from `GoogleAuth`; the server checks
  /// it against Google's public keys before issuing our own token.
  Future<({String token, UserDto user, bool needsNickname})> loginWithGoogle(String idToken) async {
    final json = await _post('/auth/google', {'idToken': idToken}) as Map<String, dynamic>;
    return _loginResult(json);
  }

  /// Throwaway account for development, served only while the backend runs
  /// with `wordbattle.dev-login-enabled`. Every call creates a new player.
  Future<({String token, UserDto user, bool needsNickname})> loginDev(String displayName) async {
    final json = await _post('/auth/dev', {'displayName': displayName}) as Map<String, dynamic>;
    return _loginResult(json);
  }

  ({String token, UserDto user, bool needsNickname}) _loginResult(Map<String, dynamic> json) => (
        token: json['token'] as String,
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
        needsNickname: json['needsNickname'] as bool? ?? false,
      );

  // --------------------------------------------------------------- users

  Future<UserDto> me() async => UserDto.fromJson(await _get('/users/me') as Map<String, dynamic>);

  Future<NicknameCheck> checkNickname(String value) async =>
      NicknameCheck.fromJson(await _get('/users/nickname/check', {'value': value}) as Map<String, dynamic>);

  Future<UserDto> claimNickname(String nickname) async =>
      UserDto.fromJson(await _put('/users/me/nickname', {'nickname': nickname}) as Map<String, dynamic>);

  Future<ProfileDto> profile() async => ProfileDto.fromJson(await _get('/users/me/profile') as Map<String, dynamic>);

  Future<UserDto> setCity(String city) async =>
      UserDto.fromJson(await _put('/users/me/city', {'city': city}) as Map<String, dynamic>);

  /// Deletes the account for good. The token is dead the moment this returns.
  Future<void> deleteAccount() => _delete('/users/me');

  Future<List<UserDto>> searchUsers(String query) async {
    final list = await _get('/users/search', {'q': query}) as List;
    return list.map((e) => UserDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ------------------------------------------------------------- friends

  Future<List<FriendDto>> friends() async {
    final list = await _get('/friends') as List;
    return list.map((e) => FriendDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<FriendRequestDto>> friendRequests() async {
    final list = await _get('/friends/requests') as List;
    return list.map((e) => FriendRequestDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendFriendRequest(int userId) => _post('/friends/requests', {'userId': userId});

  Future<void> acceptFriendRequest(int id) => _post('/friends/requests/$id/accept');

  Future<void> declineFriendRequest(int id) => _post('/friends/requests/$id/decline');

  Future<void> removeFriend(int userId) => _delete('/friends/$userId');

  // ------------------------------------------------------------- history

  Future<List<MatchSummaryDto>> matchHistory({int limit = 20}) async {
    final list = await _get('/matches', {'limit': limit}) as List;
    return list.map((e) => MatchSummaryDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MatchDetailDto> matchDetail(int id) async =>
      MatchDetailDto.fromJson(await _get('/matches/$id') as Map<String, dynamic>);

  // --------------------------------------------------- leaderboard, extras

  Future<LeaderboardDto> globalLeaderboard() async =>
      LeaderboardDto.fromJson(await _get('/leaderboard/global') as Map<String, dynamic>);

  Future<LeaderboardDto> friendsLeaderboard() async =>
      LeaderboardDto.fromJson(await _get('/leaderboard/friends') as Map<String, dynamic>);

  Future<PracticeWordDto> practiceWord() async =>
      PracticeWordDto.fromJson(await _get('/practice/word') as Map<String, dynamic>);

  Future<List<String>> practiceHints(String letter) async {
    final list = await _get('/practice/hints', {'letter': letter}) as List;
    return list.map((e) => e as String).toList();
  }

  void close() => _rest.close();
}
