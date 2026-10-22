import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/encryption_api.dart';
import 'package:chatterloop_app/views/settings/passphrase_section.dart';
import 'package:chatterloop_app/views/diary/diary_gate.dart';
import 'package:chatterloop_app/views/diary/diary_compose_view.dart';
import 'package:chatterloop_app/views/diary/diary_entry_view.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'passphrase_mobile_test.dart' show fixtureConfiguration, fixtureData;

Map<String, dynamic> sharedConfiguration({bool active = true}) => {
      ...fixtureConfiguration(active: active),
      'purpose': 'notes',
      'verification_purpose': 'notes',
      'purposes': ['notes', 'diary'],
      'verification_aad':
          '["chatterloop.encryption.verification",1,"11111111-1111-4111-8111-111111111111","entity-vector","user-vector","notes"]',
    };

void main() {
  testWidgets('single purpose catalog still displays passphrase uses',
      (tester) async {
    final data = fixtureData();
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add passphrase'));
    await tester.pumpAndSettle();
    expect(find.text('Passphrase uses'), findsOneWidget);
    final diary = find.widgetWithText(CheckboxListTile, 'Use for Diary');
    expect(diary, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(diary).value, isTrue);
    expect(tester.getTopLeft(find.text('Name')).dy,
        lessThan(tester.getTopLeft(find.text('Passphrase uses')).dy));
    await tester.tap(diary);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Add passphrase').last)
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'global creation permits Notes alone and uses its verification origin and version',
      (tester) async {
    final data = fixtureData(active: false);
    data['purposes'] = <Map<String, dynamic>>[
      Map<String, dynamic>.from(data['purposes'][0]),
      {
        'purpose': 'notes',
        'label': 'Notes',
        'is_active': true,
        'scope_version': 'b' * 64,
        'active_configuration_id': null,
        'configurations': []
      },
      {
        'purpose': 'future',
        'label': 'Future area',
        'is_active': false,
        'scope_version': 'a' * 64,
        'active_configuration_id': null,
        'configurations': []
      },
    ];
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    Map<String, dynamic>? submitted;
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'POST') {
          submitted = Map<String, dynamic>.from(options.data as Map);
        }
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add passphrase').first);
    await tester.pumpAndSettle();
    final notes = find.widgetWithText(CheckboxListTile, 'Use for Notes');
    expect(notes, findsOneWidget);
    final origin = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Use for Diary'));
    expect(origin.value, isTrue);
    expect(origin.onChanged, isNotNull);
    expect(find.widgetWithText(CheckboxListTile, 'Use for Future area'),
        findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Use for Diary'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Add passphrase').last)
            .onPressed,
        isNull);
    await tester.ensureVisible(notes);
    await tester.tap(notes);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(0), 'Reusable private data');
    await tester.enterText(
        find.byType(TextField).at(1), 'violet lantern river 你好');
    await tester.enterText(
        find.byType(TextField).at(2), 'violet lantern river 你好');
    final recovery = find.widgetWithText(CheckboxListTile,
        'I understand that a forgotten passphrase cannot be recovered.');
    await tester.ensureVisible(recovery);
    await tester.pumpAndSettle();
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(TextButton, 'Add passphrase').last;
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    for (var i = 0; i < 200 && submitted == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(submitted?['purpose'], 'notes');
    expect(submitted?['purposes'], ['notes']);
    expect(submitted?['expected_scope_version'], 'b' * 64);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('disabled Diary retains encrypted entries locked even with a cached key',
      () async {
    final data = fixtureData();
    final session = DiarySession();
    final key = List.filled(32, 7);
    session.install(data, 'owner');
    session.addKey('11111111-1111-4111-8111-111111111111', key);
    final fields = await PassphraseCrypto().encryptDiary(
        key,
        'entity-vector',
        'user-vector',
        '11111111-1111-4111-8111-111111111111',
        'Hidden title',
        'Hidden writing');
    final entry = DiaryEntry.fromJson({
      'id': 'old',
      'is_encrypted': true,
      'title': fields.$1,
      'content': fields.$2
    });
    data['purposes'][0]['is_active'] = false;
    session.install(data, 'owner');
    expect(key, everyElement(0));
    expect((await session.openEntry(entry)).isLocked, isTrue);
    expect(session.configuration('11111111-1111-4111-8111-111111111111'),
        isNotNull);
    expect(session.canEncrypt, isFalse);
    await expectLater(session.encryptNew('New', 'New'), throwsFormatException);
    session.clear();
  });

  testWidgets('disabled Diary bypasses the visit prompt', (tester) async {
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    final data = fixtureData();
    data['purposes'][0]['is_active'] = false;
    DiarySession.instance.clear();
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Private diary'), findsOneWidget);
    expect(find.text('Unlock your Diary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets('disabled Diary does not offer encryption for a new entry',
      (tester) async {
    final data = fixtureData();
    data['purposes'][0]['is_active'] = false;
    DiarySession.instance.install(data, 'owner');
    addTearDown(DiarySession.instance.clear);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const DiaryComposeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Encrypt this entry'), findsNothing);
  });

  testWidgets('disabled Diary detail stays blurred without unlock actions',
      (tester) async {
    final data = fixtureData();
    data['purposes'][0]['is_active'] = false;
    DiarySession.instance.install(data, 'owner');
    addTearDown(DiarySession.instance.clear);
    late (String, String) fields;
    await tester.runAsync(() async {
      fields = await PassphraseCrypto().encryptDiary(
          List.filled(32, 7),
          'entity-vector',
          'user-vector',
          '11111111-1111-4111-8111-111111111111',
          'Hidden old title',
          '<p>Hidden old writing</p>');
    });
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'id': 'old',
          'title': fields.$1,
          'content': fields.$2,
          'is_encrypted': true,
          'is_private': true,
        }));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const DiaryEntryScreen(entryId: 'old')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('locked-diary-content')), findsOneWidget);
    expect(find.text('Hidden old title'), findsNothing);
    expect(find.text('Unlock entry'), findsNothing);
    expect(find.text('Unlock older entries'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  for (final active in [false, true]) {
    testWidgets(
        'disabled purpose settings retain maintenance for active=$active',
        (tester) async {
      final data = fixtureData(active: active);
      data['purposes'][0]['is_active'] = false;
      final dio = ApiClient.userService.dio;
      final previous = List<Interceptor>.from(dio.interceptors);
      addTearDown(() => dio.interceptors
        ..clear()
        ..addAll(previous));
      dio.interceptors
        ..clear()
        ..add(InterceptorsWrapper(onRequest: (options, handler) {
          handler.resolve(Response(
              requestOptions: options, data: {'status': true, 'result': data}));
        }));
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: const Scaffold(
              body: SingleChildScrollView(child: PassphraseSection()))));
      await tester.pumpAndSettle();
      expect(find.text('Diary · Paused'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Add passphrase'))
              .onPressed,
          isNull);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<PopupMenuItem<String>>(
                  find.widgetWithText(PopupMenuItem<String>, 'Rename'))
              .enabled,
          isTrue);
      expect(
          tester
              .widget<PopupMenuItem<String>>(find.widgetWithText(
                  PopupMenuItem<String>, active ? 'Disable' : 'Activate'))
              .enabled,
          active);
    });
  }

  testWidgets('disabled empty Diary bypasses the first-time setup introduction',
      (tester) async {
    final data = fixtureData(active: false);
    data['purposes'][0]['is_active'] = false;
    data['purposes'][0]['configurations'] = [];
    DiarySession.instance.clear();
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Plaintext Diary'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Plaintext Diary'), findsOneWidget);
    expect(find.text('Protect your Diary'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets('Diary fetches only configurations for its purpose',
      (tester) async {
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    final requests = <RequestOptions>[];
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    DiarySession.instance.clear();
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(Response(
            requestOptions: options,
            data: {'status': true, 'result': fixtureData()}));
      }));
    final router = GoRouter(initialLocation: '/diary', routes: [
      GoRoute(
          path: '/diary',
          builder: (_, __) => const DiaryGate(child: Text('Private diary'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    expect(requests.single.queryParameters, {'purpose': 'diary'});
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  test('verification binding uses immutable origin despite changed memberships',
      () {
    final c = sharedConfiguration();
    expect(PassphraseCrypto.verificationAad(c), c['verification_aad']);
    expect(() => PassphraseCrypto.validateConfiguration(c), returnsNormally);
    c['purposes'] = ['diary'];
    expect(() => PassphraseCrypto.validateConfiguration(c), returnsNormally);
    c['verification_purpose'] = 'diary';
    expect(
        () => PassphraseCrypto.validateConfiguration(c), throwsFormatException);
  });

  test('new configuration verifies its chosen origin and optional shared uses',
      () async {
    final crypto = PassphraseCrypto();
    final payload = await crypto.setup('Shared private data',
        'violet lantern river 你好', 'entity-vector', 'user-vector', 'a' * 64,
        purpose: 'notes', purposes: ['notes', 'diary']);
    expect(payload['purpose'], 'notes');
    expect(payload['purposes'], ['notes', 'diary']);
    final c = {
      ...payload,
      'entity_id': 'entity-vector',
      'user_id': 'user-vector',
      'verification_purpose': 'notes',
      'verification_aad': jsonEncode([
        'chatterloop.encryption.verification',
        1,
        payload['id'],
        'entity-vector',
        'user-vector',
        'notes'
      ])
    };
    final unlocked = await crypto.unlock(c, 'violet lantern river 你好');
    expect(base64Decode(unlocked.proof), hasLength(32));
    unlocked.key.fillRange(0, unlocked.key.length, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('legacy Diary verification remains usable after its membership changes',
      () async {
    final c = {
      ...fixtureConfiguration(),
      'verification_purpose': 'diary',
      'purposes': ['notes']
    };
    final unlocked =
        await PassphraseCrypto().unlock(c, 'violet lantern river 你好');
    expect(unlocked.proof, 'ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=');
    unlocked.key.fillRange(0, unlocked.key.length, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('malformed explicit membership never falls back to the legacy origin',
      () {
    for (final uses in [
      null,
      [],
      ['diary', 'diary'],
      [''],
      [1],
      ['a' * 41]
    ]) {
      expect(
          () => PassphraseCrypto.validateConfiguration(
              {...fixtureConfiguration(), 'purposes': uses}),
          throwsFormatException);
    }
  });

  test('filtered responses and blank purposes fail closed', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(Response(
          requestOptions: options,
          data: {'status': true, 'result': fixtureData()}));
    }));
    addTearDown(dio.close);
    final api = EncryptionApi(dio: dio);
    await expectLater(api.load(purpose: ''), throwsFormatException);
    expect(requests, 0);
    await expectLater(api.load(purpose: 'notes'), throwsFormatException);
  });

  test('Diary uses explicit membership and fails closed when absent', () async {
    final session = DiarySession();
    final data = fixtureData();
    final c = sharedConfiguration();
    data['purposes'][0]['configurations'] = [c];
    session.install(data, 'owner');
    session.addKey(c['id'], List.filled(32, 7));
    expect(session.active?['id'], c['id']);
    final fields =
        await session.encryptNew('Shared title', '<p>Shared body</p>');
    expect(jsonDecode(fields.$1)['configuration_id'], c['id']);
    c['purposes'] = ['notes'];
    expect(session.configuration(c['id']), isNull);
    await expectLater(
        session.encryptNew('Blocked', 'Blocked'), throwsFormatException);
    session.clear();
  });

  test(
      'settings load accepts advertised groups without a Diary origin or group',
      () async {
    final data = fixtureData();
    data['purposes'][0]['purpose'] = 'notes';
    data['purposes'][0]['configurations'] = [sharedConfiguration()];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options, data: {'status': true, 'result': data}));
    }));
    addTearDown(dio.close);
    expect((await EncryptionApi(dio: dio).load())['purposes'], hasLength(1));
    data['purposes'][0]['purpose'] = 'other';
    await expectLater(EncryptionApi(dio: dio).load(), throwsFormatException);
  });

  test('registered purpose limits count Unicode codepoints like the server',
      () async {
    final data = fixtureData();
    final code = '😀' * 21;
    final c = {
      ...fixtureConfiguration(),
      'purpose': code,
      'verification_purpose': code,
      'purposes': [code],
      'verification_aad': jsonEncode([
        'chatterloop.encryption.verification',
        1,
        '11111111-1111-4111-8111-111111111111',
        'entity-vector',
        'user-vector',
        code
      ])
    };
    data['purposes'][0]['purpose'] = code;
    data['purposes'][0]['configurations'] = [c];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options, data: {'status': true, 'result': data}));
    }));
    addTearDown(dio.close);
    expect((await EncryptionApi(dio: dio).load(purpose: code))['purposes'],
        hasLength(1));
    await expectLater(EncryptionApi(dio: dio).load(purpose: '😀' * 41),
        throwsFormatException);
  });

  testWidgets('advertised groups share the global active confirmation',
      (tester) async {
    final data = fixtureData();
    final active = fixtureConfiguration();
    final target = {
      ...sharedConfiguration(active: false),
      'id': '33333333-3333-4333-8333-333333333333',
      'name': 'Reusable passphrase',
      'purposes': ['notes'],
      'verification_aad':
          '["chatterloop.encryption.verification",1,"33333333-3333-4333-8333-333333333333","entity-vector","user-vector","notes"]',
    };
    data['purposes'] = [
      {
        ...data['purposes'][0],
        'configurations': [active]
      },
      {
        'purpose': 'notes',
        'label': 'Notes',
        'scope_version': 'a' * 64,
        'active_configuration_id': null,
        'configurations': [target]
      },
    ];
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Reusable passphrase'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Current passphrase · Personal journal'), findsOneWidget);
    expect(
        find.text('Selected passphrase · Reusable passphrase'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('renaming a shared configuration reloads every advertised group',
      (tester) async {
    final data = fixtureData();
    final shared = {
      ...fixtureConfiguration(),
      'verification_purpose': 'diary',
      'purposes': ['diary', 'notes']
    };
    data['purposes'][0]['configurations'] = [shared];
    (data['purposes'] as List).add(<String, dynamic>{
      ...data['purposes'][0],
      'purpose': 'notes',
      'label': 'Notes'
    });
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    final reads = <RequestOptions>[];
    RequestOptions? mutation;
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'GET') {
          reads.add(options);
        } else {
          mutation = options;
          shared['name'] = (options.data as Map)['name'];
        }
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Personal journal'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('Add passphrase'), findsOneWidget);
    expect(find.text('Diary'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Every private use');
    await tester.tap(find.text('Rename passphrase').last);
    await tester.pumpAndSettle();
    expect((mutation?.data as Map)['purpose'], 'diary');
    expect(reads, hasLength(2));
    expect(reads.every((r) => r.queryParameters.isEmpty), isTrue);
    expect(find.text('Every private use'), findsOneWidget);
  });

  testWidgets('a shared row activates through an enabled linked purpose',
      (tester) async {
    final data = fixtureData(active: false);
    final shared = {
      ...fixtureConfiguration(active: false),
      'purposes': ['diary', 'notes']
    };
    data['purposes'] = <Map<String, dynamic>>[
      {
        ...data['purposes'][0],
        'is_active': false,
        'configurations': [shared]
      },
      {
        ...data['purposes'][0],
        'purpose': 'notes',
        'label': 'Notes',
        'is_active': true,
        'scope_version': 'b' * 64,
        'configurations': [shared]
      },
    ];
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.from(dio.interceptors);
    Map<String, dynamic>? mutation;
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(previous));
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'POST') {
          mutation = Map<String, dynamic>.from(options.data as Map);
        }
        handler.resolve(Response(
            requestOptions: options, data: {'status': true, 'result': data}));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: SingleChildScrollView(child: PassphraseSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Personal journal'), findsOneWidget);
    expect(find.text('Diary · Paused'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activate'));
    await tester.pump(const Duration(milliseconds: 500));
    Navigator.of(tester.element(find.text('Activate passphrase').first))
        .pop((active: null as String?, target: 'confirmed-proof' as String?));
    await tester.pumpAndSettle();
    expect(mutation?['purpose'], 'notes');
    expect(mutation?['expected_scope_version'], 'b' * 64);
    expect(mutation?['target_verification_proof'], 'confirmed-proof');
  });
}
