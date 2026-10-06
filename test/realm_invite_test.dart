// Realm invites in the app: the model's sentence and destination (mirrors of
// the server's invite_rules.py and the webapp's invites.ts), the invite
// screen's answers, and the push route that leads to it.
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/notifications/push_payload.dart';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
import 'package:chatterloop_app/views/realm/realm_invite_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> _json({
  String type = 'group',
  String purpose = 'join',
  String? role,
  String status = 'pending',
  String? slug,
  String kind = 'invite',
}) =>
    {
      'id': 'inv1',
      'realm_id': 'R100',
      'realm_name': 'Weekend Hikers',
      'realm_type': type,
      'realm_slug': slug,
      'realm_profile': 'none',
      'kind': kind,
      'status': status,
      'purpose': purpose,
      'role': role,
      'inviter': {
        'id': 'maya',
        'type': 'user',
        'details': {'first_name': 'Maya', 'last_name': 'Reyes', 'username': 'maya'},
      },
      'target_email': null,
      'target_entity': null,
      'invite_token': 'tok1',
      'created_at': '2026-10-06T10:00:00Z',
    };

class _FakeInvites implements InvitesApi {
  RealmInvite? invite;
  final answers = <String>[];

  _FakeInvites(this.invite);

  @override
  Future<RealmInvite?> getByToken(String token) async => invite;

  @override
  Future<RealmInvite?> answer(String token, String status) async {
    answers.add(status);
    return invite = invite?.withStatus(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_FakeInvites api, {Future<bool> Function(Uri)? openExternal}) {
  final router = GoRouter(initialLocation: '/invite/tok1', routes: [
    GoRoute(
      path: '/invite/:token',
      builder: (c, s) => openExternal == null
          ? RealmInviteScreen(token: s.pathParameters['token']!, api: api)
          : RealmInviteScreen(
              token: s.pathParameters['token']!,
              api: api,
              openExternal: openExternal,
            ),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (c, s) =>
          Scaffold(body: Text('conversation ${s.pathParameters['id']}')),
    ),
  ]);
  return MaterialApp.router(
    theme: buildCLTheme(Brightness.light),
    routerConfig: router,
  );
}

void main() {
  group('RealmInvite', () {
    test('says who invited you to what', () {
      expect(RealmInvite.fromJson(_json()).sentence,
          'Maya Reyes invited you to join the group Weekend Hikers.');
      expect(RealmInvite.fromJson(_json(type: 'server')).sentence,
          'Maya Reyes invited you to join the server Weekend Hikers.');
      expect(
          RealmInvite.fromJson(_json(type: 'page', purpose: 'follow')).sentence,
          'Maya Reyes invited you to follow Weekend Hikers.');
      expect(
          RealmInvite.fromJson(
                  _json(type: 'page', purpose: 'manage', role: 'admin'))
              .sentence,
          'Maya Reyes invited you to help run Weekend Hikers as an admin.');
    });

    test('an accepted invite goes to the realm, where the app has one', () {
      expect(RealmInvite.fromJson(_json()).destination, '/conversation/R100');
      expect(RealmInvite.fromJson(_json(type: 'server')).destination,
          '/server/R100');
      expect(
          RealmInvite.fromJson(
                  _json(type: 'page', purpose: 'follow', slug: 'acme'))
              .destination,
          '/realm/acme');
      expect(
          RealmInvite.fromJson(_json(
                  type: 'page', purpose: 'manage', role: 'moderator', slug: 'acme'))
              .destination,
          '/realm/acme/manage');
      // Conferences live on the web.
      expect(RealmInvite.fromJson(_json(type: 'conference', slug: 'sync'))
          .destination, isNull);
    });

    test('a conference invite leads to its lobby on the web', () {
      final invite =
          RealmInvite.fromJson(_json(type: 'conference', slug: 'team-sync'));
      expect(invite.conferenceUrl,
          'https://chatterloop.app/conference/team-sync?invite_token=tok1');
      expect(invite.conferenceAddress, 'chatterloop.app/conference/team-sync');
      expect(RealmInvite.fromJson(_json()).conferenceUrl, isNull);
      expect(RealmInvite.fromJson(_json(type: 'conference')).conferenceUrl,
          isNull,
          reason: 'no slug, no address');
    });

    test('"none" for a picture means no picture', () {
      expect(RealmInvite.fromJson(_json()).realmProfile, isNull);
    });
  });

  test('a push may lead to an invite', () {
    final payload = PushPayload.fromData({
      'type': 'realm_invite',
      'title': 'Weekend Hikers',
      'body': 'Maya invited you',
      'route': '/invite/tok1',
    });
    expect(payload.safeRoute, '/invite/tok1');
  });

  group('RealmInviteScreen', () {
    testWidgets('accepting goes on to the group', (tester) async {
      final api = _FakeInvites(RealmInvite.fromJson(_json()));
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      expect(find.text('Weekend Hikers'), findsOneWidget);
      expect(find.text('Maya Reyes invited you to join the group Weekend Hikers.'),
          findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(api.answers, ['accepted']);
      expect(find.text('conversation R100'), findsOneWidget);
    });

    testWidgets('declining stays, and says so', (tester) async {
      final api = _FakeInvites(RealmInvite.fromJson(_json()));
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(api.answers, ['declined']);
      expect(find.text('You declined this invite.'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('an answered invite offers no buttons', (tester) async {
      final api =
          _FakeInvites(RealmInvite.fromJson(_json(status: 'revoked')));
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      expect(find.text('This invite was withdrawn.'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('a conference invite has a way in: Join conference, and the '
        'address to tap or copy', (tester) async {
      final opened = <Uri>[];
      final api = _FakeInvites(
          RealmInvite.fromJson(_json(type: 'conference', slug: 'team-sync')));
      await tester.pumpWidget(_app(api, openExternal: (uri) async {
        opened.add(uri);
        return true;
      }));
      await tester.pumpAndSettle();

      expect(find.text('Join conference'), findsOneWidget);
      expect(find.text('Accept'), findsNothing,
          reason: 'it is accepted in the lobby, where joining happens');
      expect(find.text('chatterloop.app/conference/team-sync'), findsOneWidget);

      await tester.tap(find.text('Join conference'));
      await tester.pump();
      expect(opened.single.toString(),
          'https://chatterloop.app/conference/team-sync?invite_token=tok1');

      await tester.tap(find.text('chatterloop.app/conference/team-sync'));
      await tester.pump();
      expect(opened, hasLength(2));
      expect(api.answers, isEmpty, reason: 'opening it answers nothing');
    });

    testWidgets('an accepted conference invite still says where to go',
        (tester) async {
      final api = _FakeInvites(RealmInvite.fromJson(
          _json(type: 'conference', slug: 'team-sync', status: 'accepted')));
      await tester.pumpWidget(_app(api, openExternal: (_) async => true));
      await tester.pumpAndSettle();
      expect(find.text('You accepted this invite.'), findsOneWidget);
      expect(find.text('Open conference'), findsOneWidget);
      expect(find.text('chatterloop.app/conference/team-sync'), findsOneWidget);
    });

    testWidgets('a declined conference invite offers no way in',
        (tester) async {
      final api = _FakeInvites(RealmInvite.fromJson(
          _json(type: 'conference', slug: 'team-sync', status: 'declined')));
      await tester.pumpWidget(_app(api, openExternal: (_) async => true));
      await tester.pumpAndSettle();
      expect(find.text('Open conference'), findsNothing);
      expect(find.text('chatterloop.app/conference/team-sync'), findsNothing);
    });

    testWidgets('a broken link, or a join request, says it cannot open',
        (tester) async {
      await tester.pumpWidget(_app(_FakeInvites(null)));
      await tester.pumpAndSettle();
      expect(find.text("This invite can't be opened"), findsOneWidget);

      await tester.pumpWidget(
          _app(_FakeInvites(RealmInvite.fromJson(_json(kind: 'request')))));
      await tester.pumpAndSettle();
      expect(find.text("This invite can't be opened"), findsOneWidget);
    });
  });
}
