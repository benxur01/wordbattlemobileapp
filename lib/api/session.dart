import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// Remembers the login between launches. The token is the only thing stored;
/// everything else is fetched fresh, so a stale profile can never be shown.
class Session {
  Session(this._api);

  static const _tokenKey = 'wb_token';

  final ApiClient _api;
  UserDto? user;

  bool get isLoggedIn => _api.token != null;

  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return false;

    _api.token = token;
    try {
      user = await _api.me();
      return true;
    } catch (_) {
      // Expired or revoked: drop it and start over at onboarding.
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
