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

  @override
  String toString() => 'ApiException($code, $message)';
}
