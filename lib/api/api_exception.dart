/// A failure the UI can show: either the server's own `{code, message}` error
/// or a transport problem.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  factory ApiException.network([Object? cause]) =>
      ApiException('network', "Serverga ulanib bo'lmadi — internetni tekshiring", statusCode: null)
        ..cause = cause;

  final String code;
  final String message;
  final int? statusCode;
  Object? cause;

  bool get isUnauthorized => statusCode == 401;

  /// True when the failure means the session is over rather than that one call
  /// went wrong. A 401 is the obvious case; `user_not_found` is the other one —
  /// the account was deleted, so the token is signed correctly but names
  /// nobody. Anything else — a timeout, a refused connection, a 500 — says
  /// nothing about the token, and must never be treated as a logout.
  bool get endsSession => isUnauthorized || code == 'user_not_found';

  @override
  String toString() => 'ApiException($code, $message)';
}
