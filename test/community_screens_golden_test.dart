import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/views/search/post_preview_view.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/views/communities/communities_view.dart';
import 'package:chatterloop_app/views/communities/create_community_view.dart';
import 'package:chatterloop_app/views/communities/community_profile_view.dart';
import 'package:chatterloop_app/views/communities/community_requests_view.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'community_flows_test.dart' show FixtureCommunityApi;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('actual community screens ${brightness.name}', (tester) async {
      final previousAuth = appStore.state.userAuth;
      addTearDown(
          () => appStore.dispatch(DispatchModel(setUserAuthT, previousAuth)));
      appStore.dispatch(DispatchModel(
          setUserAuthT,
          UserAuth(
              true,
              UserAccount('fixture-account', 'alex', 'Alex', '', 'Rivera', null,
                  true, true, null, null, null, null,
                  personalEntityId: 'fixture-viewer'))));
      FlutterSecureStorage.setMockInitialValues({
        'token': JwtCodec.sign({'userID': 'fixture-viewer'})
      });
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await font.load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      final api = FixtureCommunityApi()
        ..member = true
        ..owner = true;
      final dio = ApiClient.userService.dio;
      var requests = true;
      final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
        if (request.path.contains('/preview/')) {
          handler.resolve(Response(
              requestOptions: request,
              statusCode: 200,
              data: api.postsFixture['anonymous_owner']));
          return;
        }
        if (request.path.endsWith('/comments')) {
          handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: {
            'count': 1,
            'next': null,
            'results': [api.postsFixture['comment']]
          }));
          return;
        }
        final realm = {
          'id': 'club',
          'realm_id': 'club',
          'entity': 'club-entity',
          'name': 'Photography Club',
          'type': 'community',
          'description': 'A place to share photos and learn together.',
          'is_private': true,
          'is_member': true,
          'is_admin': true,
          'my_role': 'owner',
          'is_verified': true,
          'members_count': 248
        };
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: request.path.contains('invites')
                ? {
                    'status': true,
                    'result': requests
                        ? [
                            {
                              'id': 'request-1',
                              'realm_id': 'club',
                              'realm_type': 'community',
                              'realm_name': 'Photography Club',
                              'kind': 'request',
                              'status': 'pending',
                              'purpose': 'join',
                              'invite_token': 'request-token',
                              'target_entity': {
                                'id': 'maya',
                                'type': 'user',
                                'details': {
                                  'username': 'maya',
                                  'first_name': 'Maya',
                                  'last_name': 'Chen'
                                }
                              }
                            }
                          ]
                        : []
                  }
                : {'data': realm}));
      });
      dio.interceptors.insert(0, interceptor);
      addTearDown(() => dio.interceptors.remove(interceptor));
      const root = ValueKey('native-community-preview');
      Future<void> screen(String name, Widget widget) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(RepaintBoundary(
            key: root,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigator,
                key: ValueKey(name),
                theme: buildCLTheme(brightness),
                home: const Scaffold())));
        navigator.currentState!
            .push(MaterialPageRoute<void>(builder: (_) => widget));
        await tester.pumpAndSettle();
        if (name == 'directory') {
          await tester.tap(find.text('Load more'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
            find.byKey(root),
            matchesGoldenFile(
                'goldens/community_${name}_${brightness.name}.png'));
      }

      await screen('directory', CommunitiesView(api: api));
      await screen('create', CreateCommunityView(api: api));
      await screen(
          'profile_member', CommunityProfileView(id: 'club', api: api));
      await tester.ensureVisible(find.text('About'));
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(root),
          matchesGoldenFile(
              'goldens/community_profile_about_${brightness.name}.png'));
      await tester.tap(find.text('Members').first);
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(root),
          matchesGoldenFile(
              'goldens/community_profile_members_${brightness.name}.png'));
      await screen('profile_private',
          CommunityProfileView(id: 'club', api: FixtureCommunityApi()));
      await screen('manage', const RealmManageScreen(slug: 'club'));
      await screen('requests', const CommunityRequestsView(realmId: 'club'));
      await screen(
          'profile_member', CommunityProfileView(id: 'club', api: api));
      await tester
          .ensureVisible(find.text('Share something with Photography Club…'));
      await tester.tap(find.text('Share something with Photography Club…'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).first, 'What did you capture this weekend?');
      await tester.tap(find.text('Post anonymously'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(root),
          matchesGoldenFile(
              'goldens/community_composer_${brightness.name}.png'));
      ReactionPalette.seed([
        Emoji(
            emojiId: 'love',
            content: '❤️',
            title: 'Love',
            theme: '#e94266',
            priority: 1),
        Emoji(
            emojiId: 'like',
            content: '👍',
            title: 'Like',
            theme: '#1c7def',
            priority: 2),
        Emoji(
            emojiId: 'wow',
            content: '😮',
            title: 'Wow',
            theme: '#e69500',
            priority: 3)
      ]);
      await screen(
          'interactions_named', const PostPreviewScreen(postId: 'anon-1'));
      await tester.tap(find.text('Comment anonymously'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(root),
          matchesGoldenFile(
              'goldens/community_interactions_${brightness.name}.png'));
      await tester.pumpWidget(RepaintBoundary(
          key: root,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              key: const ValueKey('reactions'),
              theme: buildCLTheme(brightness),
              home: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => showCommunityReactionPicker(context,
                              currentEmojiId: 'love', currentIsAnonymous: true),
                          child: const Text('Open reactions')))))));
      await tester.tap(find.text('Open reactions'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byKey(root),
          matchesGoldenFile(
              'goldens/community_reactions_${brightness.name}.png'));
      requests = false;
    });
  }
}
