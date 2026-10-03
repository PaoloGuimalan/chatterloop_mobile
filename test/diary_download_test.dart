// Saving a diary entry's attachments through the app's own downloader.
//
// The entry screen reads GET diary/<id>/ itself, so the user_service client is
// given an adapter that answers from memory (interceptors cleared: they read
// secure storage and the device token, which don't exist under test). Only a
// plain file attachment is pumped - the image and video players need platform
// plugins a widget test doesn't have.

import 'dart:convert';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/views/diary/diary_entry_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

const _pdf = 'https://media.example.invalid/uploads/diaries/a1/x/Trip%20plan.pdf';

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = {
      "id": "d1",
      "title": "Holiday",
      "content": "<p>Packing list attached.</p>",
      "entry_date": "2026-10-01",
      "is_private": true,
      "attachments": [
        {
          "id": "a1",
          "url": _pdf,
          "file_name": "Trip plan.pdf",
          "file_type": "application/pdf",
        }
      ],
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpEntry(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  ApiClient.userService.dio
    ..interceptors.clear()
    ..httpClientAdapter = _Adapter();
  await tester.pumpWidget(StoreProvider<AppState>(
    store: appStore,
    child: MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const DiaryEntryScreen(entryId: 'd1'),
    ),
  ));
  for (var i = 0; i < 20 && find.text('Trip plan.pdf').evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() => MediaDownloader.instance.progress.value = const {});

  group('the saved name', () {
    test("a diary attachment's own name wins, made safe for disk", () {
      expect(mediaFileName(_pdf, name: 'Trip: day 1/2.pdf'), 'Trip_ day 1_2.pdf');
    });

    test('without one, the link names it', () {
      expect(mediaFileName(_pdf), 'Trip plan.pdf');
      expect(mediaFileName(_pdf, name: '  '), 'Trip plan.pdf');
    });
  });

  testWidgets('a file attachment offers a download, not a browser link',
      (tester) async {
    await _pumpEntry(tester);

    expect(find.text('Trip plan.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a download already running shows as progress', (tester) async {
    // The download outlives the screen: reopening the entry mid-download
    // picks the ring back up instead of offering a second copy.
    MediaDownloader.instance.progress.value = {chatMediaUrl(_pdf): 0.6};
    await _pumpEntry(tester);

    expect(find.byIcon(Icons.download_rounded), findsNothing);
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, 0.6);
  });
}
