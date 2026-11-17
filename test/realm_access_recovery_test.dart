import 'dart:async';
import 'package:chatterloop_app/core/auth/realm_access_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = {
    'code': 'REALM_ACCESS_REVOKED',
    'message': 'Your access to Garden Club was revoked.'
  };
  test(
      'Node and Django revocations share copy and ordinary denials do not switch',
      () {
    expect(revokedRealmMessage(body), body['message']);
    expect(
        revokedRealmMessage(
            {'detail': 'REALM_ACCESS_REVOKED: ${body['message']}'}),
        body['message']);
    expect(revokedRealmMessage({'message': 'Forbidden'}), isNull);
    expect(
        revokedRealmMessage({'code': 'AUTHORITY_CHECK_UNAVAILABLE'}), isNull);
  });
  test(
      'concurrent HTTP/SSE denials switch once and late failures cannot switch a new identity',
      () async {
    String? token = 'realm';
    final finish = Completer<void>();
    var switches = 0;
    final notices = <String>[];
    final recovery = RealmAccessRecovery(
        readToken: () async => token,
        switchBack: (expected) async {
          switches++;
          expect(expected, 'realm');
          await finish.future;
          token = 'personal';
          return true;
        },
        onRecovered: notices.add);
    final first = recovery.handle(body, token: 'realm');
    final second = recovery.handle(body, token: 'realm');
    await Future<void>.delayed(Duration.zero);
    expect(switches, 1);
    finish.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(notices, [body['message']]);
    token = 'other-page';
    expect(await recovery.handle(body, token: 'realm'), isTrue);
    token = null;
    expect(await recovery.handle(body, token: 'realm'), isTrue);
    expect(switches, 1);
    expect(notices.length, 1);
  });
  test('switch-back failure can retry and never claims success', () async {
    var calls = 0;
    final recovery = RealmAccessRecovery(
        readToken: () async => 'realm', switchBack: (_) async => ++calls > 1);
    expect(await recovery.handle(body, token: 'realm'), isFalse);
    expect(await recovery.handle(body, token: 'realm'), isTrue);
    expect(await recovery.handle({'message': 'Forbidden'}, token: 'realm'),
        isFalse);
    expect(calls, 2);
  });
}
