// Wraps JwtTools with the client payload/response signing key, so call sites
// don't each need to import keys.dart and thread secretKey through by
// hand. Mirrors chatterloop_mobile/lib/services/jwt_helper.dart's role as
// the one place JWT encode/decode happens.

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' show JWT;

class JwtCodec {
  const JwtCodec._();

  static final _tools = JwtTools();

  static String sign(Map<String, dynamic> payload) =>
      _tools.createJwt(payload, secretKey);

  static Map<String, dynamic>? decode(String token) =>
      _tools.verifyJwt(token, secretKey);

  // Access tokens use the server-only AUTHENTICATION_SECRET. Read claims only
  // to label the nonce; the server verifies authentication and device sessions.
  // This is not signature verification and must not authorize client actions.
  static Map<String, dynamic>? readClaims(String token) =>
      JWT.decode(token).payload as Map<String, dynamic>;
}
