// The New Moment screen: how it lays out upright and on its side, and Undo /
// Redo stepping through the edits.
//
// Video clips only: a photo draws its file, which a test has none of (and
// the videos' players never start here - the canvas shows them black).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/edit_canvas.dart';
import 'package:chatterloop_app/core/media/widgets/timeline_view.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/views/moments/create_moment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:image/image.dart' as img;

MediaSource _video(String name) => MediaSource(
      path: '/in/$name.mp4',
      kind: MediaKind.video,
      width: 1080,
      height: 1920,
      duration: const Duration(seconds: 20),
      hasAudio: true,
    );

/// A 4s clip, then a 3s one.
final _edit = Composition(clips: [
  MediaLayer(
      source: _video('a'),
      trim: const TrimRange(Duration.zero, Duration(seconds: 4))),
  MediaLayer(
      source: _video('b'),
      trim: const TrimRange(Duration.zero, Duration(seconds: 3))),
]);

/// A phone, logical pixels.
const _onItsSide = Size(915, 412);
const _upright = Size(412, 915);

Future<void> _pump(WidgetTester tester, Size size,
    {Composition? edit, bool openTools = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.dark),
    home: CreateMomentScreen(initialEdit: edit),
  ));
  await tester.pump();
  if (edit != null && openTools) {
    await tester.tap(find.byTooltip('Show editing layers'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('landscape full-preview tools stay above multiline captions',
      (tester) async {
    await _pump(tester, _onItsSide, edit: _edit, openTools: false);
    await tester.enterText(
        find.byType(TextField), 'First line\nSecond line\nThird line');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pumpAndSettle();
    final tools = find
        .ancestor(
            of: find.byTooltip('Reset framing'),
            matching: find.byType(SingleChildScrollView))
        .first;
    await tester.drag(tools, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byTooltip('Reset framing')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
    await tester.tap(find.byTooltip('Reset framing'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditCanvas>(find.byType(EditCanvas))
            .layers
            .first
            .layer
            .transform
            .rotationDeg,
        0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [_upright, _onItsSide]) {
    testWidgets('full-screen editing keeps controls and gestures at $size',
        (tester) async {
      late Directory directory;
      late File photo;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('moment-gesture-');
        photo = File('${directory.path}/photo.png');
        await photo
            .writeAsBytes(img.encodePng(img.Image(width: 100, height: 200)));
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.runAsync(() async {
          for (var attempt = 0;; attempt++) {
            try {
              await directory.delete(recursive: true);
              break;
            } on FileSystemException {
              if (attempt == 20) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        });
      });
      final edit = Composition(clips: [
        MediaLayer(
            source: MediaSource(
                path: photo.path,
                kind: MediaKind.image,
                width: 100,
                height: 200))
      ]);
      await _pump(tester, size, edit: edit, openTools: false);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Canvas orientation'), findsOneWidget);
      expect(find.byTooltip('Rotate'), findsOneWidget);
      expect(
          tester.widget<EditCanvas>(find.byType(EditCanvas)).enabled, isTrue);
      await tester.tap(find.byTooltip('Rotate'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<EditCanvas>(find.byType(EditCanvas))
              .layers
              .single
              .layer
              .transform
              .rotationDeg,
          90);
      final center = tester.getCenter(find.byType(EditCanvas));
      final gesture = await tester.startGesture(center.translate(-25, 0));
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(45, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final transformed = tester
          .widget<EditCanvas>(find.byType(EditCanvas))
          .layers
          .single
          .layer
          .transform;
      expect(transformed.cx, greaterThan(.5));
      expect(transformed.cy, greaterThan(.5));
      await tester.tap(find.byTooltip('Show editing layers'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TimelineView>(find.byType(TimelineView))
              .edit
              .clips
              .single
              .transform,
          transformed);
      expect(find.text('Hide Layers'), findsOneWidget);
      expect(
          find.byIcon(size.width > size.height
              ? Icons.keyboard_arrow_right_rounded
              : Icons.keyboard_arrow_down_rounded),
          findsOneWidget);
      await tester.tap(find.byTooltip('Hide editing layers'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<EditCanvas>(find.byType(EditCanvas))
              .layers
              .single
              .layer
              .transform,
          transformed);
      expect(
          tester.widget<EditCanvas>(find.byType(EditCanvas)).enabled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'full preview controls do not overlap on a narrow phone with larger text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, const Size(320, 568), edit: _edit, openTools: false);
    final toggle = tester.getRect(find.byTooltip('Show editing layers'));
    final clock = tester.getRect(find.text('0:00 / 0:07'));
    expect(toggle.right, lessThanOrEqualTo(clock.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'caption keyboard keeps portrait editing below the canvas without overflow',
      (tester) async {
    await _pump(tester, const Size(390, 844), edit: _edit);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TimelineView)).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(EditCanvas)).bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'moment opens with full preview and toggles editing tools without changing layers',
      (tester) async {
    final edit = _edit.copyWith(overlays: [
      OverlayClip(
          clip: MediaLayer(
              source: _video('overlay'),
              trim: const TrimRange(Duration.zero, Duration(seconds: 3))))
    ]);
    await _pump(tester, _upright, edit: edit, openTools: false);
    expect(find.byType(TimelineView), findsNothing);
    final full = tester.getSize(find.byType(EditCanvas));
    expect(full.height, greaterThan(650));
    expect(tester.widget<EditCanvas>(find.byType(EditCanvas)).enabled, isTrue);
    expect(find.text('Edit layers'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    final sources = tester
        .widget<EditCanvas>(find.byType(EditCanvas))
        .layers
        .map((layer) => layer.layer.source.path)
        .toList();
    await tester.tap(find.byTooltip('Show editing layers'));
    await tester.pumpAndSettle();
    final timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.edit, same(edit));
    timeline.onSeek(const Duration(seconds: 2));
    timeline.onSelect(const TimelineSelection.overlay(0));
    await tester.pump();
    expect(tester.widget<EditCanvas>(find.byType(EditCanvas)).enabled, isTrue);
    expect(
        tester.getSize(find.byType(EditCanvas)).height, lessThan(full.height));
    await tester.tap(find.byTooltip('Hide editing layers'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsNothing);
    final canvas = tester.widget<EditCanvas>(find.byType(EditCanvas));
    expect(canvas.layers.map((layer) => layer.layer.source.path), sources);
    expect(canvas.outlined, 1);
    expect(tester.getSize(find.byType(EditCanvas)), full);
    await tester.tap(find.byTooltip('Show editing layers'));
    await tester.pumpAndSettle();
    final reopened = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(reopened.position.value, const Duration(seconds: 2));
    final scroller = tester.widget<SingleChildScrollView>(find.descendant(
        of: find.byType(TimelineView),
        matching: find.byWidgetPredicate((widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal)));
    expect(
        scroller.controller!.offset, closeTo(2 * TimelineView.pxPerSecond, .5));
    expect(reopened.selection, const TimelineSelection.overlay(0));
    expect(tester.widget<EditCanvas>(find.byType(EditCanvas)).outlined, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing tray moves beside the canvas when the phone rotates',
      (tester) async {
    await _pump(tester, _upright, edit: _edit, openTools: false);
    await tester.tap(find.byTooltip('Show editing layers'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = _onItsSide;
    await tester.pumpAndSettle();
    var canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(9 / 16, 0.01));
    expect(tester.getRect(find.byType(TimelineView)).left,
        greaterThanOrEqualTo(canvas.right));
    await tester.tap(find.byTooltip('Hide editing layers'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsNothing);
    canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(9 / 16, 0.01));
    tester.view.physicalSize = _upright;
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'landscape composition stays uncropped in preview and its editing tray',
      (tester) async {
    final edit = _edit.copyWith(orientation: CanvasOrientation.landscape);
    await _pump(tester, _onItsSide, edit: edit, openTools: false);
    var canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(16 / 9, 0.01));
    expect(canvas.width, greaterThan(600));
    await tester.tap(find.byTooltip('Show editing layers'));
    await tester.pumpAndSettle();
    canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(16 / 9, 0.01));
    expect(tester.getRect(find.byType(TimelineView)).left,
        greaterThanOrEqualTo(canvas.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits over two minutes remain exportable with sharing explained',
      (tester) async {
    final longEdit = Composition(clips: [
      MediaLayer(
          source: MediaSource(
        path: '/in/long.mp4',
        kind: MediaKind.video,
        width: 1080,
        height: 1920,
        duration: const Duration(minutes: 6),
      )),
    ]);
    await _pump(tester, _upright, edit: longEdit);
    final share = tester.widget<CLBtn>(find.widgetWithText(CLBtn, 'Share'));
    expect(share.onPressed, isNull);
    expect(find.textContaining('Export only'), findsOneWidget);
    expect(find.textContaining('2 minutes'), findsWidgets);
    final save = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Save to device'),
        matching: find.byType(IconButton)));
    expect(save.onPressed, isNotNull);
    final timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.maxTotal, greaterThan(const Duration(minutes: 6)));
  });

  testWidgets('exactly two minutes can still be shared', (tester) async {
    final atLimit = Composition(clips: [
      MediaLayer(
          source: MediaSource(
        path: '/in/limit.mp4',
        kind: MediaKind.video,
        width: 1080,
        height: 1920,
        duration: const Duration(minutes: 2),
      ))
    ]);
    await _pump(tester, _upright, edit: atLimit);
    final share = tester.widget<CLBtn>(find.widgetWithText(CLBtn, 'Share'));
    expect(share.onPressed, isNotNull);
    expect(find.textContaining('Export only'), findsNothing);
  });

  testWidgets('failed previews expose recovery on the ordinary editing canvas',
      (tester) async {
    await _pump(tester, _upright, edit: _edit);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't preview this clip."), findsOneWidget);
    expect(find.text('Retry preview'), findsOneWidget);
    await tester.tap(find.text('Remove clip'));
    await tester.pumpAndSettle();
    final timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.edit.clips, hasLength(1));
    expect(timeline.edit.clips.single.source.path, '/in/b.mp4');
  });

  testWidgets(
      'landscape canvas fits either phone layout and orientation is undoable',
      (tester) async {
    await _pump(tester, _upright, edit: _edit);
    final orientationButton = find.byTooltip('Canvas orientation');
    final backgroundButton = find.byTooltip('Background');
    final preview = tester.getRect(find.byType(EditCanvas));
    expect(preview.contains(tester.getCenter(orientationButton)), isTrue);
    expect(tester.getCenter(orientationButton).dx,
        tester.getCenter(backgroundButton).dx);
    expect(tester.getCenter(orientationButton).dy,
        lessThan(tester.getCenter(backgroundButton).dy));
    await tester.tap(find.byTooltip('Canvas orientation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Landscape (16:9)'));
    await tester.pumpAndSettle();
    var canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(16 / 9, 0.01));
    var timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.edit.orientation, CanvasOrientation.landscape);
    await tester.ensureVisible(backgroundButton);
    await tester.pumpAndSettle();
    expect(
        tester
            .getRect(find.byType(EditCanvas))
            .contains(tester.getCenter(backgroundButton)),
        isTrue);

    tester.view.physicalSize = _onItsSide;
    await tester.pumpAndSettle();
    canvas = tester.getRect(find.byType(EditCanvas));
    expect(canvas.width / canvas.height, closeTo(16 / 9, 0.01));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    timeline = tester.widget<TimelineView>(find.byType(TimelineView));
    expect(timeline.edit.orientation, CanvasOrientation.portrait);
  });

  testWidgets('on its side, picking: the whole width, not a 9:16 sliver',
      (tester) async {
    await _pump(tester, _onItsSide);
    expect(tester.takeException(), isNull);
    final title = find.text('Add photos and videos');
    expect(title, findsOneWidget);
    final stage = tester.getRect(
        find.ancestor(of: title, matching: find.byType(ClipRRect)).first);
    expect(stage.width, greaterThan(_onItsSide.width - 40));
  });

  testWidgets(
      "on its side, editing: the canvas the screen's height, the rest "
      'beside it', (tester) async {
    await _pump(tester, _onItsSide, edit: _edit);
    expect(tester.takeException(), isNull);
    final canvas = tester.getRect(find.byType(EditCanvas));
    final timeline = tester.getRect(find.byType(TimelineView));
    expect(canvas.height, greaterThan(_onItsSide.height - 40));
    expect(canvas.width / canvas.height, closeTo(9 / 16, 0.01));
    expect(timeline.left, greaterThanOrEqualTo(canvas.right));
    expect(find.byTooltip('Undo'), findsOneWidget);
  });

  testWidgets('upright, editing: the canvas over the timeline', (tester) async {
    await _pump(tester, _upright, edit: _edit);
    expect(tester.takeException(), isNull);
    final canvas = tester.getRect(find.byType(EditCanvas));
    final timeline = tester.getRect(find.byType(TimelineView));
    expect(timeline.top, greaterThanOrEqualTo(canvas.bottom));
    expect(canvas.height, greaterThan(400));
  });

  testWidgets('with nothing picked, the bar offers clips, a layer and music',
      (tester) async {
    await _pump(tester, _upright, edit: _edit);
    expect(find.text('Clips'), findsOneWidget);
    expect(find.text('Layer'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('undo and redo step through the edits', (tester) async {
    await _pump(tester, _upright, edit: _edit);
    IconButton button(String tooltip) =>
        tester.widget<IconButton>(find.ancestor(
            of: find.byTooltip(tooltip), matching: find.byType(IconButton)));
    // Nothing done yet.
    expect(button('Undo').onPressed, isNull);
    expect(button('Redo').onPressed, isNull);

    // The first clip picked, then deleted.
    await tester.tap(find.text('4s'));
    await tester.pump();
    // At the end of the picked clip's tools - scrolled to on a narrow
    // screen.
    await tester.ensureVisible(find.text('Delete'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('4s'), findsNothing);
    expect(button('Undo').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('4s'), findsOneWidget);
    expect(button('Redo').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('4s'), findsNothing);
    expect(button('Redo').onPressed, isNull);
  });
}
