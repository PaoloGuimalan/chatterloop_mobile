// Resolves and tracks auth state once at startup, replacing main.dart's old
// build()-time checkToken() (which ran on every rebuild with two artificial
// Future.delayed(seconds: 3) calls). Exposed as a Listenable so GoRouter can
// re-evaluate its redirect the moment auth state changes.

import 'dart:async';

import 'package:chatterloop_app/core/auth/consent_prefs.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/auth_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/foundation.dart';
import 'package:redux/redux.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._store) {
    _storeSubscription = _store.onChange.listen(_onStoreChange);
  }

  final Store<AppState> _store;
  late final StreamSubscription<AppState> _storeSubscription;

  AuthStatus status = AuthStatus.unknown;

  void _onStoreChange(AppState state) {
    final resolved = state.userAuth.auth == null
        ? AuthStatus.unknown
        : (state.userAuth.auth!
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated);
    if (resolved != status) {
      status = resolved;
      notifyListeners();
    }
  }

  /// Runs once at app start. No artificial delay - the splash route stays
  /// up for however long the network call actually takes.
  Future<void> resolve() async {
    final token = await ApiClient.instance.readToken();
    if (token == null) {
      _store.dispatch(
          DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
      return;
    }

    JWTCheckerResponse? response;
    try {
      response = await AuthApi().jwtCheckerRequest();
    } catch (_) {
      response = null;
    }

    if (response == null) {
      await ApiClient.instance.clearToken();
      _store.dispatch(
          DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
      return;
    }

    try {
      final payload = JwtCodec.decode(response.usertoken);
      var account = UserAccount.fromNodeJwt(payload ?? const {},
          allowedModules: response.allowedModules,
          activeEntity: response.activeEntity,
          personalEntityId: response.personalEntityId);
      // Strict consent half of the restore gate: the Node token reports
      // profile completeness but never consent state, so re-apply the pending
      // consents persisted at the last authoritative (Django) login. Any
      // still pending means the account isn't complete and must pass through
      // /setup again before reaching the app.
      final storedPending = await ConsentPrefs.read();
      if (storedPending.isNotEmpty) {
        account = account.copyWith(
            pendingConsents: storedPending, isComplete: false);
      }
      _store.dispatch(DispatchModel(setUserAuthT, UserAuth(true, account)));
    } catch (_) {
      // A malformed/expired token throws rather than returning null - fall
      // back to signed-out instead of crashing the auth guard.
      await ApiClient.instance.clearToken();
      _store.dispatch(
          DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    }
  }

  @override
  void dispose() {
    _storeSubscription.cancel();
    super.dispose();
  }
}
