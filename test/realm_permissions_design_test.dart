import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/views/realm/realm_permissions_view.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/models/user_models/realm_policy_model.dart';
import 'package:chatterloop_app/views/realm/realm_role_name_dialog.dart';
import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'realm_permissions_test.dart';

class LongPermissions extends RolesApi {
  @override
  Future<RealmPermissionSettings> permissions(String id) async =>
      RealmPermissionSettings.fromJson({
        'capabilities': {
          'can_manage_permissions': true,
          'can_manage_roles': true
        },
        'roles': [
          {
            'id': 12,
            'name': 'Community editorial contributors',
            'code': 'editors',
            'editable': true,
            'permissions_editable': true,
            'permissions': []
          }
        ],
        'catalog': [
          {
            'code': 'realm.custom.review',
            'name': 'Review submissions and coordinate community activities',
            'description':
                'Review proposed contributions and keep the community informed about decisions and next steps.',
            'grantable': true
          }
        ]
      });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('Permissions uses native heading and permission name sizes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: RealmPermissionsView(realmId: 'r', api: RolesFixture())));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.text('Roles and permissions')).style?.fontSize,
        CLType.sectionTitle);
    expect(tester.widget<Text>(find.text('Writers')).style?.fontSize,
        CLType.title);
    await tester.tap(find.text('Writers'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.text('Submit community posts'))
            .style
            ?.fontSize,
        CLType.title);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 768.0]) {
      for (final scale in [1.0, 1.6, 3.0]) {
        testWidgets(
            'permission controls wrap at $width/$scale/${brightness.name}',
            (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MaterialApp(
              theme: buildCLTheme(brightness),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home:
                  RealmPermissionsView(realmId: 'r', api: LongPermissions())));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
              find.text('Community editorial contributors'), 180,
              scrollable: find.byType(Scrollable).first, maxScrolls: 40);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Community editorial contributors'));
          await tester.pumpAndSettle();
          expect(
              find.text(
                  'Review submissions and coordinate community activities'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text('Save permissions'), 180,
              scrollable: find.byType(Scrollable).first, maxScrolls: 60);
          await tester.pumpAndSettle();
          final save = find.ancestor(
              of: find.text('Save permissions'),
              matching: find.byType(TextButton));
          expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
          expect(tester.widget<Text>(find.text('Save permissions')).overflow,
              isNot(TextOverflow.ellipsis));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'role naming uses native dialog validation and trims a confirmed name',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<String>(
                          context: context,
                          builder: (_) =>
                              const RealmRoleNameDialog(title: 'Create role'));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.ancestor(
                of: find.text('Save role'), matching: find.byType(TextButton)))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '  Editorial team  ');
    await tester.pump();
    await tester.tap(find.text('Save role'));
    await tester.pumpAndSettle();
    expect(result, 'Editorial team');
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final action in ['Save role', 'Cancel']) {
      testWidgets(
          'role dialog $action stays reachable at320px3x with keyboard ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? result;
        await tester.pumpWidget(MaterialApp(
            theme: buildCLTheme(brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(3),
                    viewInsets: const EdgeInsets.only(bottom: 300)),
                child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await showDialog<String>(
                              context: context,
                              builder: (_) => const RealmRoleNameDialog(
                                  title: 'Rename role',
                                  initialValue: '  Editorial team  '));
                        },
                        child: const Text('Open'))))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text(action), 100,
            scrollable: find.byType(Scrollable).first, maxScrolls: 30);
        await tester.pumpAndSettle();
        final button = find.ancestor(
            of: find.text(action), matching: find.byType(TextButton));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(tester.widget<Text>(find.text(action)).overflow,
            isNot(TextOverflow.ellipsis));
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(result, action == 'Save role' ? 'Editorial team' : null);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
