import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/realm_lifecycle_api.dart';
import 'package:chatterloop_app/models/user_models/realm_lifecycle_model.dart';
import 'package:chatterloop_app/views/realm/realm_lifecycle_view.dart';
import 'package:chatterloop_app/views/settings/deactivated_realms_view.dart';

class LifecycleLayoutFixture extends RealmLifecycleApi {
  @override
  Future<RealmLifecycle> get(String id) async => RealmLifecycle.fromJson({
        'realm_id': id,
        'name': 'Chatterloop Community',
        'kind': 'server',
        'child_count': 4,
        'capabilities': {
          'can_deactivate_realm': true,
          'can_delete_realm': true,
          'can_reactivate_realm': true
        },
        'owned_realm_blocker_count': 0,
        'owned_realm_blockers': [],
      });
  @override
  Future<RecoveryPage> deactivated({String? cursor}) async =>
      RecoveryPage.fromJson({
        'items': [
          {
            'realm_id': 'r',
            'name': 'Chatterloop Community',
            'kind': 'community',
            'actors': [
              {'entity_id': 'me', 'name': 'Your profile'},
              {'entity_id': 'page', 'name': 'My page'}
            ]
          },
          {
            'realm_id': 'c',
            'name': 'Private channel',
            'kind': 'channel',
            'blocked_by_parent': true,
            'actors': [
              {'entity_id': 'me', 'name': 'Your profile'}
            ]
          },
        ]
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 3.0]) {
        testWidgets(
            'realm lifecycle layouts ${dark ? 'dark' : 'light'} $width ${scale}x',
            (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final screen in ['manage', 'recovery']) {
            final key = GlobalKey();
            final api = LifecycleLayoutFixture();
            await tester.pumpWidget(MaterialApp(
                theme: buildCLTheme(dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: RepaintBoundary(
                    key: key,
                    child: screen == 'manage'
                        ? RealmLifecycleView(realmId: 'realm', api: api)
                        : DeactivatedRealmsView(api: api))));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final dir = Platform.environment['REALM_LIFECYCLE_CAPTURE_DIR'];
            if (dir != null && width == 390 && scale == 1) {
              await tester.runAsync(() async {
                final boundary = key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('$dir/native-$screen-${dark ? 'dark' : 'light'}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        });
      }
    }
  }
}
