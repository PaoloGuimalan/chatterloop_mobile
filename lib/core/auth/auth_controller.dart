// Resolves and tracks auth state once at startup, replacing main.dart's old
// build()-time checkToken() (which ran on every rebuild with two artificial
// Future.delayed(seconds: 3) calls). Exposed as a Listenable so GoRouter can
// re-evaluate its redirect the moment auth state changes.

import 'dart:async';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:redux/redux.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._store) {
    _storeSubscription = _store.onChange.listen(_onStoreChange);
  }

  final Store<AppState> _store;
  final _storage = const FlutterSecureStorage();
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
    final token = await _storage.read(key: 'token');
    if (token == null) {
      _store.dispatch(
          DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
      return;
    }

    JWTCheckerResponse? response;
    try {
      response = await APIRequests().jwtCheckerRequest();
    } catch (_) {
      response = null;
    }

    if (response == null) {
      await _storage.delete(key: 'token');
      _store.dispatch(
          DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
      return;
    }

    try {
      final payload = JwtTools().verifyJwt(response.usertoken, secretKey);
      final account = UserAccount.fromNodeJwt(payload ?? const {},
          allowedModules: response.allowedModules,
          activeEntity: response.activeEntity,
          personalEntityId: response.personalEntityId);
      _store.dispatch(DispatchModel(setUserAuthT, UserAuth(true, account)));
    } catch (_) {
      // A malformed/expired token throws rather than returning null - fall
      // back to signed-out instead of crashing the auth guard.
      await _storage.delete(key: 'token');
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
