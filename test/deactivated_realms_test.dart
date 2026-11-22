import 'package:chatterloop_app/core/requests/realm_lifecycle_api.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';
import 'package:chatterloop_app/views/settings/deactivated_realms_view.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class RecoveryFixture extends RealmLifecycleApi {
  final calls = <String>[];
  @override
  Future<RecoveryPage> deactivated({String? cursor}) async =>
      RecoveryPage.fromJson({
        'items': calls.isNotEmpty
            ? []
            : [
                {
                  'realm_id': 'realm',
                  'name': 'Example',
                  'kind': 'community',
                  'actors': [
                    {'entity_id': 'page', 'name': 'My page'}
                  ]
                },
                {
                  'realm_id': 'child',
                  'name': 'Blocked channel',
                  'kind': 'channel',
                  'blocked_by_parent': true,
                  'actors': [
                    {'entity_id': 'me', 'name': 'Your profile'}
                  ]
                },
              ]
      });
  @override
  Future<void> reactivate(String id, String actor) async {
    calls.add('$id:$actor');
  }
}

void main() {
  testWidgets('recovery uses page actor and keeps blocked parent unavailable',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = RecoveryFixture();
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: DeactivatedRealmsView(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Example'), findsOneWidget);
    final buttons = tester
        .widgetList<CLBtn>(find.byType(CLBtn))
        .where((b) => b.label == 'Reactivate')
        .toList();
    expect(buttons[0].onPressed, isNotNull);
    expect(buttons[1].onPressed, isNull);
    await tester.tap(find.widgetWithText(CLBtn, 'Reactivate').first);
    await tester.pumpAndSettle();
    expect(api.calls, ['realm:page']);
    expect(find.text('Example'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
