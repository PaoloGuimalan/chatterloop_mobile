import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/views/moments/create_moment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/pending_render_harness.dart';

void main() {
  final harness = PendingRenderHarness();
  setUpAll(harness.install);
  tearDownAll(harness.dispose);
  testWidgets('closing a render settles cancellation before the leave decision',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: CreateMomentScreen(
            initialEdit: Composition(clips: [
      MediaLayer(
          source: MediaSource(
              path: harness.photo.path,
              kind: MediaKind.image,
              width: 8,
              height: 8))
    ]))));
    await tester.pump();
    await tester.tap(find.text('Share'));
    await harness.until(tester, () => harness.activeSession != null);
    await tester.tap(find.byTooltip('Close editor'));
    await harness.until(
        tester, () => find.text('Leave this edit?').evaluate().isNotEmpty);
    expect(harness.cancelled, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Uploading'), findsNothing);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this edit?'), findsNothing);
    expect(find.text('Share'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
