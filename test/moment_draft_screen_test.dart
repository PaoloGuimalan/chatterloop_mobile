import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/moment_draft.dart';
import 'package:chatterloop_app/core/media/widgets/timeline_view.dart';
import 'package:chatterloop_app/views/moments/create_moment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory directory;
  late MomentDraftStore store;
  late Composition edit;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moment-screen-');
    final photo = File('${directory.path}/photo.png');
    await photo.writeAsBytes(img.encodePng(img.Image(width: 8, height: 8)));
    edit = Composition(orientation: CanvasOrientation.landscape, clips: [
      MediaLayer(
          source: MediaSource(
              path: photo.path, kind: MediaKind.image, width: 8, height: 8)),
    ]);
    store = MomentDraftStore(
        ownerId: 'account|entity', directoryProvider: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  // File operations finish on the real event loop; store queue continuations
  // created by a widget run in its fake-async zone. Pump both until the actual
  // operation completes instead of awaiting one zone from the other.
  Future<MomentDraft?> readDraft(WidgetTester tester) async {
    MomentDraft? snapshot;
    Object? failure;
    var done = false;
    store.load().then((value) {
      snapshot = value;
      done = true;
    }, onError: (Object error) {
      failure = error;
      done = true;
    });
    final elapsed = Stopwatch()..start();
    while (!done && elapsed.elapsed < const Duration(seconds: 10)) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    expect(done, isTrue, reason: 'draft queue should settle');
    if (failure != null) throw failure!;
    return snapshot;
  }

  Future<void> open(WidgetTester tester, {Composition? initialEdit}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Moment home'))),
      GoRoute(
          path: '/editor',
          builder: (_, __) =>
              CreateMomentScreen(initialEdit: initialEdit, draftStore: store)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: buildCLTheme(Brightness.dark), routerConfig: router));
    router.push('/editor').ignore();
    await tester.pump();
    await readDraft(tester);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await readDraft(tester);
    await tester.pump();
  }

  testWidgets('restores landscape framing, caption, privacy and replies',
      (tester) async {
    await tester.runAsync(() => store.save(MomentDraft(
        edit: edit,
        caption: 'Continue this edit',
        audience: 'connections',
        allowReplies: false,
        position: const Duration(seconds: 2))));
    await open(tester);
    final timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.edit.orientation, CanvasOrientation.landscape);
    expect(timeline.position.value, const Duration(seconds: 2));
    expect(find.text('Continue this edit'), findsOneWidget);
    expect(find.text('Replies off'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('autosaves caption changes with the complete edit',
      (tester) async {
    await open(tester, initialEdit: edit);
    await tester.enterText(find.byType(TextField), 'Updated caption');
    await tester.pump(const Duration(seconds: 1));
    final saved = await readDraft(tester);
    expect(saved?.caption, 'Updated caption');
    expect(saved?.edit.orientation, CanvasOrientation.landscape);
    expect(saved?.edit.clips, hasLength(1));
    await unmount(tester);
  });

  testWidgets('discard leaves the editor and cannot be recreated by autosave',
      (tester) async {
    await open(tester, initialEdit: edit);
    await tester.enterText(find.byType(TextField), 'Discard me');
    await tester.tap(find.byTooltip('Close editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await readDraft(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Moment home'), findsOneWidget);
    expect(await readDraft(tester), isNull);
    await unmount(tester);
  });

  testWidgets('removing the last clip does not resurrect an older draft',
      (tester) async {
    await tester.runAsync(() => store.save(MomentDraft(
        edit: edit,
        caption: '',
        audience: 'public',
        allowReplies: true,
        position: Duration.zero)));
    await open(tester);
    await tester.tap(find.text('6s'));
    await tester.pump();
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(seconds: 1));
    final saved = await readDraft(tester);
    expect(saved?.edit.clips, isEmpty);
    expect(find.text('Add photos and videos'), findsOneWidget);
    await unmount(tester);
  });
}
