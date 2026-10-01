// The conversation info screen's shared media: the preview section and the
// Photos / Videos / Audio / Files screen it opens.
//
// Driven through the screens' `fetch` parameter, so what is pinned here is the
// paging contract with /m/conversationfiles - which kinds each tab asks for,
// that a cursor goes back exactly as it came, that a short page keeps pulling
// until the tab fills, and that a failure offers a retry instead of an empty
// tab. Pumped at a 360px phone width, so a row that overflows fails too.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/messages_models/conversation_files_model.dart';
import 'package:chatterloop_app/views/messages/conversation_files_view.dart';

class _Call {
  final List<ConversationFileKind> kinds;
  final String? cursor;
  final int limit;
  final Completer<ConversationFilesPage?> reply = Completer();

  _Call(this.kinds, this.cursor, this.limit);
}

/// A fetch whose every call waits until the test answers it.
class _FakeServer {
  final List<_Call> calls = [];

  Future<ConversationFilesPage?> fetch(
      List<ConversationFileKind> kinds, String? cursor, int limit) {
    final call = _Call(kinds, cursor, limit);
    calls.add(call);
    return call.reply.future;
  }
}

ConversationFileItem _item(ConversationFileKind kind, int i,
        {String? content}) =>
    ConversationFileItem(
      messageID: '${kind.wire}-$i',
      sender: 'them',
      kind: kind,
      mimeType: switch (kind) {
        ConversationFileKind.image => 'image',
        ConversationFileKind.video => 'video/mp4',
        ConversationFileKind.audio => 'audio/mpeg',
        ConversationFileKind.file => 'application/pdf',
      },
      content: content ?? 'https://cdn.example.invalid/${kind.wire}-$i',
      sentAt: DateTime.now().subtract(Duration(hours: i)),
    );

ConversationFilesPage _page(ConversationFileKind kind, int from, int count,
        {String? next}) =>
    ConversationFilesPage(
      items: [for (var i = from; i < from + count; i++) _item(kind, i)],
      nextCursor: next,
    );

Future<void> _pumpScreen(WidgetTester tester, _FakeServer server) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: ConversationFilesScreen(
      conversationId: 'conv-1',
      conversationType: 'single',
      title: 'Ada Lovelace',
      fetch: server.fetch,
    ),
  ));
  await tester.pump();
}

/// Answers a call and lets the result render (and ensureFilled's post-frame
/// check run).
Future<void> _answer(
    WidgetTester tester, _Call call, ConversationFilesPage? page) async {
  call.reply.complete(page);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(VideoFirstFrame.clearCache);

  testWidgets('the Photos tab shows skeletons, then its first page',
      (tester) async {
    final server = _FakeServer();
    await _pumpScreen(tester, server);

    // Only the open tab has asked - the others wait until they are shown.
    expect(server.calls, hasLength(1));
    expect(server.calls.single.kinds, [ConversationFileKind.image]);
    expect(server.calls.single.cursor, isNull);
    expect(server.calls.single.limit, 30);
    expect(find.byType(CLSkeleton), findsWidgets);

    await _answer(tester, server.calls.single,
        _page(ConversationFileKind.image, 0, 30, next: 'cursor-2'));

    expect(find.byType(CLNetworkImage), findsWidgets);
    expect(find.byType(CLSkeleton), findsNothing);
    // A full first page overflows the screen, so nothing more is asked for
    // until it is scrolled.
    expect(server.calls, hasLength(1));
  });

  testWidgets('scrolling to the end pages on with the cursor it was given',
      (tester) async {
    final server = _FakeServer();
    await _pumpScreen(tester, server);
    await _answer(tester, server.calls.single,
        _page(ConversationFileKind.image, 0, 30, next: 'cursor-2'));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();

    expect(server.calls, hasLength(2));
    expect(server.calls[1].cursor, 'cursor-2');
    // Infinite loading: skeleton tiles under the loaded ones meanwhile. They
    // land just below the fold (the scroll stopped at the OLD end), so they
    // are built in the cache area rather than painted - hence skipOffstage.
    expect(find.byType(CLSkeleton, skipOffstage: false), findsNWidgets(6));

    await _answer(
        tester, server.calls[1], _page(ConversationFileKind.image, 30, 9));
    expect(find.byType(CLSkeleton), findsNothing);

    // No cursor back = the end. Scrolling again asks for nothing.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    expect(server.calls, hasLength(2));
  });

  testWidgets('a short first page keeps loading until the tab fills',
      (tester) async {
    final server = _FakeServer();
    await _pumpScreen(tester, server);

    // Three tiles cannot scroll, so no scroll event would ever ask for more.
    await _answer(tester, server.calls.single,
        _page(ConversationFileKind.image, 0, 3, next: 'cursor-2'));

    expect(server.calls, hasLength(2));
    expect(server.calls[1].cursor, 'cursor-2');
  });

  testWidgets('the Files tab lists names, legacy and current alike',
      (tester) async {
    final server = _FakeServer();
    await _pumpScreen(tester, server);
    await _answer(tester, server.calls.single,
        _page(ConversationFileKind.image, 0, 30, next: 'cursor-2'));

    await tester.tap(find.text('Files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final filesCall = server.calls.last;
    expect(filesCall.kinds, [ConversationFileKind.file]);
    expect(filesCall.limit, 20);

    await _answer(
      tester,
      filesCall,
      ConversationFilesPage(items: [
        _item(ConversationFileKind.file, 0,
            content:
                'https://storage.googleapis.com/bucket/files/IMG_abc%%%Quarterly report.pdf'),
        _item(ConversationFileKind.file, 1,
            content:
                'https://bucket.cdn.example.invalid/uploads/messages/conv-1/AB12_notes.pdf'),
      ]),
    );

    expect(find.text('Quarterly report.pdf'), findsOneWidget);
    expect(find.text('AB12_notes.pdf'), findsOneWidget);
  });

  testWidgets('a failed first page offers a retry, not an empty tab',
      (tester) async {
    final server = _FakeServer();
    await _pumpScreen(tester, server);
    await _answer(tester, server.calls.single, null);

    expect(find.text("Couldn't load this tab"), findsOneWidget);
    expect(find.text('No photos yet'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(server.calls, hasLength(2));
    expect(server.calls[1].cursor, isNull);

    await _answer(
        tester, server.calls[1], _page(ConversationFileKind.image, 0, 0));
    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('the info screen preview shows the latest four and opens See all',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final server = _FakeServer();
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(CLSpacing.contentGutter),
          child: ConversationMediaPreview(
            conversationId: 'conv-1',
            conversationType: 'group',
            title: 'Design team',
            fetch: server.fetch,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Photos and videos together, one row's worth.
    expect(server.calls.single.kinds,
        [ConversationFileKind.image, ConversationFileKind.video]);
    expect(server.calls.single.limit, ConversationMediaPreview.count);
    expect(find.byType(CLSkeleton), findsNWidgets(4));

    await _answer(
      tester,
      server.calls.single,
      ConversationFilesPage(items: [
        _item(ConversationFileKind.image, 0),
        _item(ConversationFileKind.video, 1),
        _item(ConversationFileKind.image, 2),
      ], nextCursor: null),
    );
    expect(find.byType(CLSkeleton), findsNothing);
    expect(find.byType(CLNetworkImage), findsNWidgets(2));
    expect(find.byType(VideoFirstFrame), findsOneWidget);

    await tester.tap(find.text('See all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConversationFilesScreen), findsOneWidget);
  });

  testWidgets('a conversation with no photos or videos still offers See all',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final server = _FakeServer();
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: ConversationMediaPreview(
          conversationId: 'conv-1',
          conversationType: 'single',
          title: 'Ada',
          fetch: server.fetch,
        ),
      ),
    ));
    await tester.pump();
    await _answer(
        tester, server.calls.single, const ConversationFilesPage(items: []));

    expect(find.text('No photos or videos yet'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  // The Audio tab's day groups. Pinned on the grouping rather than the widget:
  // a rendered clip opens a real audio player, which a widget test cannot.
  group('audio grouped by day', () {
    final now = DateTime(2026, 10, 1, 9, 30);
    ConversationFileItem at(String id, DateTime sentAt) => ConversationFileItem(
          messageID: id,
          sender: 'them',
          kind: ConversationFileKind.audio,
          mimeType: 'audio/mpeg',
          content: 'https://cdn.example.invalid/$id',
          sentAt: sentAt,
        );

    test('one label per calendar day, in the order they came', () {
      final days = groupFilesByDay([
        at('a', DateTime(2026, 10, 1, 9, 0)),
        at('b', DateTime(2026, 10, 1, 0, 5)),
        // 23:50 last night is Yesterday, not "Today" for being < 24h old.
        at('c', DateTime(2026, 9, 30, 23, 50)),
        at('d', DateTime(2026, 7, 16, 12)),
        at('e', DateTime(2026, 7, 16, 8)),
        at('f', DateTime(2025, 12, 31, 20)),
      ], now: now);

      expect(days.map((d) => d.label),
          ['Today', 'Yesterday', 'Jul 16, 2026', 'Dec 31, 2025']);
      expect(days.map((d) => d.items.map((i) => i.messageID).join()),
          ['ab', 'c', 'de', 'f']);
    });

    test('a day split across two pages stays one group', () {
      final firstPage = [
        at('a', DateTime(2026, 7, 16, 12)),
        at('b', DateTime(2026, 7, 16, 11)),
      ];
      final secondPage = [
        at('c', DateTime(2026, 7, 16, 10)),
        at('d', DateTime(2026, 7, 13, 10)),
      ];
      final days = groupFilesByDay([...firstPage, ...secondPage], now: now);
      expect(days.map((d) => d.items.length), [3, 1]);
    });

    test('Yesterday is right across a month boundary', () {
      final days = groupFilesByDay(
        [at('a', DateTime(2026, 9, 30, 18))],
        now: DateTime(2026, 10, 1, 0, 30),
      );
      expect(days.single.label, 'Yesterday');
    });
  });
}
