import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/notes_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_attachment.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/diary/diary_list_view.dart';
import 'package:chatterloop_app/views/diary/diary_entry_view.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/views/diary/diary_compose_view.dart';
import 'package:chatterloop_app/views/notes/notes_list_view.dart';
import 'package:chatterloop_app/views/notes/note_editor_view.dart';
import 'package:dio/dio.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _titles = [
  'Ideas for the next release',
  'Weekend plans',
  'A thought to keep',
  'Reading list',
  'Project handover',
  'A few little reminders'
];
const _bodies = [
  'A quieter interface, clearer navigation, and small details that make everyday use feel better.',
  'Coffee in the morning, a walk somewhere new, and a little time away from the screen.',
  'Make room for the work that matters. Sometimes the useful thing is also the simplest.',
  'The Design of Everyday Things\nCreative Confidence\nFour Thousand Weeks',
  'The decisions we made, useful links, and a few open questions for the next person.',
  'Back up the project, call home, and make some time to learn something new.'
];
Map<String, dynamic> _note(int i) => {
      'id': 'note-$i',
      'title': _titles[i],
      'content': '<p>${_bodies[i]}</p>',
      'version': 1,
      'sort': 10 - i,
      'updated_at': '2026-10-15T08:00:00Z',
      'attachments': []
    };
List<Map<String, dynamic>> _entries() => List.generate(
    5,
    (i) => {
          'id': 'entry-$i',
          'title': [
            'The little things added up',
            'A slow morning',
            'An idea finally clicked',
            'Time with good people',
            'A little room to breathe'
          ][i],
          'content': '<p>${[
            'Nothing especially big happened today, but I ended it feeling a little lighter.',
            'I left the phone on the table and took the long way to get coffee.',
            'The thing I had been going back and forth on made sense after a short break.',
            'An ordinary evening that I am glad I made time for.',
            'I needed a quieter day, and today gave me one.'
          ][i]}</p>',
          'entry_date': i < 2 ? '2026-10-15' : '2026-10-${16 - i}',
          'created_at': '2026-10-15T11:30:00Z',
          'is_private': i != 3,
          'attachments': [],
          'tag_objects': [
            {'id': 1, 'name': i == 2 ? 'Work' : 'Life'},
            {'id': 2, 'name': i == 2 ? 'Learning' : 'Gratitude'}
          ],
          'mood': {
            'id': i + 1,
            'name': ['Grateful', 'Calm', 'Happy', 'Happy', 'Thoughtful'][i],
            'emoji': ['😌', '🌿', '😊', '😊', '💭'][i]
          },
        });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotesApi api;
  late List<Interceptor> previous;
  late List<Map<String, dynamic>> notes;
  late List<Map<String, dynamic>> moves;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'token': 'local-preview'});
    appStore.dispatch(DispatchModel(
        setUserAuthT,
        const UserAuth(
            true,
            UserAccount('preview-user', 'alex', 'Alex', '', 'Morgan', null,
                true, true, null, null, null, null,
                personalEntityId: 'preview-entity',
                allowedModules: [
                  'module.notes.access',
                  'module.diary.access'
                ]))));
    api = await NotesApi.open();
    notes = List.generate(6, _note);
    moves = [];
    void respond(RequestOptions options, RequestInterceptorHandler handler) {
      dynamic data;
      if (options.path.contains('/notes/')) {
        if (options.path.endsWith('/reorder/')) {
          moves.add(Map<String, dynamic>.from(options.data));
          final moved =
              notes.firstWhere((n) => n['id'] == options.data['note_id']);
          notes.remove(moved);
          final before = options.data['before_id'];
          notes.insert(
              before == null
                  ? notes.length
                  : notes.indexWhere((n) => n['id'] == before),
              moved);
          data = {
            'order': notes
                .map((n) =>
                    {'id': n['id'], 'sort': notes.length - notes.indexOf(n)})
                .toList()
          };
        } else if (options.path.endsWith('/notes/')) {
          data = {'count': notes.length, 'next': null, 'results': notes};
        } else {
          data =
              notes.firstWhere((n) => options.path.contains(n['id'] as String));
        }
      } else if (options.path.contains('/entries/')) {
        data = {'count': 5, 'next': null, 'results': _entries()};
      } else if (options.path.contains('/entry/')) {
        data = {
          ..._entries().first,
          'link_preview': {
            'status': 'ok',
            'url': 'https://chatterloop.test/story',
            'title': 'A story worth keeping',
            'site_name': 'Chatterloop',
            'description': 'A saved link preview from this diary entry.'
          }
        };
      } else {
        data = {'count': 0, 'next': null, 'results': []};
      }
      handler.resolve(
          Response(requestOptions: options, data: data, statusCode: 200));
    }

    api.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: respond));
    previous = List.of(ApiClient.userService.dio.interceptors);
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: respond));
  });
  tearDown(() {
    api.dio.close();
    ApiClient.userService.dio.interceptors
      ..clear()
      ..addAll(previous);
  });

  Future<void> show(WidgetTester tester, Widget screen, Brightness brightness,
      {bool settle = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
        initialLocation: '/review',
        routes: [GoRoute(path: '/review', builder: (_, __) => screen)]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildCLTheme(brightness),
        routerConfig: router));
    if (settle) await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('Diary retains its API link preview in the entry reader',
      (tester) async {
    await show(
        tester, const DiaryEntryScreen(entryId: 'entry-0'), Brightness.light);
    expect(find.byType(LinkPreviewCard), findsOneWidget);
    expect(find.text('A story worth keeping'), findsOneWidget);
  });

  testWidgets(
      'saved note history hides the keyboard and resumes editing on tap',
      (tester) async {
    notes[5]['content'] =
        '<p>First paragraph</p><ul><li>A list item</li><li>Another item</li></ul><p>Last paragraph</p>';
    await show(
        tester, NoteEditorScreen(api: api, noteId: 'note-5'), Brightness.light);
    final editor = tester.widget<FleatherEditor>(find.byType(FleatherEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    editor.controller.replaceText(6, 0, 'edited ',
        selection: const TextSelection.collapsed(offset: 13));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      tester.state<RawEditorState>(find.byType(RawEditor)).requestKeyboard();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(editor.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      tester.state<RawEditorState>(find.byType(RawEditor)).requestKeyboard();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(editor.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    }
    final current = tester.widget<FleatherEditor>(find.byType(FleatherEditor));
    expect(current.controller.document.toPlainText(),
        contains('First edited paragraph'));
    expect(current.controller.selection.baseOffset, 13);
    final input = tester.state<RawEditorState>(find.byType(RawEditor));
    input.requestKeyboard();
    await tester.pump();
    input.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
          oldText: current.controller.document.toPlainText(),
          textInserted: 'again ',
          insertionOffset: 13,
          selection: const TextSelection.collapsed(offset: 19),
          composing: TextRange.empty)
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<FleatherEditor>(find.byType(FleatherEditor))
            .controller
            .document
            .toPlainText(),
        contains('First edited again paragraph'));
    await tester.pumpWidget(const SizedBox());
  });

  for (final screen in ['notes', 'diary', 'entry', 'editor']) {
    testWidgets(
        '$screen shows layout-specific skeletons while its request is pending',
        (tester) async {
      void hold(RequestOptions _, RequestInterceptorHandler __) {}
      api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: hold));
      ApiClient.userService.dio.interceptors
          .insert(0, InterceptorsWrapper(onRequest: hold));
      await show(
          tester,
          switch (screen) {
            'notes' => NotesListScreen(api: api),
            'diary' => const DiaryListScreen(),
            'entry' => const DiaryEntryScreen(entryId: 'entry-0'),
            _ => NoteEditorScreen(api: api, noteId: 'note-4'),
          },
          Brightness.light,
          settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(ValueKey('writing-$screen-skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets(
        'Notes cards fit their content and pack without row gaps ($theme)',
        (tester) async {
      notes[0]['content'] = '<p>A short thought.</p>';
      notes[1]['content'] =
          '<p>${List.filled(12, 'A longer thought to keep for another day.').join(' ')}</p>';
      await show(tester, NotesListScreen(api: api), brightness);
      Rect card(int i) => tester.getRect(find
          .ancestor(of: find.text(_titles[i]), matching: find.byType(InkWell))
          .first);
      final first = card(0), second = card(1), third = card(2);
      expect(first.height, lessThan(second.height - 30));
      expect(first.width, second.width);
      expect(third.left, first.left);
      expect(third.top, closeTo(first.bottom + 10, .1));
      for (var i = 0; i < notes.length; i++) {
        for (var j = i + 1; j < notes.length; j++) {
          expect(card(i).overlaps(card(j)), isFalse,
              reason: 'Content-sized cards must not overlap');
        }
      }
      expect(tester.takeException(), isNull);
    });
    testWidgets('Notes skeletons use stable varied card heights ($theme)',
        (tester) async {
      api.dio.interceptors
          .insert(0, InterceptorsWrapper(onRequest: (_, __) {}));
      await show(tester, NotesListScreen(api: api), brightness, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final cards = find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.padding == const EdgeInsets.fromLTRB(12, 13, 8, 5));
      expect(cards, findsNWidgets(8));
      final heights = cards
          .evaluate()
          .map(
              (element) => tester.getSize(find.byWidget(element.widget)).height)
          .toList();
      expect(heights.toSet().length, greaterThan(2));
      await tester.pump(const Duration(milliseconds: 300));
      final later = cards
          .evaluate()
          .map(
              (element) => tester.getSize(find.byWidget(element.widget)).height)
          .toList();
      expect(later, heights,
          reason: 'Loading animation must not reshuffle card sizes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('native Notes grid fits and animates a real drag ($theme)',
        (tester) async {
      await show(tester, NotesListScreen(api: api), brightness);
      expect(find.text(_titles.first), findsOneWidget);
      final first = tester.getCenter(find.text(_titles.first));
      final target = tester.getCenter(find.text(_titles[3]));
      final neighborBefore = tester.getTopLeft(find.text(_titles[1]));
      final gesture = await tester.startGesture(first);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(_titles.first), findsNWidgets(2),
          reason: 'The held note must enter a live drag before moving');
      await gesture.moveBy(const Offset(8, 8));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final neighborDuring = tester.getTopLeft(find.text(_titles[1]));
      await tester.pump(const Duration(milliseconds: 180));
      final neighborAfter = tester.getTopLeft(find.text(_titles[1]));
      expect(neighborDuring, isNot(neighborBefore));
      expect(neighborDuring, isNot(neighborAfter),
          reason: 'Neighboring cards should interpolate into place');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moves, isNotEmpty);
      expect(moves.last['note_id'], 'note-0');
      expect(notes.map((n) => n['id']).toList().indexOf('note-0'), 3,
          reason: 'Drop target follows the actual card bounds');
      expect(tester.takeException(), isNull);
    });
    testWidgets('native Diary cards fit cleanly ($theme)', (tester) async {
      await show(tester, const DiaryListScreen(), brightness);
      expect(find.text('The little things added up'), findsOneWidget);
      expect(find.text('Grateful'), findsOneWidget);
      expect(find.text('Private'), findsWidgets);
      expect(find.textContaining('Nothing especially big happened today'),
          findsOneWidget);
    });
    testWidgets('native Diary composer shows one tags field ($theme)',
        (tester) async {
      await show(tester, const DiaryComposeScreen(), brightness);
      expect(find.text('Search or create a tag'), findsOneWidget);
    });
    testWidgets('native Notes title changes stay outside body history ($theme)',
        (tester) async {
      await show(
          tester, NoteEditorScreen(api: api, noteId: 'note-0'), brightness);
      await tester.enterText(find.byType(TextField).first, 'Current title');
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
              .onPressed,
          isNull);
      final controller =
          tester.widget<FleatherEditor>(find.byType(FleatherEditor)).controller;
      controller.replaceText(0, 0, 'Added body. ',
          selection: const TextSelection.collapsed(offset: 12));
      await tester.pump();
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('Current title'), findsOneWidget);
      expect(
          tester
              .widget<FleatherEditor>(find.byType(FleatherEditor))
              .controller
              .document
              .toPlainText()
              .trim(),
          _bodies.first);
      expect(
          tester
              .widget<FleatherEditor>(find.byType(FleatherEditor))
              .controller
              .selection
              .baseOffset,
          0);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo))
              .onPressed,
          isNotNull);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(
          tester
              .widget<FleatherEditor>(find.byType(FleatherEditor))
              .controller
              .document
              .toPlainText()
              .trim(),
          'Added body. ${_bodies.first}');
      expect(
          tester
              .widget<FleatherEditor>(find.byType(FleatherEditor))
              .controller
              .selection
              .baseOffset,
          12,
          reason: 'Redo caret must follow the restored text');
      expect(find.text('Current title'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      // Dispose cancels the pending idle save; all rendering is local.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
  testWidgets(
      'saved Notes use the Diary attachment viewer without adding body history',
      (tester) async {
    notes[1]['attachments'] = [
      {
        'id': 'document',
        'url': 'https://media.test/plan.pdf',
        'file_name': 'Plan.pdf',
        'file_type': 'application/pdf'
      }
    ];
    await show(
        tester, NoteEditorScreen(api: api, noteId: 'note-1'), Brightness.light);
    expect(find.byType(WritingAttachment), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pump();
    expect(find.byType(WritingAttachment), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('writing images open the existing full-screen media viewer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
            body: WritingAttachment(
                attachment: DiaryAttachment(
                    url: 'https://media.test/photo.png',
                    fileType: 'image/png')))));
    // The test engine has no image bytes; invoke the image action to verify
    // it routes to the real shared viewer without relying on network layout.
    final imageAction = tester.widget<GestureDetector>(find
        .descendant(
            of: find.byType(WritingAttachment),
            matching: find.byType(GestureDetector))
        .first);
    imageAction.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    final viewer =
        tester.widget<MediaViewerScreen>(find.byType(MediaViewerScreen));
    expect(viewer.items.single.source, 'https://media.test/photo.png');
    expect(viewer.items.single.isVideo, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
