import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'models.dart';

/// Remembers the login between launches. The token is the only thing stored;
/// everything else is fetched fresh, so a stale profile can never be shown.
class Session {
  Session(this._api);

  static const _tokenKey = 'wb_token';

  final ApiClient _api;
  UserDto? user;

  bool get isLoggedIn => _api.token != null;

  /// True when a stored token was accepted, false when there was none or the
  /// server refused the one there was.
  ///
  /// Throws [ApiException] when the check could not be made at all. That
  /// distinction is the whole point: this used to swallow every failure and
  /// forget the token, so opening the app with no signal — a lift, a tunnel, a
  /// server restart — logged the player out for good and dropped the Google
  /// account link with it. Only a token the server actively rejects is worth
  /// forgetting; a network that is merely down says nothing about it, and the
  /// caller shows the offline screen and retries instead.
  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return false;

    _api.token = token;
    try {
      user = await _api.me();
      return true;
    } on ApiException catch (e) {
      if (!e.endsSession) rethrow;
      // Expired, revoked, or the account is gone: start over at onboarding.
      await clear();
      return false;
    }
  }

  Future<void> save(String token, UserDto loggedIn) async {
    _api.token = token;
    user = loggedIn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clear() async {
    _api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  String? get token => _api.token;
}
