import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/user_app_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter shortcutRouter() => GoRouter(initialLocation: '/account', routes: [
      GoRoute(
          path: '/account',
          builder: (_, __) => Scaffold(
                appBar: AppBar(title: const Text('Account apps')),
                body: UserAppShortcuts(onSettings: () {}),
              )),
      GoRoute(
          path: '/servers',
          builder: (_, __) =>
              const Scaffold(body: Text('Servers welcome tab'))),
      GoRoute(
          path: '/server-browser',
          builder: (_, __) => const Scaffold(body: Text('Server browser'))),
      GoRoute(
          path: '/diary',
          builder: (_, __) => const Scaffold(body: Text('Diary destination'))),
    ]);

void main() {
  testWidgets('Servers shortcut opens the full browser directly',
      (tester) async {
    final router = shortcutRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servers'));
    await tester.pumpAndSettle();
    expect(find.text('Server browser'), findsOneWidget);
    expect(find.text('Servers welcome tab'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Account apps'), findsOneWidget);
  });
  testWidgets('Diary opens and Notes remains unavailable', (tester) async {
    final router = shortcutRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.light), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Account apps'), findsOneWidget);
    await tester.tap(find.text('Diary'));
    await tester.pumpAndSettle();
    expect(find.text('Diary destination'), findsOneWidget);
  });
}
