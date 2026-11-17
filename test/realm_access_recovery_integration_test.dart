import 'dart:async';
import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/auth/realm_access_recovery.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/entity_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String original, personal;
  final userDio = ApiClient.userService.dio;
  final nodeDio = ApiClient.instance.dio;
  setUp(() {
    original = JwtCodec.sign(
        {'userID': 'account', 'username': 'paolo', 'entity': 'realm'});
    personal = JwtCodec.sign(
        {'userID': 'account', 'username': 'paolo', 'entity': 'personal'});
    FlutterSecureStorage.setMockInitialValues({'token': original});
    appStore.dispatch(DispatchModel(
        resetAppStateT,
        const UserAuth(
            true,
            UserAccount('account', 'paolo', 'Paolo', '', '', null, true, true,
                null, null, null, null,
                personalEntityId: 'personal',
                activeEntity: ActiveEntity(
                    id: 'realm', type: 'realm', name: 'Garden Club')))));
  });
  tearDown(() {
    realmAccessRecovery.readToken = null;
    realmAccessRecovery.switchBack = null;
    realmAccessRecovery.onRecovered = null;
    realmAccessRecovery.onFailure = null;
  });
  void intercept(Dio dio, InterceptorsWrapper interceptor) {
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
  }

  Map<String, dynamic> restored() => {
        'status': true,
        'result': {
          'usertoken': JwtCodec.sign({
            '_id': 'account',
            'userID': 'paolo',
            'firstname': 'Paolo',
            'isActivated': true,
            'isVerified': true,
            'isComplete': true
          }),
          'personal_entity_id': 'personal',
          'active_entity': {'id': 'personal', 'type': 'user'},
          'allowed_modules': ['module.diary.access']
        }
      };

  test(
      'revocation during session restore reuses switch-back and stale restore cannot log out the restored account',
      () async {
    var switches = 0;
    final notices = <String>[];
    intercept(userDio, InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, contains('/entity/switch-back'));
      expect(options.extra['authToken'], original);
      expect(options.extra['skipRealmRecovery'], isTrue);
      switches++;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'status': true,
        'result': {'authtoken': personal, 'personal_entity_id': 'personal'}
      }));
    }));
    intercept(nodeDio, InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await ApiClient.instance.readToken();
      options.headers['x-access-token'] = token;
      if (token == original) {
        handler.reject(
            DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response:
                    Response(requestOptions: options, statusCode: 403, data: {
                  'code': 'REALM_ACCESS_REVOKED',
                  'message': 'Your access to Garden Club was revoked.'
                })),
            true);
      } else {
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: restored()));
      }
    }));
    realmAccessRecovery.readToken = ApiClient.instance.readToken;
    realmAccessRecovery.switchBack =
        (token) => EntityApi().switchBackRequest(expectedToken: token);
    realmAccessRecovery.onRecovered = notices.add;
    final controller = AuthController(appStore);
    addTearDown(controller.dispose);
    await controller.resolve();
    expect(switches, 1);
    expect(notices, ['Your access to Garden Club was revoked.']);
    expect(await ApiClient.instance.readToken(), personal);
    expect(appStore.state.userAuth.auth, isTrue);
    expect(appStore.state.userAuth.user.entityId, 'personal');
    expect(
        appStore.state.userAuth.user.allowedModules, ['module.diary.access']);
    expect(appStore.state.messages, isEmpty);
    expect(appStore.state.isTypingList, isEmpty);
  });
  test('late switch-back response cannot overwrite a manual identity switch',
      () async {
    final received = Completer<void>(), respond = Completer<void>();
    intercept(userDio, InterceptorsWrapper(onRequest: (options, handler) async {
      received.complete();
      await respond.future;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'status': true,
        'result': {'authtoken': personal}
      }));
    }));
    final request = EntityApi().switchBackRequest(expectedToken: original);
    await received.future;
    await ApiClient.instance.writeToken('other-page');
    respond.complete();
    expect(await request, isFalse);
    expect(await ApiClient.instance.readToken(), 'other-page');
    expect(appStore.state.userAuth.user.entityId, 'realm');
  });
}
