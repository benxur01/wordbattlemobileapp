import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import 'models.dart';

/// Thin REST client. Every call carries the JWT and turns a non-2xx response
/// into an [ApiException] with the server's own error code, so screens can
/// react to `nickname_taken` or a 401 without parsing strings.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// The JWT sent with every call. Null before login and after logout.
  String? token;

  static const _timeout = Duration(seconds: 10);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException catch (e) {
      throw ApiException.network(e);
    } catch (e) {
      throw ApiException.network(e);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }

    String code = 'http_${response.statusCode}';
    String message = 'Server xatosi (${response.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      code = (body['code'] as String?) ?? code;
      message = (body['message'] as String?) ?? message;
    } catch (_) {
      // non-JSON error body — keep the generic message
    }
    throw ApiException(code, message, statusCode: response.statusCode);
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) =>
      _send(() => _http.get(ApiConfig.rest(path, query), headers: _headers));

  Future<dynamic> _post(String path, [Object? body]) =>
      _send(() => _http.post(ApiConfig.rest(path), headers: _headers, body: body == null ? null : jsonEncode(body)));

  Future<dynamic> _put(String path, Object body) =>
      _send(() => _http.put(ApiConfig.rest(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> _delete(String path) => _send(() => _http.delete(ApiConfig.rest(path), headers: _headers));

  // ---------------------------------------------------------------- auth

  /// Development login. Production builds use [loginWithTelegram].
  Future<({String token, UserDto user, bool needsNickname})> loginDev(int telegramId, String displayName) async {
    final json = await _post('/auth/dev', {'telegramId': telegramId, 'displayName': displayName})
        as Map<String, dynamic>;
    return _loginResult(json);
  }

  Future<({String token, UserDto user, bool needsNickname})> loginWithTelegram(String initData) async {
    final json = await _post('/auth/telegram', {'initData': initData}) as Map<String, dynamic>;
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

  void close() => _http.close();
}
