// The editor's timeline widget: cards for clips, layers and songs, picking,
// trimming by the handles, holding a card to move it - along its row or to
// another - dragging a song, scrubbing.
//
// Video clips only: a photo card draws the photo's file, which a test has
// none of.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/timeline.dart';
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

/// Songs on the first lane at 1..4s and 5..7s.
final _twoSongs = _edit.copyWith(audio: [
  ..._edit.audio,
  AudioTrack(
    path: '/in/other.mp3',
    name: 'Winter',
    fileLength: _s(60),
    start: _s(5),
    trim: TrimRange(Duration.zero, _s(2)),
  ),
]);

/// A 3s layer at 1s on the first lane, a 5s one at 2s on the lane over it,
/// and the songs of [_twoSongs] with the second on a lane of its own.
final _layered = _edit.copyWith(
  overlays: [
    OverlayClip(
      clip: MediaLayer(source: _video('x'), trim: TrimRange(Duration.zero, _s(3))),
      start: _s(1),
    ),
    OverlayClip(
      clip: MediaLayer(source: _video('y'), trim: TrimRange(Duration.zero, _s(5))),
      start: _s(2),
      lane: 1,
    ),
  ],
  audio: [
    _twoSongs.audio[0],
    _twoSongs.audio[1].copyWith(start: _s(2), lane: 1),
  ],
);

class _Harness {
  _Harness(this.edit);

  Composition edit;
  TimelineSelection? selection;
  final seeks = <Duration>[];
  final position = ValueNotifier(Duration.zero);
  int ends = 0;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  TimelineSelection? selection,
  Composition? edit,
  double? maxHeight,
}) async {
  tester.view.physicalSize = const Size(1000, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final h = _Harness(edit ?? _edit)..selection = selection;
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
            maxHeight: maxHeight,
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

  testWidgets('a text layer shows its words on its card', (tester) async {
    await _pump(tester,
        edit: _edit.copyWith(overlays: [
          OverlayClip(
            clip: MediaLayer(
                source: _video('t'), trim: TrimRange(Duration.zero, _s(3))),
            text: const TextCard(text: 'Hello\nthere'),
          ),
        ]));
    expect(find.text('Hello there'), findsOneWidget);
    expect(find.byIcon(Icons.text_fields_rounded), findsOneWidget);
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

  testWidgets('layers over the clips, the top lane highest; songs under, '
      'lane by lane', (tester) async {
    await _pump(tester, edit: _layered);
    double top(String text) => tester.getRect(find.text(text)).top;
    expect(top('5s'), lessThan(top('3s')));
    expect(top('3s'), lessThan(top('2s')));
    expect(top('2s'), lessThan(top('Summer')));
    expect(top('Summer'), lessThan(top('Winter')));
  });

  testWidgets('more lanes than the height it is given: they scroll',
      (tester) async {
    await _pump(tester, edit: _layered, maxHeight: 120);
    expect(TimelineView.heightFor(_layered), greaterThan(120));
    expect(tester.getSize(find.byType(TimelineView)).height, 120);
    // Sideways for time, and up and down for the lanes.
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
  });

  testWidgets('hold a clip and drag it above the top: a layer of its own',
      (tester) async {
    final h = await _pump(tester);
    final first = tester.getCenter(find.text('4s').first);
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    // Up out of its row, over the ruler.
    await gesture.moveTo(Offset(first.dx, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // Out of the run, over where it played.
    expect(h.edit.clips.map((c) => c.source.path), ['/in/b.mp4', '/in/c.mp4']);
    final layer = h.edit.overlays.single;
    expect(layer.clip.source.path, '/in/a.mp4');
    expect((layer.lane, layer.start), (0, Duration.zero));
    expect(h.selection, const TimelineSelection.overlay(0));
    expect(h.ends, 1);
  });

  testWidgets('hold a layer and drag it down: into the clips', (tester) async {
    final h = await _pump(tester,
        edit: _edit.copyWith(overlays: [_layered.overlays.first]));
    final layer = tester.getCenter(find.text('3s'));
    final gesture = await tester.startGesture(layer);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // Its middle (2.5s) past the first clip's (2s): in after it.
    expect(h.edit.overlays, isEmpty);
    expect(h.edit.clips.map((c) => c.source.path),
        ['/in/a.mp4', '/in/x.mp4', '/in/b.mp4', '/in/c.mp4']);
    expect(h.selection, const TimelineSelection.clip(1));
  });

  testWidgets('hold a song and drag it below the others: a lane of its own',
      (tester) async {
    final h = await _pump(tester, edit: _twoSongs);
    final song = tester.getCenter(find.text('Winter'));
    final gesture = await tester.startGesture(song);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(h.edit.audioLanes, 2);
    final winter = h.edit.audio.firstWhere((t) => t.name == 'Winter');
    expect((winter.lane, winter.start), (1, _s(5)));
    expect(h.selection, TimelineSelection.track(h.edit.audio.indexOf(winter)));
  });

  testWidgets('a picked clip slides along its row, leaving a blank behind',
      (tester) async {
    final h = await _pump(tester, selection: const TimelineSelection.clip(2));
    // The last clip (2s at 8s) dragged 1.5s on.
    await tester.drag(find.text('2s'), const Offset(pps * 1.5, 0));
    await tester.pump();
    expect(h.edit.clipStarts, [Duration.zero, _s(4), _s(9.5)]);
    expect(h.edit.clips[2].gapBefore, _s(1.5));
    // Its card moved with it: a blank shows before it.
    final second = tester.getRect(find.text('4s').last);
    final third = tester.getRect(find.text('2s'));
    expect(third.left - second.left, closeTo(pps * 5.5, 1));
    expect(h.ends, 1);
  });

  testWidgets('dragged back near its neighbour, it does not stick',
      (tester) async {
    final h = await _pump(tester,
        edit: _edit.slideClip(2, _s(2), maxTotal: const Duration(minutes: 2)),
        selection: const TimelineSelection.clip(2));
    // The timeline following the playhead to 5s, the clip at 10s in view.
    h.position.value = _s(5);
    await tester.pump();
    // 1.9s back: 0.1s short of the clip before - that blank stays.
    await tester.drag(find.text('2s'), const Offset(-pps * 1.9, 0));
    await tester.pump();
    expect(h.edit.clips[2].gapBefore, _s(0.1));
  });
}
