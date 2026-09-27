// The New Moment screen: how it lays out upright and on its side, and Undo /
// Redo stepping through the edits.
//
// Video clips only: a photo draws its file, which a test has none of (and
// the videos' players never start here - the canvas shows them black).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/edit_canvas.dart';
import 'package:chatterloop_app/core/media/widgets/timeline_view.dart';
import 'package:chatterloop_app/views/moments/create_moment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> _pump(WidgetTester tester, Size size, {Composition? edit}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.dark),
    home: CreateMomentScreen(initialEdit: edit),
  ));
  await tester.pump();
}

void main() {
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

  testWidgets('upright, editing: the canvas over the timeline',
      (tester) async {
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
    IconButton button(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
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
