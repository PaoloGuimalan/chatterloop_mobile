import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/views/diary/diary_compose_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleather/fleather.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<GoRouter> open(WidgetTester tester) async {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Diary list'))),
      GoRoute(path: '/new', builder: (_, __) => const DiaryComposeScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    router.push('/new');
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('untouched entry exits without a discard dialog', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Back to diary'));
    await tester.pumpAndSettle();
    expect(find.text('Discard entry?'), findsNothing);
    expect(find.text('Diary list'), findsOneWidget);
  });
  testWidgets('body undo preserves title and keeps its discard protection',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'Remember this');
    await tester.tap(find.byTooltip('Back to diary'));
    await tester.pumpAndSettle();
    expect(find.text('Discard entry?'), findsOneWidget);
    await tester.tap(find.text('Keep writing'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull);
    final controller =
        tester.widget<FleatherEditor>(find.byType(FleatherEditor)).controller;
    controller.replaceText(0, 0, 'Body text',
        selection: const TextSelection.collapsed(offset: 9));
    await tester.pumpAndSettle();
    tester.state<RawEditorState>(find.byType(RawEditor)).requestKeyboard();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
        tester
            .widget<FleatherEditor>(find.byType(FleatherEditor))
            .focusNode!
            .hasFocus,
        isFalse);
    expect(find.text('Remember this'), findsOneWidget);
    expect(
        tester
            .widget<FleatherEditor>(find.byType(FleatherEditor))
            .controller
            .document
            .toPlainText()
            .trim(),
        isEmpty);
    tester.state<RawEditorState>(find.byType(RawEditor)).requestKeyboard();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
        tester
            .widget<FleatherEditor>(find.byType(FleatherEditor))
            .focusNode!
            .hasFocus,
        isFalse);
    expect(
        tester
            .widget<FleatherEditor>(find.byType(FleatherEditor))
            .controller
            .document
            .toPlainText()
            .trim(),
        'Body text');
    await tester.tap(find.byTooltip('Back to diary'));
    await tester.pumpAndSettle();
    expect(find.text('Discard entry?'), findsOneWidget);
  });
}
