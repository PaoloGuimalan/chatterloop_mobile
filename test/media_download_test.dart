// Full-screen media in conversations, and saving attachments to the device.
//
// Three things are pinned here, in the order a file moves through them:
//
//   1. the content -> url / filename parsing, which is the part with real
//      edge cases (a legacy "url%%%filename" upload, a signed URL with a
//      query string, a percent-encoded name)
//   2. the viewer's actions, including the one regression that is invisible
//      on a photo: the download button has to come BACK as a progress ring
//      when the viewer is reopened on a file already downloading
//   3. the message bubble reaching the viewer at all - and the file card's
//      tap, which used to be an empty callback that did nothing

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

const _spacesImage = 'https://cdn.example.invalid/uploads/holiday%20photo.jpg';
const _spacesFile = 'https://cdn.example.invalid/uploads/report.pdf';

/// The file card itself - the bubble also carries a reply button, which is an
/// ElevatedButton too.
final Finder _fileCard = find.ancestor(
  of: find.text('report.pdf'),
  matching: find.byType(ElevatedButton),
);

MessageContent _message({required String type, required String content}) =>
    MessageContent.fromJson({
      "messageID": "m1",
      "conversationID": "c1",
      "sender": "them",
      "content": content,
      "messageType": type,
      "messageDate": "2026-01-01T00:00:00.000Z",
    });

void main() {
  // The notifier is a process-wide singleton, so a test that stages a
  // download has to hand it back empty or the next one inherits a spinner.
  tearDown(() => MediaDownloader.instance.progress.value = const {});

  group('attachment url and name', () {
    test('a plain url is left alone', () {
      expect(chatMediaUrl(_spacesFile), _spacesFile);
    });

    test('the legacy url%%%filename encoding keeps only the url', () {
      const content =
          'https://storage.googleapis.com/bucket/abc123%%%quarterly.pdf';
      expect(chatMediaUrl(content),
          'https://storage.googleapis.com/bucket/abc123');
      // The name is the half after the delimiter - the key itself carries no
      // readable one.
      expect(chatMediaFileName(content), 'quarterly.pdf');
    });

    test('a literal ### in a key is escaped back into a percent-encoded #', () {
      expect(
        chatMediaUrl('https://cdn.example.invalid/a###b.mp4'),
        'https://cdn.example.invalid/a%23%23%23b.mp4',
      );
    });

    test('a name comes from the last path segment, percent-decoded', () {
      expect(chatMediaFileName(_spacesImage), 'holiday photo.jpg');
    });

    test('a signed url does not save its query string as part of the name', () {
      expect(
        chatMediaFileName('$_spacesFile?X-Amz-Signature=deadbeef&x=1'),
        'report.pdf',
      );
    });

    test('characters a filesystem rejects are replaced', () {
      expect(
        chatMediaFileName('https://cdn.example.invalid/a%2Fb%3Ac.txt'),
        'a_b_c.txt',
      );
    });

    test('a url with nothing to name falls back', () {
      expect(chatMediaFileName('https://cdn.example.invalid/'), 'file');
    });

    test('content type is guessed from the extension, opaque when unknown', () {
      expect(mimeTypeForFileName('a.jpg'), 'image/jpeg');
      expect(mimeTypeForFileName('a.mp4'), 'video/mp4');
      expect(mimeTypeForFileName('a.pdf'), 'application/pdf');
      expect(mimeTypeForFileName('a.wat'), 'application/octet-stream');
      expect(mimeTypeForFileName('noextension'), 'application/octet-stream');
    });
  });

  group('the full-screen viewer', () {
    Future<void> pumpViewer(
      WidgetTester tester, {
      required List<MediaViewerItem> items,
      int initialIndex = 0,
      bool canDownload = true,
    }) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: MediaViewerScreen(
          items: items,
          initialIndex: initialIndex,
          canDownload: canDownload,
        ),
      ));
      await tester.pump();
    }

    testWidgets('an image is zoomable and offers a download', (tester) async {
      await pumpViewer(tester, items: const [
        MediaViewerItem(source: _spacesImage, isVideo: false),
      ]);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      // Nothing to count through with one attachment.
      expect(find.textContaining(' of '), findsNothing);
    });

    testWidgets('several attachments are counted from the opening one',
        (tester) async {
      await pumpViewer(
        tester,
        items: const [
          MediaViewerItem(source: _spacesImage, isVideo: false),
          MediaViewerItem(source: _spacesImage, isVideo: false),
          MediaViewerItem(source: _spacesImage, isVideo: false),
        ],
        initialIndex: 1,
      );

      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('a post opens the same viewer without a download action',
        (tester) async {
      await pumpViewer(
        tester,
        items: const [MediaViewerItem(source: _spacesImage, isVideo: false)],
        canDownload: false,
      );

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsNothing);
    });

    testWidgets('a download already running shows as progress, not a button',
        (tester) async {
      // A download outlives the route that started it, so reopening the viewer
      // on the same attachment has to resume its state rather than offer to
      // start a second copy of it.
      MediaDownloader.instance.progress.value = {
        chatMediaUrl(_spacesImage): 0.4
      };

      await pumpViewer(tester, items: const [
        MediaViewerItem(source: _spacesImage, isVideo: false),
      ]);

      expect(find.byIcon(Icons.download_rounded), findsNothing);
      final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(indicator.value, 0.4);
    });

    testWidgets('an unknown download size spins rather than sitting at zero',
        (tester) async {
      // 0 is "started, size unknown" - a response with no Content-Length.
      MediaDownloader.instance.progress.value = {chatMediaUrl(_spacesImage): 0};

      await pumpViewer(tester, items: const [
        MediaViewerItem(source: _spacesImage, isVideo: false),
      ]);

      final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(indicator.value, isNull);
    });
  });

  group('a message bubble', () {
    Future<void> pumpBubble(WidgetTester tester, MessageContent content) async {
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
                messageContent: content,
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

    testWidgets('tapping a photo opens it full screen', (tester) async {
      await pumpBubble(tester, _message(type: "image", content: _spacesImage));

      // The tile, not the Image: a network image that never resolves renders
      // at zero opacity, which ignores pointers - the tile around it is what
      // carries the tap.
      await tester.tap(find
          .ancestor(
            of: find.byType(CLNetworkImage),
            matching: find.byType(GestureDetector),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.byType(MediaViewerScreen), findsOneWidget);
    });

    testWidgets('a file card is tappable', (tester) async {
      // It used to render with `onPressed: () {}` - a card that looked like a
      // button and did nothing at all when tapped.
      await pumpBubble(
          tester, _message(type: "application/pdf", content: _spacesFile));

      expect(find.text('report.pdf'), findsOneWidget);
      // By name, not byType: the bubble also carries the reply affordance,
      // which is an ElevatedButton too.
      final card = tester.widget<ElevatedButton>(_fileCard);
      expect(card.onPressed, isNotNull);
    });

    testWidgets('a file being downloaded shows progress on its card',
        (tester) async {
      MediaDownloader.instance.progress.value = {_spacesFile: 0.25};
      await pumpBubble(
          tester, _message(type: "application/pdf", content: _spacesFile));

      expect(find.byIcon(Icons.file_copy_outlined), findsNothing);
      final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(indicator.value, 0.25);
    });

    testWidgets('long-pressing an attachment offers Save', (tester) async {
      await pumpBubble(
          tester, _message(type: "application/pdf", content: _spacesFile));

      await tester.longPress(_fileCard);
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('long-pressing plain text does not', (tester) async {
      await pumpBubble(tester, _message(type: "text", content: "hello"));

      await tester.longPress(find.text('hello'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });
}
