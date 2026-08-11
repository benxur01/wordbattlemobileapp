import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// The REST plumbing every client in this app shares: the bearer header on each
/// call, a timeout that fails instead of hanging, and the rule that turns a
/// non-2xx response into an [ApiException] carrying the server's own
/// `{code, message}`.
///
/// Lifted out of `ApiClient` unchanged when the admin panel arrived, rather than
/// copied into it. The copy would have been a second place for the 401 rule to
/// drift, and that rule is the one that tells a dead session apart from a call
/// that merely failed.
class RestTransport {
  RestTransport({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// The JWT sent with every call. Null before login and after logout.
  String? token;

  static const _timeout = Duration(seconds: 10);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> send(Future<http.Response> Function() request) async {
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

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) =>
      send(() => _http.get(ApiConfig.rest(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      send(() => _http.post(ApiConfig.rest(path), headers: _headers, body: body == null ? null : jsonEncode(body)));

  Future<dynamic> put(String path, Object body) =>
      send(() => _http.put(ApiConfig.rest(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => send(() => _http.delete(ApiConfig.rest(path), headers: _headers));

  void close() => _http.close();
}
