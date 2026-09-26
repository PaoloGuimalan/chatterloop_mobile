// The editor's timeline widget: cards for clips and songs, picking, trimming
// by the handles, holding a clip to move it, dragging a song, scrubbing.
//
// Video clips only: a photo card draws the photo's file, which a test has
// none of.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/timeline_view.dart';
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

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// Two 4s clips, then a 2s one; a song from 1s to 4s.
final _edit = Composition(
  clips: [
    MediaLayer(source: _video('a'), trim: TrimRange(Duration.zero, _s(4))),
    MediaLayer(source: _video('b'), trim: TrimRange(Duration.zero, _s(4))),
    MediaLayer(source: _video('c'), trim: TrimRange(Duration.zero, _s(2))),
  ],
  audio: [
    AudioTrack(
      path: '/in/song.mp3',
      name: 'Summer',
      fileLength: _s(60),
      start: _s(1),
      trim: TrimRange(Duration.zero, _s(3)),
    ),
  ],
);

class _Harness {
  Composition edit = _edit;
  TimelineSelection? selection;
  final seeks = <Duration>[];
  final position = ValueNotifier(Duration.zero);
  int ends = 0;
}

Future<_Harness> _pump(WidgetTester tester,
    {TimelineSelection? selection}) async {
  tester.view.physicalSize = const Size(1000, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final h = _Harness()..selection = selection;
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.dark),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: StatefulBuilder(
        builder: (context, setState) => Align(
          alignment: Alignment.topCenter,
          child: TimelineView(
            edit: h.edit,
            position: h.position,
            maxTotal: const Duration(minutes: 2),
            thumbnails: const {},
            selection: h.selection,
            onSelect: (s) => setState(() => h.selection = s),
            onEdit: (e) => setState(() => h.edit = e),
            onEditEnd: () => h.ends++,
            onSeek: h.seeks.add,
            onScrubStart: () {},
            onScrubEnd: () {},
            onAddMedia: () {},
            onAddAudio: () {},
          ),
        ),
      ),
    ),
  ));
  return h;
}

/// A clip card's centre, found by its length badge.
Finder _clip(String length) => find.text(length);

void main() {
  const pps = TimelineView.pxPerSecond;

  testWidgets('a card per clip and per song, as wide as they are long',
      (tester) async {
    await _pump(tester);
    expect(find.text('4s'), findsNWidgets(2));
    expect(find.text('2s'), findsOneWidget);
    expect(find.text('Summer'), findsOneWidget);
    expect(find.byTooltip('Add photos or videos'), findsOneWidget);
    expect(find.byTooltip('Add music'), findsOneWidget);
  });

  testWidgets('tap picks a card; tap again lets it go', (tester) async {
    final h = await _pump(tester);
    await tester.tap(_clip('2s'));
    await tester.pump();
    expect(h.selection, const TimelineSelection.clip(2));
    await tester.tap(find.text('Summer'));
    await tester.pump();
    expect(h.selection, const TimelineSelection.track(0));
    await tester.tap(find.text('Summer'));
    await tester.pump();
    expect(h.selection, isNull);
  });

  testWidgets("a picked clip's end handle trims it", (tester) async {
    final h =
        await _pump(tester, selection: const TimelineSelection.clip(2));
    // The last clip's right edge: its handle sits just inside it.
    final card = tester.getRect(find
        .ancestor(of: _clip('2s'), matching: find.byType(GestureDetector))
        .first);
    await tester.dragFrom(
        Offset(card.right - 4, card.center.dy), const Offset(pps, 0));
    await tester.pump();
    expect(h.edit.clips[2].trim, TrimRange(Duration.zero, _s(3)));
    expect(h.ends, 1);
  });

  testWidgets('hold a clip and drag it: it moves in the order',
      (tester) async {
    final h = await _pump(tester);
    // Scrolled to the start, the first card sits right of the middle line.
    final first = tester.getCenter(find.text('4s').first);
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    // With it lifted out, the others close up: the second clip is 0..4s,
    // the third 4..6s. Its middle moved past the second's middle (2s) but
    // not the third's (5s): it drops between them.
    await gesture.moveBy(const Offset(pps * 1.5, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(pps * 1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(h.edit.clips.map((c) => c.source.path),
        ['/in/b.mp4', '/in/a.mp4', '/in/c.mp4']);
    expect(h.selection, const TimelineSelection.clip(1));
  });

  testWidgets('a picked song drags along the timeline', (tester) async {
    final h =
        await _pump(tester, selection: const TimelineSelection.track(0));
    await tester.drag(find.text('Summer'), const Offset(pps * 2, 0));
    await tester.pump();
    expect(h.edit.audio.single.start, _s(3));
    expect(h.edit.audio.single.trim, TrimRange(Duration.zero, _s(3)));
  });

  testWidgets('dragging the timeline scrubs', (tester) async {
    final h = await _pump(tester);
    // On the ruler, away from the cards.
    await tester.dragFrom(const Offset(900, 6), const Offset(-pps * 2, 0));
    await tester.pumpAndSettle();
    expect(h.seeks, isNotEmpty);
    expect(h.seeks.last.inMilliseconds, closeTo(2000, 60));
  });

  testWidgets('while playing, the timeline follows the playhead',
      (tester) async {
    final h = await _pump(tester);
    h.position.value = _s(5);
    await tester.pump();
    final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView));
    expect(scroll.controller!.offset, closeTo(5 * pps, 0.5));
    // Following isn't the user scrubbing.
    expect(h.seeks, isEmpty);
  });
}
