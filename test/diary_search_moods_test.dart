import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/views/diary/diary_list_view.dart';
import 'package:chatterloop_app/views/diary/widgets/mood_picker_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Interceptor> previous;
  late List<RequestOptions> requests;
  setUp(() {
    previous = List.of(ApiClient.userService.dio.interceptors);
    requests = [];
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        final second = options.queryParameters['page'] == 2;
        final moods = options.path.contains('moods');
        handler.resolve(Response(requestOptions: options, data: {
          'count': 2,
          'next': second ? null : 'page2',
          'results': [
            moods
                ? {
                    'id': second ? 2 : 1,
                    'name': second ? 'Thoughtful' : 'Calm',
                    'emoji': '🌿'
                  }
                : {
                    'id': second ? 'old' : 'new',
                    'title': second ? 'Older searchable memory' : 'Today',
                    'content': '<p>Words</p>',
                    'entry_date': second ? '2025-01-01' : '2026-10-15'
                  }
          ],
        }));
      }));
  });
  tearDown(() {
    ApiClient.userService.dio.interceptors
      ..clear(keepImplyContentTypeInterceptor: false)
      ..addAll(previous);
  });
  testWidgets('search stays within loaded entries until explicit pagination',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light), home: const DiaryListScreen()));
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    await tester.enterText(find.byType(TextField), 'older searchable');
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    expect(find.text('Older searchable memory'), findsNothing);
    await tester.tap(find.text('Load more entries'));
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last.queryParameters['page'], 2);
    expect(find.text('Older searchable memory'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });
  testWidgets('moods use dynamic paginated two-column options', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showMoodPickerSheet(context),
                    child: const Text('Choose mood'))))));
    await tester.tap(find.text('Choose mood'));
    await tester.pumpAndSettle();
    expect(find.text('Calm'), findsOneWidget);
    expect(find.text('Thoughtful'), findsNothing);
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        2);
    await tester.tap(find.text('Load more moods'));
    await tester.pumpAndSettle();
    expect(find.text('Thoughtful'), findsOneWidget);
    expect(requests.last.queryParameters['page'], 2);
  });

  testWidgets('date groups and entries within each group are newest first',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiClient.userService.dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: {
          'next': null,
          'results': [
            {
              'id': 'early',
              'title': 'Earlier same day',
              'content': 'Body',
              'entry_date': '2026-10-20',
              'created_at': '2026-10-20T09:00:00Z'
            },
            {
              'id': 'previous',
              'title': 'Previous day',
              'content': 'Body',
              'entry_date': '2026-10-19',
              'created_at': '2026-10-21T20:00:00Z'
            },
            {
              'id': 'latest',
              'title': 'Latest same day',
              'content': 'Body',
              'entry_date': '2026-10-20',
              'created_at': '2026-10-20T17:00:00Z'
            },
          ],
        }));
      }));
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light), home: const DiaryListScreen()));
    await tester.pumpAndSettle();
    final latest = tester.getTopLeft(find.text('Latest same day')).dy;
    final earlier = tester.getTopLeft(find.text('Earlier same day')).dy;
    final previous = tester.getTopLeft(find.text('Previous day')).dy;
    expect(latest, lessThan(earlier));
    expect(earlier, lessThan(previous));
  });
}
