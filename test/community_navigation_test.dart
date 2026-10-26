import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_tagging.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/views/communities/community_widgets.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const community = Community(
    realmId: 'club',
    entityId: 'club-entity',
    name: 'Photography Club',
    isVerified: true);

void main() {
  for (final type in ['profile', 'cover_photo']) {
    testWidgets('community $type update author opens the community profile',
        (tester) async {
      final post = PostPreview.fromJson({
        'post_id': 'community-media-$type',
        'content_type': type,
        'entity': {
          'id': 'club-entity',
          'type': 'realm',
          'details': {
            'realm_id': 'club',
            'type': 'community',
            'first_name': 'Photography Club',
            'username': 'photography-club',
            'is_badged': true,
          },
        },
        'community': {
          'realm_id': 'club',
          'entity_id': 'club-entity',
          'name': 'Photography Club',
          'is_verified': true,
        },
      });
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(body: PostCard(post: post))),
        GoRoute(
            path: '/communities/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Profile ${state.pathParameters['id']}'))),
        GoRoute(
            path: '/realm/:id',
            builder: (_, __) => const Scaffold(body: Text('Wrong page'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
          theme: buildCLTheme(Brightness.light), routerConfig: router));
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.text('Follow'), findsNothing);
      expect(find.text('Open chat'), findsNothing);
      await tester.tap(find.text('Photography Club').first);
      await tester.pumpAndSettle();
      expect(find.text('Profile club'), findsOneWidget);
      expect(find.text('Wrong page'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('directory uses the server item and its name opens the profile',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: SizedBox(
                  width: 180,
                  height: 180 / 0.78,
                  child: CommunityDirectoryCard(
                      community: community,
                      onOpen: () => context.push('/communities/club'))))),
      GoRoute(
          path: '/communities/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Profile ${state.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.tap(find.text('Photography Club'));
    await tester.pumpAndSettle();
    expect(find.text('Profile club'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inline destination name has a working leaf text link and centered markers',
      (tester) async {
    final post = PostPreview.fromJson({
      'post_id': 'post',
      'entity': null,
      'is_anonymous': true,
      'community': {
        'realm_id': 'club',
        'entity_id': 'club-entity',
        'name': 'Photography Club',
        'is_verified': true
      }
    });
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: Text.rich(TextSpan(
                  children: postDestinationSpans(context, post,
                      baseStyle: const TextStyle(fontSize: CLType.title),
                      linkColor: Colors.blue))))),
      GoRoute(
          path: '/communities/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Profile ${state.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    final finder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('posted in'));
    final span = tester.widget<RichText>(finder).text as TextSpan;
    final destination = span.children!.last as TextSpan;
    expect(
        destination.children!
            .whereType<WidgetSpan>()
            .every((s) => s.alignment == PlaceholderAlignment.baseline),
        isTrue);
    await tester.tap(find.text('Photography Club'));
    await tester.pumpAndSettle();
    expect(find.text('Profile club'), findsOneWidget);
  });

  testWidgets('community search result opens its profile without group actions',
      (tester) async {
    final realm = SearchRealmResult.fromJson({
      'id': 'club',
      'entity_id': 'club-entity',
      'display_name': 'Photography Club',
      'realm_type': 'community',
      'is_member': false,
      'members_count': 12
    });
    var joined = false;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: SearchRealmCard(
                  realm: realm,
                  followBusy: false,
                  joinBusy: false,
                  onToggleFollow: (_) {},
                  onJoinGroup: (_) => joined = true,
                  onOpen: (realm) => openSearchRealm(context, realm)))),
      GoRoute(
          path: '/communities/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Profile ${state.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    expect(find.text('Join'), findsNothing);
    expect(find.text('Open chat'), findsNothing);
    expect(find.byIcon(Icons.groups_outlined), findsWidgets);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Profile club'), findsOneWidget);
    expect(joined, isFalse);
  });
}
