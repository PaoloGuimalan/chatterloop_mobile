import 'dart:async';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/auth/auth_controller.dart';
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:chatterloop_app/models/notifications_models/community_notification_model.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/views/communities/community_notifications_view.dart';
import 'package:chatterloop_app/views/communities/community_requests_view.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> notificationFixture(String id,
        {String type = 'post_comment',
        String? status,
        String name = 'Maya Chen',
        String entityType = 'user',
        String? realmType,
        bool anonymous = false}) =>
    {
      'id': id,
      'type': type,
      'description': type == 'community_join_request'
          ? '$name requested to join the community.'
          : '${anonymous ? 'An anonymous member' : name} ${type == 'post_comment' ? 'commented on' : 'reacted to'} the community’s cover photo.',
      'actor': {
        'id': 'entity-$id',
        'type': entityType,
        'details': {
          'id': 'account-$id',
          'first_name': realmType == null ? name : '',
          'name': name,
          'username': 'maya',
          'is_verified': true,
          'type': realmType
        }
      },
      'is_anonymous': anonymous,
      'created_at': '2026-10-01T08:00:00Z',
      'request_id': status == null ? null : 'request-$id',
      'request_status': status,
      'post_id': status == null ? 'photo-$id' : null,
      'anchor': type == 'post_comment' ? 'comment-$id' : null,
    };

CommunityNotificationsPage fixturePage(List<Map<String, dynamic>> rows,
        {bool next = false, int revision = 7}) =>
    CommunityNotificationsPage.fromJson({
      'count': 12,
      'next': next ? '/next' : null,
      'results': rows,
      'activity_revision': revision,
    });

class FixtureNotificationsApi extends CommunityApi {
  final loads = <int>[];
  final acknowledgements = <int>[];
  final acknowledgedIds = <List<String>>[];
  Future<CommunityNotificationsPage> Function(int)? respond;
  CommunityNotificationsPage page = fixturePage([]);
  bool ackFails = false;
  final details = <String>[];
  @override
  Future<Community> detail(String id) async {
    details.add(id);
    return const Community(
        realmId: 'canonical-club', entityId: 'club-entity', name: 'Club');
  }

  @override
  Future<CommunityNotificationsPage> notifications(String id, {int page = 1}) {
    loads.add(page);
    return respond?.call(page) ?? Future.value(this.page);
  }

  @override
  Future<void> acknowledgeNotifications(String id,
      {required int activityRevision,
      List<String> notificationIds = const []}) async {
    acknowledgements.add(activityRevision);
    acknowledgedIds.add(notificationIds);
    if (ackFails) throw StateError('Acknowledgement unavailable');
  }
}

UserAuth identity(String entity) => UserAuth(
    true,
    UserAccount('account', 'alex', 'Alex', '', 'Rivera', null, true, true, null,
        null, null, null,
        personalEntityId: entity));

Future<void> pumpNotifications(WidgetTester tester, FixtureNotificationsApi api,
    {Brightness brightness = Brightness.light, Key? boundaryKey}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
          theme: buildCLTheme(brightness),
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          home: const Scaffold())));
  navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => CommunityNotificationsView(realmId: 'club', api: api)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    CLAlerts.clear();
  });
  tearDown(CLAlerts.clear);

  test('new-post notices open the post and join notices remain informational',
      () {
    final post = CommunityNotification.fromJson({
      'id': 'post-notice',
      'type': 'community_post_created',
      'description': 'Maya posted in the community.',
      'post_id': 'new-post',
    });
    final joined = CommunityNotification.fromJson({
      'id': 'joined-notice',
      'type': 'community_member_joined',
      'description': 'Maya joined the community.',
    });
    expect(post.postRoute, '/post/new-post');
    expect(joined.postRoute, isNull);
    expect(joined.canReview, isFalse);
  });

  test(
      'parses entity identities, anonymity, statuses and safe post destinations',
      () {
    final page = CommunityNotificationsPage.fromJson({
      'count': 3,
      'next': '/next',
      'activity_revision': 42,
      'results': [
        notificationFixture('page',
            entityType: 'realm', realmType: 'page', name: 'Garden Page'),
        notificationFixture('bot', entityType: 'bot', name: 'Garden Bot'),
        notificationFixture('anonymous', anonymous: true),
      ]
    });
    expect(page.activityRevision, 42);
    expect(page.hasNext, isTrue);
    expect(page.results.first.actor!.isPage, isTrue);
    expect(page.results.first.actor!.entityId, 'entity-page');
    expect(page.results[1].actor!.isBot, isTrue);
    expect(page.results.last.actor, isNull);
    expect(
        page.results.first.postRoute, '/post/photo-page?anchor=comment-page');
    for (final status in ['accepted', 'declined', 'revoked']) {
      expect(
          CommunityNotification.fromJson(notificationFixture(status,
                  type: 'community_join_request', status: status))
              .canReview,
          isFalse);
    }
    expect(
        CommunityNotification.fromJson(
                notificationFixture('future', type: 'future_type'))
            .postRoute,
        isNull);
  });

  test(
      'transport uses user service paths, pagination and revision acknowledgement',
      () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'count': 0,
        'next': null,
        'results': [],
        'activity_revision': 9
      }));
    }));
    final api = CommunityApi(dio: dio, authToken: 'actor-token');
    final result = await api.notifications('club/id', page: 2);
    await api.acknowledgeNotifications('club/id',
        activityRevision: result.activityRevision!,
        notificationIds: ['notice-1']);
    expect(
        requests.first.path, '/api/realm/communities/club%2Fid/notifications');
    expect(requests.first.queryParameters, {'page': 2});
    expect(requests.first.extra['authToken'], 'actor-token');
    expect(requests.last.path,
        '/api/realm/communities/club%2Fid/notifications/read');
    expect(requests.last.data, {
      'activity_revision': 9,
      'notification_ids': ['notice-1']
    });
  });

  test(
      'app router matches stored community notification redirects as a pushed child',
      () {
    final auth = AuthController(appStore);
    final router = buildAppRouter(auth);
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    final match = router.configuration
        .findMatch(Uri.parse('/realm/club/manage/notifications'));
    expect(match.isError, isFalse);
    expect(match.pathParameters['slug'], 'club');
    expect(match.fullPath, '/realm/:slug/manage/notifications');
  });

  testWidgets('deduplicates pages and acknowledges each exact loaded page',
      (tester) async {
    final api = FixtureNotificationsApi()
      ..respond = (page) async => fixturePage(
          [notificationFixture('a'), if (page > 1) notificationFixture('b')],
          next: page == 1);
    await pumpNotifications(tester, api);
    expect(api.acknowledgements, [7]);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.loads, [1, 2]);
    expect(api.acknowledgements, [7, 7]);
    expect(api.acknowledgedIds, [
      ['a'],
      ['a', 'b']
    ]);
    expect(
        find.textContaining('Maya Chen', findRichText: true), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'identity changes clear old rows and reject stale responses and acknowledgements',
      (tester) async {
    final previous = appStore.state.userAuth;
    addTearDown(() => appStore.dispatch(DispatchModel(setUserAuthT, previous)));
    appStore.dispatch(DispatchModel(setUserAuthT, identity('one')));
    final pending = <Completer<CommunityNotificationsPage>>[];
    final api = FixtureNotificationsApi()
      ..respond = (_) {
        final completer = Completer<CommunityNotificationsPage>();
        pending.add(completer);
        return completer.future;
      };
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: CommunityNotificationsView(realmId: 'club', api: api)));
    expect(find.byType(CLNotificationRowSkeleton), findsNWidgets(6));
    appStore.dispatch(DispatchModel(setUserAuthT, identity('two')));
    await tester.pump();
    pending.first.complete(fixturePage(
        [notificationFixture('old', name: 'Old actor')],
        revision: 1));
    await tester.pump();
    expect(api.acknowledgements, isEmpty);
    pending.last.complete(fixturePage(
        [notificationFixture('new', name: 'New actor')],
        revision: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Old actor', findRichText: true), findsNothing);
    expect(
        find.textContaining('New actor', findRichText: true), findsOneWidget);
    expect(api.acknowledgements, [2]);
  });

  testWidgets(
      'SSE activity uses dedicated signal and request changes refresh too',
      (tester) async {
    final api = FixtureNotificationsApi();
    await pumpNotifications(tester, api);
    final before = communityChanges.value;
    await SseEvents().listen(
        SSEModel(event: 'community_notifications_changed', data: '{}'), true);
    await tester.pumpAndSettle();
    expect(communityChanges.value, before);
    expect(api.loads, [1, 1]);
    await SseEvents().listen(
        SSEModel(event: 'community_admin_preview_changed', data: '{}'), true);
    await tester.pumpAndSettle();
    expect(api.loads, [1, 1]);
    communityChanges.value++;
    await tester.pumpAndSettle();
    expect(api.loads, [1, 1, 1]);
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets(
      'load failure is distinct from empty and reports through global alerts',
      (tester) async {
    final api = FixtureNotificationsApi()
      ..respond = (_) async => throw StateError('offline');
    await pumpNotifications(tester, api);
    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
    expect(CLAlerts.active.value.single.type, CLAlertType.error);
    api.respond = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets('acknowledgement failure keeps activity and uses global alert',
      (tester) async {
    final api = FixtureNotificationsApi()
      ..page = fixturePage([notificationFixture('a')])
      ..ackFails = true;
    await pumpNotifications(tester, api);
    expect(
        find.textContaining('Maya Chen', findRichText: true), findsOneWidget);
    expect(CLAlerts.active.value.single.message,
        contains('mark community activity as read'));
  });

  testWidgets('losing access during pagination removes cached activity',
      (tester) async {
    final api = FixtureNotificationsApi()
      ..respond = (page) async {
        if (page == 1) {
          return fixturePage([notificationFixture('a')], next: true);
        }
        throw DioException(
            requestOptions: RequestOptions(path: '/notifications'),
            response: Response(
                requestOptions: RequestOptions(path: '/notifications'),
                statusCode: 403));
      };
    await pumpNotifications(tester, api);
    expect(
        find.textContaining('Maya Chen', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Maya Chen', findRichText: true), findsNothing);
    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(CLAlerts.active.value, isNotEmpty);
  });

  testWidgets('compact rows fit narrow screens with larger text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FixtureNotificationsApi()
      ..page = fixturePage([
        notificationFixture('a',
            name: 'A community with a very long display name',
            entityType: 'realm',
            realmType: 'community',
            type: 'community_join_request',
            status: 'pending'),
      ]);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: CommunityNotificationsView(realmId: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Review request'), findsOneWidget);
  });

  testWidgets('media row opens post with exact comment anchor', (tester) async {
    final api = FixtureNotificationsApi()
      ..page = fixturePage([notificationFixture('a')]);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              CommunityNotificationsView(realmId: 'club', api: api)),
      GoRoute(
          path: '/post/:id',
          builder: (_, state) => Scaffold(
              body: Text(
                  '${state.pathParameters['id']} ${state.uri.queryParameters['anchor']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Maya Chen', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('photo-a comment-a'), findsOneWidget);
  });

  testWidgets('review pending request opens existing join requests screen',
      (tester) async {
    final dio = ApiClient.userService.dio;
    String? requestsRealmId;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      requestsRealmId = request.queryParameters['realm_id']?.toString();
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'status': true, 'result': []}));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    final api = FixtureNotificationsApi()
      ..page = fixturePage([
        notificationFixture('a',
            type: 'community_join_request', status: 'pending'),
        notificationFixture('b',
            type: 'community_join_request', status: 'accepted'),
      ]);
    await pumpNotifications(tester, api);
    expect(find.text('Review request'), findsOneWidget);
    expect(find.textContaining('Approved'), findsOneWidget);
    await tester.tap(find.text('Review request'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityRequestsView), findsOneWidget);
    expect(api.details, ['club']);
    expect(requestsRealmId, 'canonical-club');
  });

  testWidgets('moderator gets community Notifications tile and pages do not',
      (tester) async {
    var kind = 'community';
    final dio = ApiClient.userService.dio;
    final interceptor = InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {
          'id': 'club',
          'name': 'Club',
          'type': kind,
          'my_role': 'moderator',
          'is_admin': kind != 'community'
        }
      }));
    });
    dio.interceptors.insert(0, interceptor);
    addTearDown(() => dio.interceptors.remove(interceptor));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const RealmManageScreen(slug: 'club')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    kind = 'page';
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const RealmManageScreen(key: ValueKey('page'), slug: 'club')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('actual notifications golden ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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
      final api = FixtureNotificationsApi()
        ..page = fixturePage([
          {
            ...notificationFixture('joined'),
            'type': 'community_member_joined',
            'description': 'Maya Chen joined the community.',
            'post_id': null,
            'request_id': null
          },
          {
            ...notificationFixture('posted'),
            'type': 'community_post_created',
            'description': 'Maya Chen posted in the community.',
            'post_id': 'new-post',
            'anchor': null
          },
          notificationFixture('join',
              type: 'community_join_request', status: 'pending'),
          notificationFixture('page',
              name: 'Garden Page', entityType: 'realm', realmType: 'page'),
          notificationFixture('anon', anonymous: true, type: 'post_reaction'),
          notificationFixture('bot',
              name: 'Garden Bot', entityType: 'bot', type: 'comment_reaction'),
          notificationFixture('accepted',
              name: 'Alex Rivera',
              type: 'community_join_request',
              status: 'accepted'),
        ], next: true);
      const boundary = ValueKey('community-notifications-preview');
      await pumpNotifications(tester, api,
          brightness: brightness, boundaryKey: boundary);
      expect(tester.takeException(), isNull);
      await expectLater(
          find.byKey(boundary),
          matchesGoldenFile(
              'goldens/community_notifications_${brightness.name}.png'));
    });
  }
}
