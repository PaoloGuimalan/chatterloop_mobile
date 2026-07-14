// Wraps JwtTools with the shared signing secret baked in, so call sites
// don't each need to import keys.dart and thread secretKey through by
// hand. Mirrors chatterloop_mobile/lib/services/jwt_helper.dart's role as
// the one place JWT encode/decode happens.

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';

class JwtCodec {
  const JwtCodec._();

  static final _tools = JwtTools();

  static String sign(Map<String, dynamic> payload) =>
      _tools.createJwt(payload, secretKey);

  static Map<String, dynamic>? decode(String token) =>
      _tools.verifyJwt(token, secretKey);
}
