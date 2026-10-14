import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/entity_api.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_menu_popover.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redux/redux.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/views/user/user_menu_view.dart';

void main() {
  late List<Interceptor> interceptors;

  setUp(() {
    // Resolve just the remote list request; the real menu and Redux state run.
    final dio = ApiClient.userService.dio;
    interceptors = List.of(dio.interceptors);
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {
        'count': 0,
        'next': null,
        'previous': null,
        'results': [],
      }));
    }));
  });

  tearDown(() {
    ApiClient.userService.dio.interceptors
      ..clear()
      ..addAll(interceptors);
  });

  test('account list still includes other pages while acting as a page',
      () async {
    final dio = ApiClient.userService.dio;
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final data = options.path == '/api/user/entity/pages'
          ? {
              'status': true,
              'result': {
                'personal_entity_id': 'personal',
                'pages': [
                  {
                    'realm_id': 'first',
                    'entity_id': 'entity-first',
                    'name': 'First page',
                    'slug': 'first-page',
                    'profile': null,
                    'role': 'admin'
                  },
                  {
                    'realm_id': 'second',
                    'entity_id': 'entity-second',
                    'name': 'Second page',
                    'slug': 'second-page',
                    'profile': null,
                    'role': 'owner'
                  },
                ]
              }
            }
          : {
              'count': 1,
              'next': null,
              'previous': null,
              'results': [
                {
                  'id': 'first',
                  'name': 'First page',
                  'type': 'page',
                  'is_admin': true,
                  'profile': null,
                  'slug': 'first-page'
                },
              ]
            };
      handler.resolve(Response(requestOptions: options, data: data));
    }));
    final pages = await EntityApi().getMyRealmsRequest();
    expect(pages.map((page) => page.id).toList(), ['first', 'second']);
    expect(pages.last.name, 'Second page');
  });

  testWidgets('account screen fits long names and opens profile and settings',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName = 'Bartholomew Maximilian Villaverde-Santos';
    final store = Store<AppState>((state, action) => state,
        initialState: AppState(
            userAuth: UserAuth(
                true,
                UserAccount('account', 'bartholomew', longName, '', 'L', null,
                    true, true, null, null, null, null,
                    personalEntityId: 'personal'))));
    final router = GoRouter(initialLocation: '/user', routes: [
      GoRoute(
          path: '/user',
          builder: (_, __) => const Scaffold(body: UserMenuView())),
      GoRoute(
          path: '/user/:handle',
          builder: (_, state) => Scaffold(
              body: Text('Profile: ${state.pathParameters["handle"]}'))),
      GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Account settings'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(StoreProvider<AppState>(
        store: store,
        child: MaterialApp.router(
            theme: buildCLTheme(Brightness.light), routerConfig: router)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('$longName L').first);
    await tester.pumpAndSettle();
    expect(find.text('Profile: bartholomew'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Account settings'), findsOneWidget);
  });

  test('older services still expose administered pages through the fallback',
      () async {
    final dio = ApiClient.userService.dio;
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/api/user/entity/pages') {
        handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 404),
            type: DioExceptionType.badResponse));
        return;
      }
      handler.resolve(Response(requestOptions: options, data: {
        'count': 2,
        'next': null,
        'previous': null,
        'results': [
          {
            'id': 'admin-page',
            'name': 'Admin page',
            'type': 'page',
            'is_admin': true
          },
          {
            'id': 'followed-page',
            'name': 'Followed page',
            'type': 'page',
            'is_admin': false
          },
        ]
      }));
    }));
    final pages = await EntityApi().getMyRealmsRequest();
    expect(pages.map((page) => page.id).toList(), ['admin-page']);
  });

  for (final fullPage in [false, true]) {
    final surface = fullPage ? 'user page' : 'popover';
    testWidgets('80 switchable accounts remain reachable in $surface',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dio = ApiClient.userService.dio;
      dio.interceptors.clear();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'status': true,
          'result': {
            'pages': [
              for (var i = 1; i <= 80; i++)
                {
                  'realm_id': 'page-$i',
                  'entity_id': 'entity-$i',
                  'name':
                      "Managed Account ${i.toString().padLeft(3, '0')} — A longer community page name",
                  'slug': 'page-$i',
                  'profile': null
                }
            ]
          }
        }));
      }));
      final store = Store<AppState>((state, action) => state,
          initialState: AppState(
              userAuth: UserAuth(
                  true,
                  UserAccount('account', 'ada', 'Ada', '', 'L', null, true,
                      true, null, null, null, null,
                      personalEntityId: 'personal'))));
      final anchor = GlobalKey();
      final router = GoRouter(initialLocation: '/source', routes: [
        GoRoute(
            path: '/source',
            builder: (_, __) => fullPage
                ? const Scaffold(body: UserMenuView())
                : Scaffold(
                    body: Builder(
                        builder: (context) => Align(
                            alignment: Alignment.topRight,
                            child: SizedBox(
                                key: anchor,
                                width: 44,
                                height: 44,
                                child: IconButton(
                                    icon: const Icon(Icons.person),
                                    onPressed: () {
                                      showUserMenuPopover(context,
                                          anchorKey: anchor,
                                          onOpenProfile: () {},
                                          onLogout: () {});
                                    })))))),
        GoRoute(
            path: '/switching',
            builder: (_, __) =>
                const Scaffold(body: Text('Switch account destination'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(StoreProvider<AppState>(
          store: store,
          child: MaterialApp.router(
              theme: buildCLTheme(Brightness.light), routerConfig: router)));
      await tester.pumpAndSettle();
      if (!fullPage) {
        await tester.tap(find.byIcon(Icons.person));
        await tester.pumpAndSettle();
      }
      final scroll = find.byType(SingleChildScrollView).first;
      await tester.drag(scroll, const Offset(0, -6000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Logout'));
      await tester.pumpAndSettle();
      final logoutRect = tester.getRect(find.text('Logout'));
      expect(logoutRect.top, greaterThanOrEqualTo(0));
      expect(logoutRect.bottom, lessThanOrEqualTo(640));
      if (fullPage) {
        await tester.ensureVisible(find.text('Apps'));
        expect(tester.getRect(find.text('Apps')).top, greaterThanOrEqualTo(0));
      } else {
        await tester.ensureVisible(find.text('Settings'));
        expect(
            tester.getRect(find.text('Settings')).top, greaterThanOrEqualTo(0));
      }
      final last =
          find.text('Managed Account 080 — A longer community page name');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      final rect = tester.getRect(last);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.text('Switch account destination'), findsOneWidget);
    });
  }

  for (final size in [
    const Size(360, 640),
    const Size(240, 320),
    const Size(640, 280)
  ]) {
    testWidgets('header menu stays visible below its avatar at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = Store<AppState>((state, action) => state,
          initialState: AppState(
              userAuth: UserAuth(
                  true,
                  UserAccount('account', 'ada', 'Ada', '', 'L', null, true,
                      true, null, null, null, null,
                      personalEntityId: 'personal'))));
      final anchor = GlobalKey();
      var profileOpened = false;
      await tester.pumpWidget(StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(
              body: Builder(
                  builder: (context) => Align(
                        alignment: Alignment.topRight,
                        child: SizedBox(
                          key: anchor,
                          width: 44,
                          height: 44,
                          child: IconButton(
                              icon: const Icon(Icons.person),
                              onPressed: () {
                                showUserMenuPopover(context,
                                    anchorKey: anchor,
                                    onOpenProfile: () => profileOpened = true,
                                    onLogout: () {});
                              }),
                        ),
                      ))),
        ),
      ));
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final profile = find.text('Ada L').first;
      final rect = tester.getRect(profile);
      expect(rect.top, greaterThanOrEqualTo(44));
      expect(rect.bottom, lessThan(size.height));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(profileOpened, isTrue);
      expect(find.text('SWITCH ACCOUNT'), findsNothing);
    });
  }
}
