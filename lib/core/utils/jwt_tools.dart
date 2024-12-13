import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class JwtTools {
  String createJwt(Map<String, dynamic> payload, String secret) {
    final jwt = JWT(
        // Payload
        payload);

    // Sign it (default with HS256 algorithm)
    final token = jwt.sign(SecretKey(secret));

    return token;
  }

  Map<String, dynamic>? verifyJwt(String token, String secret) {
    final jwt = JWT.verify(token, SecretKey(secret));

    return jwt.payload;
  }
}
