import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('access-token claims can supply nonce identity without the server key', () {
    final token = JWT({'userID': 'account-1', 'entity': 'entity-1'})
        .sign(SecretKey('server-only-authentication-test-key-different'));

    expect(JwtCodec.readClaims(token)?['userID'], 'account-1');
    // Response verification must stay strict; no fallback for wrong signatures.
    expect(() => JwtCodec.decode(token), throwsA(isA<JWTException>()));
  });

  test('client-signed payloads retain verified decoding', () {
    final token = JwtCodec.sign({'content': 'hello'});
    expect(JwtCodec.decode(token)?['content'], 'hello');
  });
}
