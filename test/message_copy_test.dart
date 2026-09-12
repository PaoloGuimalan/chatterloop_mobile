// "Copy" in the long-press menu.
//
// The entry came from the vendored flutter_chat_reactions default list and was
// never wired to anything - it rendered, you tapped it, the dialog closed and
// nothing happened. There is no webapp counterpart to mirror (web's message
// menu has no Copy at all), so what it copies is decided here:
//
//   text        the words
//   attachment  the file's URL, normalised - a link is the only thing about a
//               photo that can be text, and it is what someone reaching for
//               Copy on one wants
//   notif       nothing; the entry is not offered. A system notice is the app
//               talking, not a message anyone wrote.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

MessageContent _message({
  required String content,
  String type = 'text',
}) =>
    MessageContent.fromJson({
      "messageID": "m1",
      "conversationID": "c1",
      "sender": "me",
      "content": content,
      "messageType": type,
      "messageDate": "2026-01-01T00:00:00.000Z",
    });

void main() {
  /// What the app actually put on the clipboard, or null if it never asked.
  String? copied;

  setUp(() {
    copied = null;
    // The clipboard is a platform channel, which a widget test has no
    // implementation for - so stand in for it and record what was written.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpThread(WidgetTester tester, MessageContent message) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StoreProvider<AppState>(
      store: appStore,
      child: MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageContentWidget(
              messageContent: message,
              previousContentUserID: "end",
              currentUserID: "me",
              onPressed: (_, __) {},
              resolveSenderName: (id) => id,
              isSingleConversation: true,
              conversationID: "c1",
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Long-presses [bubble] and waits for the menu.
  ///
  /// [bubble] has to be the PAINTED content - the text, the file name, the
  /// image - not the Hero or the MessageContentWidget around it. Both of those
  /// span the full width including the empty space beside a right-aligned
  /// bubble, and the GestureDetector that opens this menu defers to its child,
  /// so a press landing in that space hits nothing at all. (Which is correct
  /// on a device: the gap beside a message is not the message.)
  Future<void> openMenu(WidgetTester tester, Finder bubble) async {
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
  }

  /// Then tap [item]. The dialog waits 500ms before popping and calling back,
  /// so the tap is not done until that has run.
  Future<void> tapMenu(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  testWidgets('a text message copies its words', (tester) async {
    await pumpThread(tester, _message(content: 'hello there'));

    await openMenu(tester, find.text('hello there').first);
    await tapMenu(tester, 'Copy');

    expect(copied, 'hello there');
  });

  testWidgets('an attachment copies its link', (tester) async {
    await pumpThread(
        tester,
        _message(
          content: 'https://cdn.example.com/files/report.pdf',
          type: 'application/pdf',
        ));

    await openMenu(tester, find.text('report.pdf').first);
    await tapMenu(tester, 'Copy');

    expect(copied, 'https://cdn.example.com/files/report.pdf');
  });

  testWidgets('a legacy attachment copies the URL, not the stored field',
      (tester) async {
    // "url%%%filename" is the old Google Cloud Storage encoding. Copying the
    // raw field would hand out a link with the filename glued to its end.
    //
    // Exercised on a FILE card rather than a photo, deliberately: the encoding
    // is a property of the stored URL, not of the media type, and a file card
    // renders as text - where an image in a widget test never loads, so the
    // hero flight would lay the bubble out at intermediate sizes an unloaded
    // image cannot fill.
    await pumpThread(
        tester,
        _message(
          content: 'https://storage.googleapis.com/b/k%%%holiday.jpg',
          type: 'application/octet-stream',
        ));

    await openMenu(tester, find.text('holiday.jpg').first);
    await tapMenu(tester, 'Copy');

    expect(copied, 'https://storage.googleapis.com/b/k');
  });

  testWidgets('a system notice is not offered Copy at all', (tester) async {
    await pumpThread(
        tester, _message(content: 'Anna joined the group', type: 'notif'));

    await openMenu(tester, find.text('Anna joined the group').first);

    // Reply is still there, so the menu did open - Copy is the one missing.
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('an empty message is not offered Copy either', (tester) async {
    await pumpThread(tester, _message(content: '   '));

    await openMenu(tester, find.text('   ').first);

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });
}
