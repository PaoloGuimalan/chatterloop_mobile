// Client payload/response HMAC key (jwt_codec.dart) and X-Nonce derivation
// (api_client.dart). Match Node JWT_SECRET and Django JWT_TOKEN.
// Authentication JWTs use a DIFFERENT, server-only AUTHENTICATION_SECRET;
// never put that key in env.json or any client build. Supply this client key
// via `--dart-define-from-file=env.json` (see env.example.json for the
// expected shape) or `--dart-define=SECRET_KEY=...`. env.json is
// gitignored - never commit real values into this file or into env.json.
const String secretKey = String.fromEnvironment('SECRET_KEY');
