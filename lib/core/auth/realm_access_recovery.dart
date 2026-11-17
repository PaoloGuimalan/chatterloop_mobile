/// Coalesces revoked-identity recovery without owning HTTP, UI or token storage.
String? revokedRealmMessage(Object? body) {
  if (body is! Map) return null;
  final detail = body['detail'];
  if (detail is String && detail.startsWith('REALM_ACCESS_REVOKED:')) {
    return detail.substring('REALM_ACCESS_REVOKED:'.length).trim();
  }
  return body['code'] == 'REALM_ACCESS_REVOKED' && body['message'] is String
      ? body['message'] as String
      : null;
}

class RealmAccessRecovery {
  RealmAccessRecovery(
      {this.readToken, this.switchBack, this.onRecovered, this.onFailure});
  Future<String?> Function()? readToken;
  Future<bool> Function(String expectedToken)? switchBack;
  void Function(String message)? onRecovered;
  void Function()? onFailure;
  final Map<String, Future<bool>> _pending = {};

  Future<bool> handle(Object? body, {String? token}) async {
    final message = revokedRealmMessage(body);
    if (message == null ||
        token == null ||
        readToken == null ||
        switchBack == null) {
      return false;
    }
    if (await readToken!() != token) return true;
    final existing = _pending[token];
    if (existing != null) return existing;
    final future = _recover(token, message);
    _pending[token] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[token], future)) _pending.remove(token);
    }
  }

  Future<bool> _recover(String token, String message) async {
    try {
      if (await switchBack!(token)) {
        onRecovered?.call(message);
        return true;
      }
    } catch (_) {/* The existing switch flow reports request failures. */}
    if (await readToken!() != token) return true;
    onFailure?.call();
    return false;
  }
}

final realmAccessRecovery = RealmAccessRecovery();
