// Native Google Sign-In - the mobile equivalent of the webapp's
// <GoogleLogin> (@react-oauth/google). Its whole job is to obtain a Google
// ID token (the same thing the webapp calls `credentialResponse.credential`)
// which is then POSTed to Django's /api/user/tp_auth for login/auto-signup.
//
// For the returned ID token to be accepted by the server, its audience must
// match the web OAuth client the server verifies against - so we pass that
// web client id as `serverClientId`. It must be the SAME client id the
// webapp uses (its VITE_GOOGLE_CLIENT_ID), from the same Google Cloud
// project. On Android an OAuth *Android* client (matching the app's package
// name + signing SHA-1) must also exist in that project, or the native
// sign-in fails with ApiException 10 (DEVELOPER_ERROR) - that's a Google
// Cloud Console setup step, not a code one.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web OAuth client id (webapp's VITE_GOOGLE_CLIENT_ID, same Google Cloud
/// project). Supplied from env.json via `--dart-define-from-file=env.json`
/// (see env.example.json for the shape) - same mechanism as SECRET_KEY in
/// keys.dart. Passed as serverClientId so the ID token's audience matches
/// what the server verifies. Empty (build without env.json) -> the button
/// reports it isn't configured rather than sending an unverifiable token.
const String kGoogleServerClientId =
    String.fromEnvironment('GOOGLE_CLIENT_ID');

/// Thrown for a real sign-in failure (not a user cancellation) so the UI can
/// show a meaningful message.
class GoogleAuthException implements Exception {
  final String message;
  GoogleAuthException(this.message);
  @override
  String toString() => message;
}

class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile', 'openid'],
    // Empty -> null so google_sign_in falls back to platform defaults rather
    // than throwing; we still guard on it in signIn() below, since without a
    // real web client id the token can't be verified server-side anyway.
    serverClientId:
        kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
  );

  bool get isConfigured => kGoogleServerClientId.isNotEmpty;

  /// Runs the native Google account chooser and returns the resulting Google
  /// ID token. Returns null if the user cancels; throws [GoogleAuthException]
  /// on a genuine failure.
  Future<String?> signIn() async {
    if (!isConfigured) {
      throw GoogleAuthException(
          'Google sign-in isn\'t configured (missing web client id).');
    }
    try {
      // Sign out first so the account chooser always appears instead of
      // silently reusing the last account.
      await _googleSignIn.signOut();

      final account = await _googleSignIn.signIn();
      if (account == null) return null; // user dismissed the chooser

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw GoogleAuthException('Google did not return an ID token.');
      }
      return idToken;
    } on GoogleAuthException {
      rethrow;
    } catch (e) {
      if (kDebugMode) print('[GoogleAuthService] sign-in failed: $e');
      // ApiException 10 (DEVELOPER_ERROR) shows up here when the Android
      // OAuth client / SHA-1 isn't registered in the Cloud project.
      throw GoogleAuthException('Could not sign in with Google.');
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
