import 'dart:convert';
import 'package:chatterloop_app/core/requests/invites_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/communities/community_profile_view.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/post_sse_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/views/communities/communities_view.dart';
import 'package:chatterloop_app/views/communities/create_community_view.dart';

class FixtureCommunityApi extends CommunityApi {
  final queries = <String>[];
  bool fail = false;
  int memberLoads = 0;
  bool member = false,
      pending = false,
      private = true,
      owner = false,
      denied = false;
  int postLoads = 0;
  int creations = 0;
  final postsFixture =
      jsonDecode(File('test/fixtures/community_stage1.json').readAsStringSync())
          as Map<String, dynamic>;
  @override
  Future<Community> create(
      {required String name,
      required String slug,
      String description = '',
      bool isPrivate = false}) async {
    creations++;
    return Community(
        realmId: 'club', entityId: 'club-entity', name: name, slug: slug);
  }

  @override
  Future<Community> detail(String id) async {
    if (denied) {
      throw DioException(
          requestOptions: RequestOptions(path: '/community'),
          response: Response(
              requestOptions: RequestOptions(path: '/community'),
              statusCode: 403));
    }
    return Community(
        realmId: 'club',
        entityId: 'club-entity',
        name: 'Photography Club',
        isPrivate: private,
        isMember: member,
        requestPending: pending,
        myRole: owner ? 'owner' : null,
        description:
            'Share photos, learn together, and find our next photo walk.',
        memberCount: 248,
        isVerified: true);
  }

  @override
  Future<PagedResult<PostPreview>> posts(String id, {int page = 1}) async {
    postLoads++;
    return PagedResult(count: 1, hasNext: false, results: [
      PostPreview.fromJson(postsFixture['anonymous_owner']).applyPatch({
        'community': {
          'realm_id': id,
          'entity_id': 'club-entity',
          'name': 'Photography Club',
          'is_private': true,
          'is_member': member,
          'is_verified': true
        }
      })
    ]);
  }

  @override
  Future<PagedResult<RealmPerson>> members(String id, {int page = 1}) async {
    memberLoads++;
    if (!member) {
      throw DioException(
          requestOptions: RequestOptions(path: '/members'),
          response: Response(
              requestOptions: RequestOptions(path: '/members'),
              statusCode: 401));
    }
    return PagedResult.empty();
  }

  @override
  Future<CommunityMembership> join(String id) async {
    if (private) {
      pending = true;
    } else {
      member = true;
    }
    return CommunityMembership(isMember: member, requestPending: pending);
  }

  @override
  Future<CommunityMembership> leave(String id) async {
    member = false;
    pending = false;
    return const CommunityMembership(isMember: false);
  }

  @override
  Future<PagedResult<Community>> discover(
      {String search = '', bool joined = false, int page = 1}) async {
    queries.add('$joined:$search:$page');
    if (fail) throw Exception('offline');
    return PagedResult(count: 1, hasNext: page == 1, results: [
      Community(
          realmId: 'club-$page',
          entityId: 'club-entity',
          name: page == 1 ? 'Photography Club' : 'Weekend Hikers',
          description: page == 1
              ? 'Share photos and discover a new perspective.'
              : 'Find trails and company for the weekend.',
          isPrivate: page != 1,
          isMember: joined,
          memberCount: page == 1 ? 248 : 86)
    ]);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'create form separates labels, hints and entered text in ${brightness.name}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(brightness),
        home: CreateCommunityView(api: FixtureCommunityApi()),
      ));
      final description = find.byType(TextFormField).at(2);
      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Description')).bottom,
          lessThan(tester.getRect(description).top));
      final palette = cl(tester.element(find.byType(CreateCommunityView)));
      final hint = find.text('Share what your community is about.');
      expect(hint, findsOneWidget);
      expect(tester.getRect(hint).top,
          lessThan(tester.getRect(description).center.dy));
      await tester.enterText(description, 'A place to share photographs.');
      await tester.pump();
      final editable = tester.widget<EditableText>(find.descendant(
          of: description, matching: find.byType(EditableText)));
      expect(editable.style.color, palette.text);
      expect(editable.style.fontSize, CLType.bodySm);
      expect(editable.style.color, isNot(palette.text3));
    });
  }

  testWidgets('community composer fits narrow screens with standard type sizes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const community = Community(
      realmId: 'club',
      entityId: 'club-entity',
      isMember: true,
      name: 'Photography and creative neighborhood community',
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () =>
                        showCreatePostSheet(context, community: community),
                    child: const Text('Open composer'),
                  ))),
    ));
    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    final destination = find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.textSpan?.toPlainText().startsWith('Post in ') == true);
    expect(tester.widget<Text>(destination).style?.fontSize, CLType.label);
    expect(tester.getRect(find.byType(TextField).first).bottom,
        lessThan(tester.getRect(destination).top));
    expect(tester.widget<Text>(find.text('Post anonymously')).style?.fontSize,
        CLType.label);
    await tester.tap(find.text('Post anonymously'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('community profile sections switch without changing membership',
      (tester) async {
    final api = FixtureCommunityApi()..member = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: CommunityProfileView(id: 'club', api: api),
    ));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsNothing);
    expect(find.byType(ProfileComposerCard), findsOneWidget);
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Member list is not available.'), findsOneWidget);
    expect(api.member, isTrue);
  });

  testWidgets('leaving a community requires confirmation', (tester) async {
    final api = FixtureCommunityApi()..member = true;
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(id: 'club', api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Leave community'));
    await tester.tap(find.text('Leave community'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.member, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.member, isTrue);
    await tester.tap(find.text('Leave community'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Leave community')));
    await tester.pumpAndSettle();
    expect(api.member, isFalse);
  });

  test('community feed and roster honor the supplied identity snapshot',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'count': 0, 'next': null, 'results': []}));
      }));
    final api = CommunityApi(dio: dio, authToken: 'snapshot-token');
    await api.posts('club');
    await api.members('club');
    expect(requests.map((request) => request.extra['authToken']),
        everyElement('snapshot-token'));
  });
  testWidgets(
      'public visitors read posts without requesting forbidden member roster',
      (tester) async {
    final api = FixtureCommunityApi()..private = false;
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(id: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(api.postLoads, 1);
    expect(api.memberLoads, 0);
    expect(find.text('Join community'), findsOneWidget);
    expect(find.text('Could not load community.'), findsNothing);
  });
  setUp(() =>
      FlutterSecureStorage.setMockInitialValues({'token': 'fixture-token'}));
  test('community request review queries the existing request kind', () async {
    final dio = ApiClient.userService.dio;
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'status': true, 'result': []}));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await InvitesApi().pending('club', kind: 'request');
    expect(requests.last.queryParameters,
        {'realm_id': 'club', 'kind': 'request', 'status': 'pending'});
  });
  testWidgets('private cached cards hide immediately on access invalidation',
      (tester) async {
    final api = FixtureCommunityApi();
    final post = PostPreview.fromJson(api.postsFixture['anonymous_owner']);
    final dio = ApiClient.userService.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 403)));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: PostCard(post: post))));
    expect(find.textContaining('Anonymous member', findRichText: true),
        findsOneWidget);
    communityChanges.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('Anonymous member', findRichText: true),
        findsNothing);
    expect(find.text('Community post unavailable'), findsOneWidget);
  });
  testWidgets(
      'private visitor can request and cancel without fetching protected posts',
      (tester) async {
    final api = FixtureCommunityApi();
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(id: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(api.postLoads, 0);
    expect(find.text('This community is private'), findsOneWidget);
    await tester.tap(find.text('Request to join'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel request'), findsOneWidget);
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    expect(find.text('Request to join'), findsOneWidget);
    expect(api.postLoads, 0);
  });
  testWidgets('access loss clears previously visible private contributions',
      (tester) async {
    final api = FixtureCommunityApi()..member = true;
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(id: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(api.postLoads, 1);
    api.denied = true;
    communityChanges.value++;
    await tester.pumpAndSettle();
    expect(find.byType(ProfileComposerCard), findsNothing);
    expect(
        find.text('This community is unavailable or your access has changed.'),
        findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Anonymous member', findRichText: true),
        findsNothing);
  });
  testWidgets(
      'community profile composer has protected destination and anonymous choice',
      (tester) async {
    final api = FixtureCommunityApi()..member = true;
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(id: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileComposerCard), findsOneWidget);
    await tester
        .ensureVisible(find.text('Share something with Photography Club…'));
    await tester.tap(find.text('Share something with Photography Club…'));
    await tester.pumpAndSettle();
    expect(find.text('Post anonymously'), findsOneWidget);
    expect(find.text('Only members of this community can see this post.'),
        findsOneWidget);
    expect(find.text('Who can see this post?'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Photography Club'), findsNothing);
    await tester.tap(find.text('Post anonymously'));
    await tester.pumpAndSettle();
    expect(find.text('Anonymous member'), findsOneWidget);
  });
  test('anonymous typing projection discards identifying actor fields', () {
    final event = PostActivityEvent.fromFrame(jsonEncode({
      'auth': true,
      'status': true,
      'result': {
        'post_id': 'post',
        'event_type': 'typing',
        'is_anonymous': true,
        'entity': {
          'entity_id': 'secret',
          'name': 'Secret Name',
          'handle': 'secret'
        }
      }
    }));
    expect(event!.actor!.name, 'Anonymous member');
    expect(event.actor!.handle, isNull);
    expect(event.actor!.entityId, isNot('secret'));
  });
  test('community comments transmit explicit anonymous identity', () async {
    final dio = ApiClient.userService.dio;
    final requests = <RequestOptions>[];
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: {'status': true}));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await NewsfeedApi()
        .addCommentRequest(postId: 'post', text: 'Hello', isAnonymous: true);
    expect(requests.last.data['is_anonymous'], true);
    await NewsfeedApi().addCommentRequest(postId: 'post', text: 'Ordinary');
    expect(requests.last.data.containsKey('is_anonymous'), false);
  });
  testWidgets(
      'directory searches, switches joined filter, paginates and retries',
      (tester) async {
    final api = FixtureCommunityApi();
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunitiesView(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Photography Club', findRichText: true),
        findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(api.queries.last, 'false::1');
    await tester.tap(find.text('Your communities'));
    await tester.pumpAndSettle();
    expect(api.queries.last, 'true::1');
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(api.queries.last, 'false::1');
    await tester.enterText(find.byType(TextField), 'photo');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.queries.last, 'false:photo:1');
    await tester.scrollUntilVisible(find.text('Load more'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Weekend Hikers', findRichText: true),
        findsOneWidget);
    api.fail = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your communities'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Photography Club', findRichText: true),
        findsNothing);
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Photography Club', findRichText: true),
        findsOneWidget);
  });
  testWidgets('create blocks omitted and whitespace-only community slugs',
      (tester) async {
    for (final slug in ['', '   ']) {
      final api = FixtureCommunityApi();
      await tester.pumpWidget(MaterialApp(
          key: ValueKey(slug),
          theme: buildCLTheme(Brightness.light),
          home: CreateCommunityView(api: api)));
      await tester.enterText(find.byType(TextFormField).first, 'Readers');
      await tester.enterText(find.byType(TextFormField).at(1), slug);
      await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Create community'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(FilledButton, 'Create community'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Enter a community slug'), -200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Enter a community slug'), findsOneWidget);
      expect(api.creations, 0);
    }
  });
  testWidgets('create requires a name and exposes privacy explicitly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CreateCommunityView(api: FixtureCommunityApi())));
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Create community'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(FilledButton, 'Create community'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enter a community name'), -200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Enter a community name'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
  });
}
