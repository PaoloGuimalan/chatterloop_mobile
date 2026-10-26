import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/core/utils/post_updates.dart';
import 'package:chatterloop_app/core/utils/view_cache.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';

import 'package:dio/dio.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_edit.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/post_models/saved_post_model.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/models/user_models/moderation_detail_model.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_comments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_options.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';

final fixtures =
    jsonDecode(File('test/fixtures/community_stage1.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('community destination displays its name, kind and verification',
      (tester) async {
    for (final verified in [true, false]) {
      final json = Map<String, dynamic>.from(fixtures['named']);
      json['community'] = {
        ...Map<String, dynamic>.from(json['community']),
        'is_verified': verified,
      };
      // Author is unverified so its badge cannot satisfy the destination check.
      json['entity'] = null;
      json['is_anonymous'] = true;
      final post = PostPreview.fromJson(json);
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(body: PostCard(post: post, key: ValueKey(verified)))));
      final header = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((text) => text.text.toPlainText().contains('posted in'));
      expect(header.text.toPlainText(), contains('posted in'));
      expect(find.text('Weekend Makers'), findsOneWidget);
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.byIcon(Icons.verified),
          verified ? findsOneWidget : findsNothing);
    }
  });
  void actAs(String entityId) => appStore.dispatch(DispatchModel(
      setUserAuthT,
      UserAuth(
          true,
          UserAccount('account-1', 'viewer', 'Viewer', '', '', null, true, true,
              null, null, null, null,
              personalEntityId: entityId))));
  tearDown(() {
    actAs('');
    PostUpdates.instance.clear();
  });
  testWidgets(
      'server ownership permits anonymous text edits without an author identity',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues(
        {'token': 'anonymous-owner-token'});
    actAs('viewer-entity');
    final post = PostPreview.fromJson(fixtures['anonymous_owner']);
    final requests = <RequestOptions>[];
    final dio = ApiClient.userService.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'status': true,
        'post': {
          'post_id': post.postId,
          'caption': 'Edited anonymously',
          'is_edited': true
        }
      }));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => openPostEditor(context, post),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Anonymous member'), findsOneWidget);
    expect(find.text('Viewer'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Edited anonymously');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(requests.single.method, 'PUT');
    expect(requests.single.extra['authToken'], 'anonymous-owner-token');
    final resolved = PostUpdates.instance.resolve(post);
    expect(resolved.caption, 'Edited anonymously');
    expect(resolved.author.entityId, isEmpty);
    expect(resolved.isOwner, isTrue);
    expect(resolved.community!.entityId, 'community-entity-1');
  });
  testWidgets('anonymous self views stay excluded from engagement tracking',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    ViewCache.instance.resetForTest();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    actAs('viewer-entity');
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PostViewTracker(
                  post: PostPreview.fromJson(fixtures['anonymous_owner']),
                  child: const SizedBox.expand()))));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(await ViewCache.instance.snapshot('viewer-entity'), isEmpty);
      await ViewCache.instance.clear();
    });
    ViewCache.instance.resetForTest();
  });

  test('existing anonymous editor upload uses its community context', () {
    expect(
        postEditUploadContext(
            PostPreview.fromJson(fixtures['anonymous_owner'])),
        {'community_entity_id': 'community-entity-1', 'is_anonymous': true});
    expect(postEditUploadContext(PostPreview.fromJson(fixtures['ordinary'])),
        isNull);
    expect(
        postEditUploadContext(PostPreview.fromJson(fixtures['page'])), isNull);
  });
  test('metadata and viewer reaction identity survive updates', () {
    final post = PostPreview.fromJson(fixtures['anonymous_owner']);
    final updated = post
        .copyWith(entityReaction: 'love')
        .applyPatch({'caption': 'Changed'});
    expect(updated.community!.realmId, 'community-1');
    expect(updated.entityReactionIsAnonymous, isTrue);
    expect(updated.isAnonymous, isTrue);
    expect(updated.isOwner, isTrue);
    expect(
        updated.copyWith(clearEntityReaction: true).entityReactionIsAnonymous,
        isNull);
    final comment = PostComment.fromJson({
      ...fixtures['comment'] as Map<String, dynamic>,
      'entity_reaction': 'like',
      'entity_reaction_is_anonymous': false
    });
    final changed = comment.copyWith(entityReaction: 'love');
    expect(changed.entityReactionIsAnonymous, isFalse);
    expect(changed.isOwner, isTrue);
    expect(changed.community!.name, 'Weekend Makers');
    expect(
        changed.copyWith(clearEntityReaction: true).entityReactionIsAnonymous,
        isNull);
  });
  test('ordinary user/page authors remain intact; explicit server false wins',
      () {
    for (final key in ['ordinary', 'page', 'named']) {
      final post = PostPreview.fromJson(fixtures[key]);
      expect(post.author.canOpenProfile, isTrue);
      expect(post.author.isVerified, isTrue);
      expect(post.isAnonymous, isFalse);
    }
    final post = PostPreview.fromJson(fixtures['named']);
    expect(post.isOwnedBy(post.author.entityId), isFalse);
    expect(PostPreview.fromJson(fixtures['ordinary']).isOwnedBy('member-1'),
        isTrue);
  });
  test('saved/search/moderation null authors have no identity or picture', () {
    final post = fixtures['anonymous_owner'] as Map<String, dynamic>;
    final saved = SavedPost.fromJson({'id': 'save', 'post': post});
    final search = SearchPostResult.fromJson({...post, 'author': null});
    final moderation = ModerationContent.fromJson(post);
    expect(saved.author.displayName, 'Anonymous member');
    expect(saved.author.presenceEntityId, isNull);
    expect(saved.community!.name, 'Weekend Makers');
    expect(search.author.displayName, 'Anonymous member');
    expect(search.author.presenceEntityId, isNull);
    expect(search.author.isVerified, isFalse);
    expect(moderation.authorName, 'Anonymous member');
    expect(moderation.authorHandle, isNull);
    expect(moderation.authorPicture, isNull);
  });
  test('explicit anonymous flag redacts even a stale identity payload', () {
    final post = PostPreview.fromJson({
      ...fixtures['anonymous_owner'] as Map<String, dynamic>,
      'entity': fixtures['ordinary']['entity']
    });
    expect(post.author.entityId, isEmpty);
    expect(post.author.canOpenProfile, isFalse);
    expect(post.author.profile, isNull);
  });
  test('community transport parses lifecycle and preserves access errors',
      () async {
    final requests = <RequestOptions>[];
    var status = 200;
    dynamic body = {'status': true, 'result': fixtures['named']['community']};
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      final response =
          Response(requestOptions: request, statusCode: status, data: body);
      if (status >= 400) {
        handler.reject(DioException.badResponse(
            statusCode: status, requestOptions: request, response: response));
      } else {
        handler.resolve(response);
      }
    }));
    final api = CommunityApi(dio: dio);
    expect((await api.detail('weekend makers')).isMember, isTrue);
    expect(requests.last.path, '/api/realm/communities/weekend%20makers');
    await api.create(
        name: 'Weekend Makers', slug: ' weekend-makers ', isPrivate: true);
    expect(requests.last.method, 'POST');
    expect(requests.last.data['is_private'], isTrue);
    expect(requests.last.data['slug'], 'weekend-makers');
    final requestCount = requests.length;
    for (final slug in ['', '   ']) {
      await expectLater(
          api.create(name: 'Weekend Makers', slug: slug), throwsArgumentError);
    }
    expect(requests.length, requestCount);
    body = {
      'count': 1,
      'next': null,
      'results': [fixtures['named']['community']]
    };
    expect(
        (await api.discover(search: 'makers', joined: true, page: 2))
            .results
            .single
            .name,
        'Weekend Makers');
    expect(requests.last.queryParameters,
        {'search': 'makers', 'joined': 'true', 'page': 2});
    body = fixtures['private_join'];
    final pending = await api.join('community-1');
    expect(pending.requestPending, isTrue);
    expect(pending.isMember, isFalse);
    body = {'status': true, 'is_member': true};
    final joined = await api.join('community-1');
    expect(joined.isMember, isTrue);
    expect(joined.requestPending, isFalse);
    expect(requests.last.path, endsWith('/join'));
    body = {'status': true, 'is_member': false};
    expect((await api.leave('community-1')).isMember, isFalse);
    for (final code in [403, 404]) {
      status = code;
      body = fixtures[code == 403 ? 'forbidden' : 'not_found'];
      await expectLater(
          api.detail('missing'),
          throwsA(isA<DioException>()
              .having((e) => e.response!.statusCode, 'status', code)));
    }
  });
  test('emoji changes omit identity unless a boolean is deliberately supplied',
      () async {
    final dio = ApiClient.userService.dio;
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(
          Response(requestOptions: request, statusCode: 200, data: {}));
    });
    // Prepend so no credentials, nonce or network are needed for a transport assertion.
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    final api = NewsfeedApi();
    await api.setPostReactionRequest(
        postId: 'anon-1', emojiId: 'love', method: ReactionMethod.swap);
    expect(requests.last.data.containsKey('is_anonymous'), isFalse);
    await api.setCommentReactionRequest(
        commentId: 'comment-1',
        emojiId: 'love',
        method: ReactionMethod.swap,
        isAnonymous: false);
    expect(requests.last.data['is_anonymous'], isFalse);
    await api.setPostReactionRequest(
        postId: 'anon-1',
        emojiId: 'love',
        method: ReactionMethod.add,
        isAnonymous: true);
    expect(requests.last.data['is_anonymous'], isTrue);
  });
  testWidgets('anonymous owner keeps edit/delete and no audience override',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: PostCard(
                post: PostPreview.fromJson(fixtures['anonymous_owner'])))));
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Change audience'), findsNothing);
    expect(find.text('Report'), findsNothing);
  });
  testWidgets(
      'anonymous visitor gets report; private destination controls audience icon',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: PostCard(
                post: PostPreview.fromJson(fixtures['anonymous_visitor'])))));
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.public), findsNothing);
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit post'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Report'), findsOneWidget);
  });
  testWidgets('anonymous comment owner keeps delete', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: CommentRow(
                comment: PostComment.fromJson(fixtures['comment']),
                busy: false,
                onReact: () {},
                onDelete: () {}))));
    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('actual Stage 1 widgets ${brightness.name} preview',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(brightness),
          home: Scaffold(
              body: RepaintBoundary(
                  key: const ValueKey('stage1-preview'),
                  child: Builder(
                      builder: (context) => ColoredBox(
                          color: cl(context).bg,
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final key in [
                                      'ordinary',
                                      'page',
                                      'named',
                                      'anonymous_owner',
                                      'anonymous_visitor'
                                    ]) ...[
                                      Container(
                                          decoration: BoxDecoration(
                                              color: cl(context).surface,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                  color: cl(context).border)),
                                          child: PostCard(
                                              post: PostPreview.fromJson(
                                                  fixtures[key]))),
                                      const SizedBox(height: 10),
                                    ],
                                    CommentRow(
                                        comment: PostComment.fromJson(
                                            fixtures['comment']),
                                        busy: false,
                                        onReact: () {},
                                        onReply: () {},
                                        onDelete: () {}),
                                    const SizedBox(height: 12),
                                    CommentRow(
                                        comment: PostComment.fromJson(
                                            fixtures['named_comment']),
                                        busy: false,
                                        onReact: () {},
                                        onReply: () {}),
                                  ]))))))));
      await tester.pumpAndSettle();
      final avatars = tester
          .widgetList<CLAvatar>(find.byType(CLAvatar))
          .where((a) => a.kind == 'anonymous');
      expect(avatars, isNotEmpty);
      for (final avatar in avatars) {
        expect(avatar.entityId, isNull);
        expect(avatar.src, isNull);
      }
      await expectLater(find.byKey(const ValueKey('stage1-preview')),
          matchesGoldenFile('goldens/community_stage1_${brightness.name}.png'));
    });
  }

  test('null authors use a neutral anonymous projection', () {
    final post = PostPreview.fromJson(fixtures['anonymous_owner']);
    expect(post.author.displayName, 'Anonymous member');
    expect(post.author.entityId, isEmpty);
    expect(post.author.handle, isEmpty);
    expect(post.author.profile, isNull);
    expect(post.author.isVerified, isFalse);
  });
  test('server ownership survives anonymous rendering and patches', () {
    final post = PostPreview.fromJson(fixtures['anonymous_owner']);
    expect(
        isOwnPost(
            post.copyWith(isSaved: true).applyPatch({'caption': 'Edited'})),
        isTrue);
    expect(isOwnPost(PostPreview.fromJson(fixtures['anonymous_visitor'])),
        isFalse);
  });
  testWidgets('real anonymous post and comment render without a profile',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
          PostCard(post: PostPreview.fromJson(fixtures['anonymous_owner'])),
          CommentRow(
              comment: PostComment.fromJson(fixtures['comment']),
              busy: false,
              onReact: () {},
              onDelete: () {})
        ])))));
    await tester.pump();
    expect(find.textContaining('Anonymous member', findRichText: true),
        findsNWidgets(2));
    expect(tester.takeException(), isNull);
    final postText = tester.widget<RichText>(
        find.textContaining('Anonymous member', findRichText: true).first);
    final nameSpan = (postText.text as TextSpan).children!.first as TextSpan;
    expect(nameSpan.recognizer, isNull);
    final anonymousAvatars = tester
        .widgetList<CLAvatar>(find.byType(CLAvatar))
        .where((avatar) => avatar.kind == 'anonymous');
    for (final avatar in anonymousAvatars) {
      expect(avatar.entityId, isNull);
      expect(avatar.src, isNull);
    }
  });
}
