import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fleather/fleather.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/encryption_api.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:chatterloop_app/views/diary/diary_gate.dart';
import 'package:chatterloop_app/views/diary/diary_compose_view.dart';
import 'package:chatterloop_app/views/diary/diary_entry_view.dart';
import 'package:chatterloop_app/views/diary/locked_diary.dart';
import 'package:chatterloop_app/views/diary/diary_list_view.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/views/settings/passphrase_section.dart';

Map<String, dynamic> fixtureConfiguration({bool active = true}) => {
      'id': '11111111-1111-4111-8111-111111111111',
      'purpose': 'diary',
      'name': 'Personal journal',
      'entity_id': 'entity-vector',
      'user_id': 'user-vector',
      'is_active': active,
      'created_at': '2026-10-20T09:00:00Z',
      'revision': 1,
      'format_version': 1,
      'kdf_algorithm': 'argon2id',
      'kdf_parameters': PassphraseCrypto.parameters,
      'cipher_algorithm': 'aes-256-gcm',
      'salt': 'AAECAwQFBgcICQoLDA0ODw==',
      'verification_nonce': 'EBESExQVFhcYGRob',
      'verification_ciphertext':
          'D3h/e9M1tO+oc+WaZll42I07hZ+lFGH89ZMaBIkM2TKzS1NBLer7h8wFDrxCnva1dQZ4YAHVtXGcQbESkFf6mv85dcDLkZjqPYzsbCJ73F4ebKhqk39jUIvvNU8JiZLQc05xr3CxEIJ619iamKKB0rhIgwjnwxm5+IM=',
      'verification_aad':
          '["chatterloop.encryption.verification",1,"11111111-1111-4111-8111-111111111111","entity-vector","user-vector","diary"]',
    };
Map<String, dynamic> fixtureData({bool active = true}) => {
      'owner': {'entity_id': 'entity-vector', 'user_id': 'user-vector'},
      'supported_profile': PassphraseCrypto.profile,
      'consumer_capabilities': {
        'diary': {'format_version': 1}
      },
      'purposes': [
        {
          'purpose': 'diary',
          'label': 'Diary',
          'configurations': [fixtureConfiguration(active: active)],
          'active_configuration_id':
              active ? '11111111-1111-4111-8111-111111111111' : null,
          'scope_version': 'a' * 64
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Interceptor> previous;
  setUp(() {
    previous = List.of(ApiClient.userService.dio.interceptors);
    DiarySession.instance.clear();
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options,
            data: {'status': true, 'result': fixtureData()}));
      }));
  });
  tearDown(() {
    ApiClient.userService.dio.interceptors
      ..clear()
      ..addAll(previous);
    DiarySession.instance.clear();
  });

  test('encrypted row parsing cannot expose ciphertext to titles or search',
      () {
    final row = DiaryEntry.fromJson({
      'id': 'one',
      'is_encrypted': true,
      'title': '{ciphertext}',
      'content': '{ciphertext}'
    });
    expect(row.isLocked, isTrue);
    expect(row.title, isEmpty);
    expect(row.plainTextPreview, isEmpty);
  });
  test(
      'visit clearing overwrites retained key buffers and removes capabilities',
      () {
    final session = DiarySession.instance, key = List.filled(32, 9);
    session.install(fixtureData(), 'owner');
    session.addKey('11111111-1111-4111-8111-111111111111', key);
    expect(session.ready, isTrue);
    session.clear();
    expect(key, everyElement(0));
    expect(session.ready, isFalse);
    expect(session.canEncrypt, isFalse);
  });
  test(
      'public configuration failures propagate rather than becoming no active protection',
      () async {
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
              Response(requestOptions: options, data: {'status': false}))));
    await expectLater(EncryptionApi().load(), throwsFormatException);
  });
  test('old backend capabilities block encryption even with a verified key',
      () async {
    final data = fixtureData()..remove('consumer_capabilities');
    final session = DiarySession.instance;
    session.install(data, 'owner');
    session.addKey('11111111-1111-4111-8111-111111111111', List.filled(32, 1));
    await expectLater(
        session.encryptNew('Private', '<p>Words</p>'), throwsFormatException);
  });
  test('new entry encryption uses the freshly confirmed key', () async {
    final session = DiarySession.instance;
    session.install(fixtureData(), 'owner');
    session.addKey('11111111-1111-4111-8111-111111111111', List.filled(32, 1));
    final confirmed = List.filled(32, 2);
    final fields = await session.encryptNew(
        'Chosen title', '<p>Chosen writing</p>',
        confirmedKey: confirmed);
    expect(
        await PassphraseCrypto().decryptDiary(
            confirmed, 'entity-vector', 'user-vector', fields.$1, fields.$2),
        ('Chosen title', '<p>Chosen writing</p>'));
  });
  test('independent Python diary vector decrypts and rejects changed field AAD',
      () async {
    final key = [
      for (var i = 0; i < 64; i += 2)
        int.parse(
            '5485f9dbf50c2bfb57a2054954e4498576759e490e476f877e160b1cf818d4a2'
                .substring(i, i + 2),
            radix: 16)
    ];
    String e(String nonce, String cipher) => jsonEncode({
          'v': 1,
          'configuration_id': '11111111-1111-4111-8111-111111111111',
          'entry_binding': '22222222-2222-4222-8222-222222222222',
          'nonce': nonce,
          'ciphertext': cipher
        });
    final title = e('QEFCQ0RFRkdISUpL',
        'eNhUZUFnGxcKQMB7yKK9nEl79+sjV/83oxpaFCrNGZZHH69Mm+0=');
    final content = e('TE1OT1BRUlNUVVZX',
        'lRJpCfnsjE3AuUjGG0bqM2tHcBuI3vxraNQKW7sJnRGvV0A/hZWQN1QKL/MIaOBDkvmjdw==');
    expect(
        await PassphraseCrypto()
            .decryptDiary(key, 'entity-vector', 'user-vector', title, content),
        ('A quiet afternoon 🌿', '<p>Today I felt grateful. 你好</p>'));
    await expectLater(
        PassphraseCrypto()
            .decryptDiary(key, 'wrong-owner', 'user-vector', title, content),
        throwsA(anything));
  });
  testWidgets('active protection gates child creation and cancel exits Diary',
      (tester) async {
    var childBuilds = 0;
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => DiaryGate(child: Builder(builder: (_) {
                childBuilds++;
                return const Text('Diary plaintext');
              }))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home')))
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(childBuilds, 0);
    expect(find.text('Diary plaintext'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Safe home'), findsOneWidget);
    expect(childBuilds, 0);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets('base prompt cancel pops back to the actual previous screen',
      (tester) async {
    final router =
        GoRouter(initialLocation: '/settings?section=privacy', routes: [
      GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Previous settings'))),
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    router.push('/diary');
    await tester.pumpAndSettle();
    expect(find.text('Unlock your Diary'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Previous settings'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/settings?section=privacy');
    expect(DiarySession.instance.ready, isFalse);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets(
      'leaving Diary for a pushed screen clears keys and prompts on return',
      (tester) async {
    final account = appStore.state.userAuth.user;
    final key = List.filled(32, 9);
    final session = DiarySession.instance;
    session.install(fixtureData(), '${account.id}/${account.entityId}');
    session.addKey('11111111-1111-4111-8111-111111111111', key);
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
      GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Other screen'))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Private diary'), findsOneWidget);
    router.push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Other screen'), findsOneWidget);
    expect(session.ready, isFalse);
    expect(key, everyElement(0));
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Unlock your Diary'), findsOneWidget);
    expect(find.text('Private diary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets('Diary list and reader share a visit but popping Diary ends it',
      (tester) async {
    final router = GoRouter(initialLocation: '/settings', routes: [
      GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Previous settings'))),
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
      GoRoute(
          path: '/diary/entry/:id',
          builder: (_, __) => const DiaryGate(child: Text('Private reader'))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    final account = appStore.state.userAuth.user;
    final key = List.filled(32, 9);
    final session = DiarySession.instance;
    session.install(fixtureData(), '${account.id}/${account.entityId}');
    session.addKey('11111111-1111-4111-8111-111111111111', key);
    router.push('/diary');
    await tester.pumpAndSettle();
    expect(find.text('Private diary'), findsOneWidget);
    router.push('/diary/entry/one');
    await tester.pumpAndSettle();
    expect(find.text('Private reader'), findsOneWidget);
    expect(find.text('Unlock your Diary'), findsNothing);
    expect(key, everyElement(9));
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Private diary'), findsOneWidget);
    expect(session.ready, isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Previous settings'), findsOneWidget);
    expect(session.ready, isFalse);
    expect(key, everyElement(0));
    router.push('/diary');
    await tester.pumpAndSettle();
    expect(find.text('Unlock your Diary'), findsOneWidget);
    expect(find.text('Private diary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets(
      'disposing the last Diary gate resets the visit even without a route change',
      (tester) async {
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    final key = List.filled(32, 9);
    Navigator.of(tester.element(find.text('Unlock your Diary')))
        .pop((key: key, proof: 'verified fixture'));
    await tester.pumpAndSettle();
    expect(find.text('Private diary'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(DiarySession.instance.ready, isFalse);
    expect(key, everyElement(0));
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Unlock your Diary'), findsOneWidget);
    expect(find.text('Private diary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets(
      'encryption is optional and cancelling save confirmation keeps the native draft',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 'fixture-token'});
    final session = DiarySession.instance;
    session.install(fixtureData(), 'owner');
    session.addKey('11111111-1111-4111-8111-111111111111', List.filled(32, 9));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const DiaryComposeScreen()));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(
        tester
            .widget<DropdownButton<bool>>(find.byType(DropdownButton<bool>))
            .onChanged,
        isNotNull);
    await tester.tap(find.text('Encrypt this entry'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(
        tester
            .widget<DropdownButton<bool>>(find.byType(DropdownButton<bool>))
            .onChanged,
        isNull);
    await tester.enterText(find.byType(TextField).first, 'Keep my draft');
    final controller =
        tester.widget<FleatherEditor>(find.byType(FleatherEditor)).controller;
    controller.replaceText(0, 0, 'Private writing',
        selection: const TextSelection.collapsed(offset: 15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    // Saving remains busy underneath the confirmation dialog.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Confirm entry encryption'), findsOneWidget);
    expect(find.text('Personal journal'), findsOneWidget);
    expect(find.text('Encrypt and save'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm entry encryption'), findsNothing);
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(controller.document.toPlainText(), contains('Private writing'));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets(
      'native encryption choice is unavailable without an active passphrase',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    DiarySession.instance.install(fixtureData(active: false), 'owner');
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const DiaryComposeScreen()));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(checkbox.onChanged, isNull);
  });

  testWidgets('passphrase Settings shows named rows and no delete action',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            appBar: AppBar(title: const Text('Data & Privacy')),
            body: const SingleChildScrollView(
                padding: EdgeInsets.all(16), child: PassphraseSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Personal journal'), findsOneWidget);
    expect(find.text('Protected'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });
  testWidgets('rename cancellation completes its closing animation safely',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Different name');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Personal journal'), findsOneWidget);
  });
  testWidgets('backgrounding clears a pending unlock secret and ends the visit',
      (tester) async {
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
      GoRoute(
          path: '/newsfeed',
          builder: (_, __) => const Scaffold(body: Text('Safe home'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'A phrase still being entered');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller?.text, isEmpty);
    }
    expect(DiarySession.instance.ready, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'switch confirmation shows both passphrases and cancel sends no mutation',
      (tester) async {
    final data = fixtureData();
    (data['purposes'][0]['configurations'] as List).add({
      ...fixtureConfiguration(active: false),
      'id': '33333333-3333-4333-8333-333333333333',
      'name': 'Travel journal',
      'verification_aad':
          '["chatterloop.encryption.verification",1,"33333333-3333-4333-8333-333333333333","entity-vector","user-vector","diary"]',
    });
    var writes = 0;
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method != 'GET') writes++;
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Current passphrase · Personal journal'), findsOneWidget);
    expect(find.text('Selected passphrase · Travel journal'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
  });
  testWidgets('Diary list shows an unlocked entry and an older locked row',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = [
      for (var i = 0; i < 64; i += 2)
        int.parse(
            '5485f9dbf50c2bfb57a2054954e4498576759e490e476f877e160b1cf818d4a2'
                .substring(i, i + 2),
            radix: 16)
    ];
    late (String, String) current;
    late (String, String) older;
    await tester.runAsync(() async {
      current = await PassphraseCrypto().encryptDiary(
          key,
          'entity-vector',
          'user-vector',
          '11111111-1111-4111-8111-111111111111',
          'Finding a little more breathing room',
          '<p>The morning was quiet, and I let it stay that way. Some days, that is enough.</p>');
      older = await PassphraseCrypto().encryptDiary(
          key,
          'entity-vector',
          'user-vector',
          '33333333-3333-4333-8333-333333333333',
          'A day by the coast',
          '<p>A memory protected with an older passphrase.</p>');
    });
    final session = DiarySession.instance;
    final account = appStore.state.userAuth.user;
    session.install(fixtureData(), '${account.id}/${account.entityId}');
    session.addKey('11111111-1111-4111-8111-111111111111', key);
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(
          onRequest: (options, handler) =>
              handler.resolve(Response(requestOptions: options, data: {
                'count': 3,
                'next': null,
                'results': [
                  {
                    'id': 'current',
                    'title': current.$1,
                    'content': current.$2,
                    'is_encrypted': true,
                    'is_private': true,
                    'entry_date': '2026-10-20',
                    'created_at': '2026-10-20T09:00:00Z'
                  },
                  {
                    'id': 'older',
                    'title': older.$1,
                    'content': older.$2,
                    'is_encrypted': true,
                    'is_private': true,
                    'entry_date': '2026-06-12',
                    'created_at': '2026-06-12T09:00:00Z'
                  },
                  {
                    'id': 'legacy',
                    'title': 'A small promise to myself',
                    'content':
                        '<p>Keep making room for things that matter.</p>',
                    'is_private': true,
                    'entry_date': '2026-01-04',
                    'created_at': '2026-01-04T09:00:00Z'
                  },
                ],
              }))));
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: DiaryListScreen()))
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Finding a little more breathing room'), findsOneWidget);
    expect(find.text('A day by the coast'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'locked details retain the reader and prompt once before remaining locked on cancel',
      (tester) async {
    late (String, String) encrypted;
    await tester.runAsync(() async {
      encrypted = await PassphraseCrypto().encryptDiary(
          List.filled(32, 7),
          'entity-vector',
          'user-vector',
          '11111111-1111-4111-8111-111111111111',
          'Hidden title',
          '<p>Hidden body</p>');
    });
    DiarySession.instance.install(fixtureData(active: false), 'owner');
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'id': 'locked',
          'title': encrypted.$1,
          'content': encrypted.$2,
          'is_encrypted': true,
          'is_private': true,
          'entry_date': '2026-10-20',
          'created_at': '2026-10-20T09:00:00Z',
        }));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const DiaryEntryScreen(entryId: 'locked')));
    await tester.pumpAndSettle();
    expect(find.text('Unlock older entries'), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-diary-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-diary-content')), findsOneWidget);
    expect(find.text('Encrypted'), findsOneWidget);
    expect(find.text('Hidden title'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock older entries'), findsNothing);
    expect(find.byKey(const ValueKey('locked-diary-content')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Unlock older entries'), findsNothing);
    await tester.tap(find.text('Unlock entry'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock older entries'), findsOneWidget);
  });
  testWidgets('locked display contains only placeholders', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
            appBar: AppBar(title: const Text('Diary')),
            body: const Padding(
                padding: EdgeInsets.all(24), child: LockedDiary()))));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.text('Entry needs a different or older key to unlock'),
        findsOneWidget);
  });
}
