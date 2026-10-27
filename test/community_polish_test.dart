import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_app_shortcuts.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/views/communities/communities_view.dart';
import 'package:chatterloop_app/views/communities/community_profile_view.dart';
import 'package:chatterloop_app/views/communities/community_widgets.dart';
import 'package:chatterloop_app/views/communities/create_community_view.dart';
import 'package:chatterloop_app/views/servers/server_channels_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'community_flows_test.dart' show FixtureCommunityApi;

class DirectoryFixtureApi extends FixtureCommunityApi {
  int joins = 0, cancellations = 0;
  DirectoryFixtureApi(bool privateCommunity) {
    private = privateCommunity;
  }
  @override
  Future<PagedResult<Community>> discover(
          {String search = '',
          bool joined = false,
          int page = 1,
          List<String> taggedEntityIds = const []}) async =>
      PagedResult(count: 1, hasNext: false, results: [
        Community(
            realmId: 'club',
            entityId: 'club-entity',
            name: 'Photography Club',
            isPrivate: private,
            isMember: member,
            requestPending: pending)
      ]);
  @override
  Future<CommunityMembership> join(String id) {
    joins++;
    return super.join(id);
  }

  @override
  Future<CommunityMembership> leave(String id,
      {bool cancelRequestOnly = false}) {
    if (cancelRequestOnly) cancellations++;
    return super.leave(id, cancelRequestOnly: cancelRequestOnly);
  }
}

class MemberFixtureApi extends FixtureCommunityApi {
  final RealmPerson person;
  MemberFixtureApi(this.person) {
    member = true;
  }
  @override
  Future<PagedResult<RealmPerson>> members(String id, {int page = 1}) async =>
      PagedResult(count: 1, hasNext: false, results: [person]);
}

void main() {
  for (final privateCommunity in [false, true]) {
    testWidgets('directory acts directly for private=$privateCommunity',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = DirectoryFixtureApi(privateCommunity);
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: CommunitiesView(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(
          find.text(privateCommunity ? 'Request to join' : 'Join community'));
      await tester.pumpAndSettle();
      expect(api.joins, 1);
      if (privateCommunity) {
        expect(find.text('Cancel request'), findsOneWidget);
        await tester.tap(find.text('Cancel request'));
        await tester.pumpAndSettle();
        expect(api.cancellations, 1);
        expect(find.text('Request to join'), findsOneWidget);
      } else {
        expect(find.text('Open'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  setUp(() =>
      FlutterSecureStorage.setMockInitialValues({'token': 'fixture-token'}));

  testWidgets('create stays disabled until name and slug contain text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CreateCommunityView(api: FixtureCommunityApi())));
    CLBtn submit() =>
        tester.widget<CLBtn>(find.widgetWithText(CLBtn, 'Create community'));
    expect(submit().onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), 'Readers');
    await tester.enterText(find.byType(TextField).at(1), '   ');
    await tester.pump();
    expect(submit().onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(1), 'readers');
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.pump();
    expect(submit().onPressed, isNull);
  });

  testWidgets('private community members can open the protected share composer',
      (tester) async {
    final api = FixtureCommunityApi()..member = true;
    final post =
        PostPreview.fromJson(api.postsFixture['anonymous_owner']).applyPatch({
      'community': {
        'realm_id': 'club',
        'entity_id': 'club-entity',
        'name': 'Photography Club',
        'is_private': true,
        'is_member': true
      }
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: PostCard(post: post))));
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share post'), findsOneWidget);
    expect(find.text('Post anonymously'), findsOneWidget);
    expect(find.text('Send in message'), findsNothing);
    expect(find.text('Add to Moment'), findsNothing);
  });

  testWidgets('profile composer uses only its existing bottom spacing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(
            id: 'club', api: FixtureCommunityApi()..member = true)));
    await tester.pumpAndSettle();
    final gap = tester.getRect(find.byType(PostItem).first).top -
        tester.getRect(find.byType(ProfileComposerCard)).bottom;
    expect(gap, lessThanOrEqualTo(2));
    expect(gap, greaterThanOrEqualTo(0));
  });

  testWidgets('public visitor posts keep a small header gap without a composer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityProfileView(
            id: 'club', api: FixtureCommunityApi()..private = false)));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileComposerCard), findsNothing);
    expect(
        tester.getRect(find.byType(PostItem).first).top -
            tester.getRect(find.byType(CommunitySectionTabs)).bottom,
        10);
  });

  testWidgets('private nonmembers cannot open the share composer',
      (tester) async {
    final api = FixtureCommunityApi();
    final post =
        PostPreview.fromJson(api.postsFixture['anonymous_owner']).applyPatch({
      'community': {
        'realm_id': 'club',
        'entity_id': 'club-entity',
        'name': 'Photography Club',
        'is_private': true,
        'is_member': false
      }
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: PostCard(post: post))));
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share post'), findsNothing);
  });

  for (final kind in ['user', 'realm', 'bot']) {
    testWidgets(
        '$kind community member name is bold, marked and opens its profile',
        (tester) async {
      final api = MemberFixtureApi(RealmPerson(
          entityId: 'member',
          accountId: 'member',
          displayName: 'Mika',
          handle: 'mika',
          entityType: kind,
          realmType: kind == 'realm' ? 'page' : null,
          isVerified: true));
      final route =
          '/${kind == 'user' ? 'user' : kind == 'realm' ? 'realm' : 'bot'}/mika';
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => CommunityProfileView(id: 'club', api: api)),
        GoRoute(
            path: route,
            builder: (_, __) => const Scaffold(body: Text('Member profile'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
          theme: buildCLTheme(Brightness.light), routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Members').first);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Mika')).style!.fontWeight,
          FontWeight.w600);
      final memberRow =
          find.ancestor(of: find.text('Mika'), matching: find.byType(ListTile));
      expect(
          find.descendant(
              of: memberRow,
              matching: find
                  .byIcon(kind == 'bot' ? Icons.smart_toy : Icons.verified)),
          findsOneWidget);
      if (kind == 'realm') {
        expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
      }
      await tester.tap(find.text('Mika'));
      await tester.pumpAndSettle();
      expect(find.text('Member profile'), findsOneWidget);
    });
  }

  for (final pending in [false, true]) {
    testWidgets('private server destination respects pending=$pending',
        (tester) async {
      final mainDio = ApiClient.instance.dio;
      final userDio = ApiClient.userService.dio;
      final posts = <RequestOptions>[];
      final mainInterceptor =
          InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method != 'GET') {
          posts.add(request);
        }
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 401)));
      });
      final userInterceptor =
          InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method != 'GET') {
          posts.add(request);
        }
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: request.method != 'GET'
                ? {'status': true}
                : {
                    'data': {
                      'id': 'private-server',
                      'name': 'Private server',
                      'entity': 'server-entity',
                      'type': 'server',
                      'is_private': true,
                      'is_member': false,
                      'request_pending': pending
                    }
                  }));
      });
      mainDio.interceptors.insert(0, mainInterceptor);
      userDio.interceptors.insert(0, userInterceptor);
      addTearDown(() {
        mainDio.interceptors.remove(mainInterceptor);
        userDio.interceptors.remove(userInterceptor);
      });
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home:
              Scaffold(body: ServerChannelsPane(serverId: 'private-server'))));
      await tester.pumpAndSettle();
      expect(find.text('Join server'), findsNothing);
      expect(find.text(pending ? 'Cancel request' : 'Request to join'),
          findsOneWidget);
      if (!pending) {
        await tester.tap(find.text('Request to join'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel request'), findsOneWidget);
        expect(posts, hasLength(1));
        expect(posts.single.path, contains('invites'));
        expect(posts.single.method, 'POST');
      } else {
        await tester.tap(find.text('Cancel request'));
        await tester.pumpAndSettle();
        expect(find.text('Request to join'), findsOneWidget);
        expect(posts, hasLength(1));
        expect(posts.single.method, 'PATCH');
        expect(posts.single.data,
            {'realm_id': 'private-server', 'status': 'revoked'});
      }
    });
  }

  testWidgets('account Apps excludes the Chatterloop extension',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: UserAppShortcuts(onSettings: () {}))));
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Chatterloop Extension'), findsNothing);
  });
}
