// Shared HMAC secret used for JWT signing/verification (jwt_codec.dart) and
// X-Nonce derivation (api_client.dart) - must match the server's own
// JWT_SECRET exactly (server/reusables/hooks/crypto.js reads it from
// process.env.JWT_SECRET). Compile-time constant, not hardcoded: supply it
// via `--dart-define-from-file=env.json` (see env.example.json for the
// expected shape) or `--dart-define=SECRET_KEY=...`. env.json is
// gitignored - never commit real values into this file or into env.json.
const String secretKey = String.fromEnvironment('SECRET_KEY');
