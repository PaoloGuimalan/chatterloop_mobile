// The moments viewer's slides (lib/views/moments/moment_route.dart): up
// from the bottom when opened; out to the left as the next person's come in
// from the right (and the other way for the previous); down and away when
// dragged down, following the finger.

import 'package:chatterloop_app/views/moments/moment_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router() => GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (c, s) => const Scaffold(body: Text('feed'))),
      GoRoute(
        path: '/m/:id',
        pageBuilder: (c, s) => MomentPage(
          key: s.pageKey,
          slide:
              s.extra is MomentSlide ? s.extra as MomentSlide : MomentSlide.open,
          child: Scaffold(body: Center(child: Text('m-${s.pathParameters['id']}'))),
        ),
      ),
    ]);

/// Where the page holding [text] is moved to, as a share of the screen.
Offset _slide(WidgetTester tester, String text) => tester
    .widget<FractionalTranslation>(find
        .ancestor(of: find.text(text), matching: find.byType(FractionalTranslation))
        .first)
    .translation;

void main() {
  testWidgets('opened, it rises from the bottom', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/m/1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = _slide(tester, 'm-1');
    expect(mid.dx, 0);
    expect(mid.dy, greaterThan(0));
    await tester.pumpAndSettle();
    expect(_slide(tester, 'm-1'), Offset.zero);
  });

  testWidgets('the next person: out left, theirs in from the right - and '
      'the other way for the previous', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/m/1');
    await tester.pumpAndSettle();

    router.pushReplacement('/m/2', extra: MomentSlide.next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_slide(tester, 'm-1').dx, lessThan(0));
    expect(_slide(tester, 'm-2').dx, greaterThan(0));
    expect(_slide(tester, 'm-2').dy, 0);
    await tester.pumpAndSettle();
    expect(find.text('m-1'), findsNothing);

    router.pushReplacement('/m/1', extra: MomentSlide.previous);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_slide(tester, 'm-2').dx, greaterThan(0));
    expect(_slide(tester, 'm-1').dx, lessThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('dragged down it follows the finger, the feed showing under '
      'it; let go early it springs back, far enough it slides away',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/m/1');
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('m-1')))
        as MomentPageRoute;

    expect(route.startDismiss(), isTrue);
    route.updateDismiss(0.3);
    await tester.pump();
    expect(_slide(tester, 'm-1').dy, closeTo(0.3, 0.001));
    expect(find.text('feed'), findsOneWidget);

    route.endDismiss(closing: false);
    await tester.pumpAndSettle();
    expect(_slide(tester, 'm-1'), Offset.zero);

    expect(route.startDismiss(), isTrue);
    route.updateDismiss(0.4);
    await tester.pump();
    route.endDismiss(closing: true);
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // On down from where the finger left it - never back up, never sideways.
    final away = _slide(tester, 'm-1');
    expect(away.dx, 0);
    expect(away.dy, greaterThan(0.4));
    await tester.pumpAndSettle();
    expect(find.text('m-1'), findsNothing);
    expect(find.text('feed'), findsOneWidget);
  });
}
