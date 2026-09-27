// The timeline's edits (lib/core/media/timeline.dart): what the editor's
// cards do to the edit - reorder, trim, slide, split and remove clips; place,
// trim, split, stack and remove layers; place, trim, split and remove songs,
// in lanes - and the rules they keep, blanks among them.

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo = MediaSource(
    path: '/in/photo.jpg', kind: MediaKind.image, width: 1600, height: 1200);

const _video = MediaSource(
  path: '/in/clip.mp4',
  kind: MediaKind.video,
  width: 1280,
  height: 720,
  duration: Duration(seconds: 20),
  hasAudio: true,
);

Duration _s(num seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

/// The most a Moment may be.
const _max = Duration(minutes: 2);

AudioTrack _song(num start, num length,
        {String path = '/in/song.mp3', num from = 0, int lane = 0}) =>
    AudioTrack(
      path: path,
      fileLength: _s(60),
      start: _s(start),
      lane: lane,
      trim: TrimRange(_s(from), _s(from + length)),
    );

/// A photo laid over the clips, [length]s long from [start].
OverlayClip _layer(num start, num length, {int lane = 0}) => OverlayClip(
      clip: MediaLayer(source: _photo, duration: _s(length)),
      start: _s(start),
      lane: lane,
    );

/// A photo clip [length]s long, after a blank of [gap]s.
MediaLayer _still(num length, {num gap = 0}) =>
    MediaLayer(source: _photo, duration: _s(length), gapBefore: _s(gap));

/// A 6s photo, a video's 4..10 (6s), a 3s photo: 15s.
Composition _edit({
  List<AudioTrack> audio = const [],
  List<OverlayClip> overlays = const [],
}) =>
    Composition(
      clips: [
        const MediaLayer(source: _photo),
        MediaLayer(source: _video, trim: TrimRange(_s(4), _s(10))),
        MediaLayer(source: _photo, duration: _s(3)),
      ],
      overlays: overlays,
      audio: audio,
    );

void main() {
  group('clips', () {
    test('move to a new place in the order', () {
      final moved = _edit().moveClip(0, 2);
      expect(moved.clips.map((c) => c.length), [_s(6), _s(3), _s(6)]);
      expect(moved.clips[2].source, _photo);
      expect(moved.clips[0].source, _video);
      final edit = _edit();
      expect(identical(edit.moveClip(1, 1), edit), isTrue);
    });

    test('removing the last one leaves nothing - unless layers or songs are '
        'left', () {
      expect(_edit().removeClip(1)!.clips, hasLength(2));
      expect(const Composition(clips: [MediaLayer(source: _photo)])
          .removeClip(0), isNull);
      // A song stays: the moment is it, over black.
      final song = Composition(
        clips: const [MediaLayer(source: _photo)],
        audio: [_song(0, 10)],
      ).removeClip(0)!;
      expect(song.clips, isEmpty);
      expect(song.naturalDuration, _s(10));
    });

    test('added clips go in where asked, else at the end', () {
      const extra = MediaLayer(source: _photo, duration: Duration(seconds: 1));
      expect(_edit().insertClips([extra], index: 1).clips[1], extra);
      expect(_edit().insertClips([extra]).clips.last, extra);
    });

    test('split at the playhead: two clips, the same media either side', () {
      // 8s in: 2s into the video's 4..10.
      final split = _edit().splitAt(_s(8))!;
      expect(split.clips, hasLength(4));
      expect(split.clips[1].trim, TrimRange(_s(4), _s(6)));
      expect(split.clips[2].trim, TrimRange(_s(6), _s(10)));
      expect(split.naturalDuration, _edit().naturalDuration);
      // A photo splits into two stills.
      final photo = _edit().splitAt(_s(2))!;
      expect(photo.clips[0].length, _s(2));
      expect(photo.clips[1].length, _s(4));
    });

    test('no split right at a clip edge, or in a blank', () {
      expect(_edit().splitAt(_s(6)), isNull);
      expect(_edit().splitAt(_s(6.2)), isNull);
      expect(_edit().splitAt(_s(11.9)), isNull);
      final blank = Composition(clips: [_still(3), _still(3, gap: 2)]);
      expect(blank.splitAt(_s(4)), isNull);
    });

    test('trimming a video: into its own length, never under half a second',
        () {
      // Front trimmed by 2s.
      expect(_edit().resizeClip(1, head: _s(2), maxTotal: _max).clips[1].trim,
          TrimRange(_s(6), _s(10)));
      // Given back past its start: stops at 0.
      expect(_edit().resizeClip(1, head: _s(-9), maxTotal: _max).clips[1].trim,
          TrimRange(Duration.zero, _s(10)));
      // Its end past the file's: stops at 20s.
      expect(_edit().resizeClip(1, tail: _s(50), maxTotal: _max).clips[1].trim,
          TrimRange(_s(4), _s(20)));
      // Squeezed: half a second is left.
      expect(
          _edit().resizeClip(1, tail: _s(-50), maxTotal: _max).clips[1].length,
          minPiece);
    });

    test('a photo is stretched or shortened by either end', () {
      expect(_edit().resizeClip(0, tail: _s(4), maxTotal: _max).clips[0].length,
          _s(10));
      expect(_edit().resizeClip(0, head: _s(4), maxTotal: _max).clips[0].length,
          _s(2));
      expect(
          _edit().resizeClip(0, head: _s(40), maxTotal: _max).clips[0].length,
          minPiece);
    });

    test('a clip only grows into the room the run has left', () {
      // 15s of a 20s cap: 5s of room.
      final cap = _s(20);
      expect(_edit().remaining(cap), _s(5));
      expect(_edit().resizeClip(0, tail: _s(30), maxTotal: cap).clips[0].length,
          _s(11));
      expect(_edit().resizeClip(1, tail: _s(30), maxTotal: cap).clips[1].trim,
          TrimRange(_s(4), _s(15)));
      expect(_edit().resizeClip(1, head: _s(-30), maxTotal: cap).clips[1].trim,
          TrimRange(Duration.zero, _s(10)));
    });
  });

  group('blanks', () {
    test('the moment runs to whatever ends last; a blank plays no clip', () {
      final edit = Composition(
        clips: [_still(3, gap: 2)],
        audio: [_song(0, 10)],
      );
      expect(edit.clipStarts, [_s(2)]);
      expect(edit.mainEnd, _s(5));
      expect(edit.naturalDuration, _s(10));
      expect(edit.locate(_s(1)), isNull);
      expect(edit.locate(_s(3)), (index: 0, offset: _s(1)));
      expect(edit.locate(_s(6)), isNull);
      // A layer past everything runs it on further.
      expect(edit.copyWith(overlays: [_layer(8, 5)]).naturalDuration, _s(13));
    });

    test('a picked clip slides into the blank beside it; the others stay put',
        () {
      // The last photo slid on by 2s: a blank before it.
      final slid = _edit().slideClip(2, _s(2), maxTotal: _max);
      expect(slid.clipStarts, [Duration.zero, _s(6), _s(14)]);
      expect(slid.mainEnd, _s(17));
      // The video slid on by 1s: the photo after it stays where it is.
      expect(slid.slideClip(1, _s(1), maxTotal: _max).clipStarts,
          [Duration.zero, _s(7), _s(14)]);
      // Run into the next one, it pushes it on - never over it.
      expect(slid.slideClip(1, _s(5), maxTotal: _max).clipStarts,
          [Duration.zero, _s(11), _s(17)]);
      // Back, it pushes the ones before it to the start.
      expect(slid.slideClip(2, _s(-20), maxTotal: _max).clipStarts,
          [Duration.zero, _s(6), _s(12)]);
      // Nor back before the start.
      final edit = _edit();
      expect(identical(edit.slideClip(0, _s(-3), maxTotal: _max), edit), isTrue);
      // Nor the last past the most a moment can be.
      expect(_edit().slideClip(2, _s(10), maxTotal: _s(20)).mainEnd, _s(20));
    });

    test('slid near a neighbour, it does not stick: any blank stays; the '
        'blanks either side, to anchor it', () {
      final slid = _edit().slideClip(2, _s(2), maxTotal: _max);
      final near = slid.slideClip(2, _s(-1.99), maxTotal: _max);
      expect(near.clipStarts, [Duration.zero, _s(6), _s(12.01)]);
      expect(near.clipBlanks(2), (before: _s(0.01), first: false, after: null));
      expect(near.clipBlanks(1), (before: Duration.zero, first: false,
          after: _s(0.01)));
      expect(near.clipBlanks(0).first, isTrue);
      // Anchored: slid back by just that blank.
      expect(near.slideClip(2, -_s(0.01), maxTotal: _max).clipStarts,
          [Duration.zero, _s(6), _s(12)]);
    });

    test('taking a clip out closes up behind it; the blank before it stays',
        () {
      final edit = Composition(clips: [_still(3), _still(3, gap: 2), _still(3)]);
      expect(edit.removeClip(1)!.clipStarts, [Duration.zero, _s(5)]);
      // Moved to the front: in straight at the start, its blank left behind.
      expect(edit.moveClip(1, 0).clipStarts, [Duration.zero, _s(3), _s(8)]);
    });

    test('trimming a clip carries the ones after it along, blanks and all',
        () {
      final edit = Composition(clips: [_still(3), _still(3, gap: 2)]);
      expect(edit.resizeClip(0, tail: _s(1), maxTotal: _max).clipStarts,
          [Duration.zero, _s(6)]);
    });

    test('clips added go in straight after the one before', () {
      final edit = Composition(clips: [_still(3), _still(3, gap: 2)]);
      final added = edit.insertClips([_still(1, gap: 5)], index: 1);
      // The new one sits against the first; the blank stays before the
      // clip it was before.
      expect(added.clipStarts, [Duration.zero, _s(3), _s(6)]);
    });
  });

  group('audio', () {
    test('a new song goes in at the playhead, cut to the room there', () {
      // A song already from 5s to 9s; a 20s song added at 1s fits 1..5.
      final edit = _edit(audio: [_song(5, 4)]);
      final added = edit.addTrack(_song(0, 20, path: '/in/b.mp3'),
          at: _s(1), maxTotal: _max)!;
      final track = added.audio.firstWhere((t) => t.path == '/in/b.mp3');
      expect(track.start, _s(1));
      expect(track.length, _s(4));
      // Kept in time order.
      expect(added.audio.map((t) => t.start), [_s(1), _s(5)]);
    });

    test('added where a song plays: on a lane of its own, heard with it - '
        'and longer than the clips, the moment runs on', () {
      final edit = _edit(audio: [_song(0, 4)]);
      final added = edit.addTrack(_song(0, 60, path: '/in/b.mp3'),
          at: _s(2), maxTotal: _max)!;
      final track = added.audio.last;
      // At the playhead still - the lane under it is taken there - all of
      // it: there is room to the most a moment can be.
      expect(track.lane, 1);
      expect(track.start, _s(2));
      expect(track.length, _s(60));
      expect(added.audioLanes, 2);
      expect(added.naturalDuration, _s(62));
    });

    test('the slot a new song would get, and how long it can be there', () {
      final edit = _edit(audio: [_song(5, 4)]);
      // At 1s: the first lane, up to the song at 5s.
      expect(edit.trackSlot(_s(1), maxTotal: _max),
          (lane: 0, start: _s(1), room: _s(4)));
      // Inside that song: a lane of its own, to the most a moment can be.
      expect(edit.trackSlot(_s(6), maxTotal: _max),
          (lane: 1, start: _s(6), room: _s(114)));
      // Under half a second before that song: no room on its lane either.
      expect(edit.trackSlot(_s(4.8), maxTotal: _max),
          (lane: 1, start: _s(4.8), room: _s(115.2)));
    });

    test('no room: every lane taken there, or the cap about to be reached',
        () {
      final full = _edit(audio: [
        for (var lane = 0; lane < maxAudioLanes; lane++)
          _song(0, 120, lane: lane),
      ]);
      expect(
          full.addTrack(_song(0, 5, path: '/in/b.mp3'),
              at: _s(3), maxTotal: _max),
          isNull);
      expect(_edit().trackSlot(_s(119.8), maxTotal: _max), isNull);
    });

    test('a dragged song lands in the free stretch nearest the finger', () {
      // Songs at 0..3 and 6..9; the first dragged to 5s doesn't fit there
      // (3s long, 3..6 is free) - it goes as near as it can: 3..6.
      final edit = _edit(audio: [_song(0, 3), _song(6, 3, from: 10)]);
      final moved = edit.moveTrack(0, _s(5), maxTotal: _max);
      expect(moved.audio.map((t) => t.start), [_s(3), _s(6)]);
      // Dragged well past the other: it goes after it - the two swap.
      final swapped = edit.moveTrack(0, _s(11), maxTotal: _max);
      expect(swapped.audio.map((t) => (t.start, t.trim.start)),
          [(_s(6), _s(10)), (_s(11), Duration.zero)]);
    });

    test('a song slid along its lane: any blank, pushing what it meets',
        () {
      final edit = _edit(audio: [_song(0, 3), _song(6, 3, from: 10)]);
      // 0.2s after the first: it stays there.
      expect(edit.slideTrack(1, _s(-2.8), maxTotal: _max).audio.map((t) => t.start),
          [Duration.zero, _s(3.2)]);
      // The first slid 4s on: it pushes the second 1s on.
      expect(edit.slideTrack(0, _s(4), maxTotal: _max).audio.map((t) => t.start),
          [_s(4), _s(7)]);
      expect(edit.trackBlanks(1), (before: _s(3), first: false, after: null));
      expect(edit.trackBlanks(0), (before: Duration.zero, first: true,
          after: _s(3)));
    });

    test('a song is never dragged off the start; past the clips it runs the '
        'moment on, to the cap', () {
      final edit = _edit(audio: [_song(4, 3)]);
      expect(edit.moveTrack(0, _s(-5), maxTotal: _max).audio.single.start,
          Duration.zero);
      final later = edit.moveTrack(0, _s(40), maxTotal: _max);
      expect(later.audio.single.start, _s(40));
      expect(later.naturalDuration, _s(43));
      // It can start no later than it still ends within the cap.
      expect(edit.moveTrack(0, _s(200), maxTotal: _max).audio.single.start,
          _s(117));
    });

    test('trimming a song: within its file and the songs either side', () {
      final edit = _edit(audio: [
        _song(0, 3),
        _song(5, 4, path: '/in/b.mp3', from: 10),
        _song(11, 2, path: '/in/c.mp3'),
      ]);
      // Its front pulled back by 5s: stops at the previous song's end (3s),
      // uncovering 2s more of its file.
      final front =
          edit.resizeTrack(1, head: _s(-5), maxTotal: _max).audio[1];
      expect(front.start, _s(3));
      expect(front.trim, TrimRange(_s(8), _s(14)));
      // Its end pulled on: stops at the next song (11s).
      final back = edit.resizeTrack(1, tail: _s(10), maxTotal: _max).audio[1];
      expect(back.end, _s(11));
      expect(back.trim, TrimRange(_s(10), _s(16)));
      // The last one: to the end of its 60s file at most.
      final last = edit.resizeTrack(2, tail: _s(100), maxTotal: _max).audio[2];
      expect(last.trim.end, _s(60));
      // Never under half a second.
      expect(edit.resizeTrack(1, head: _s(10), maxTotal: _max).audio[1].length,
          minPiece);
      // Nor past the most a moment can be.
      expect(
          _edit(audio: [_song(110, 5)])
              .resizeTrack(0, tail: _s(30), maxTotal: _max)
              .audio
              .single
              .end,
          _max);
    });

    test('its front not pulled back past the start of its file', () {
      final edit = _edit(audio: [_song(5, 4, from: 1)]);
      final track =
          edit.resizeTrack(0, head: _s(-4), maxTotal: _max).audio.single;
      expect(track.start, _s(4));
      expect(track.trim.start, Duration.zero);
    });

    test('split at the playhead: two songs that play on as one', () {
      final edit = _edit(audio: [_song(2, 8, from: 5)]);
      final split = edit.splitTrack(0, _s(6))!;
      expect(split.audio.map((t) => (t.start, t.trim)), [
        (_s(2), TrimRange(_s(5), _s(9))),
        (_s(6), TrimRange(_s(9), _s(13))),
      ]);
      expect(edit.splitTrack(0, _s(2.2)), isNull);
      // No fade where the two halves meet - only at the outer ends.
      final faded = split.withAutoFades().audio;
      expect(faded[0].fadeIn, const Duration(milliseconds: 300));
      expect(faded[0].fadeOut, Duration.zero);
      expect(faded[1].fadeIn, Duration.zero);
      expect(faded[1].fadeOut, _s(1));
    });

    test('fades: in where cut into the file, out over the last second', () {
      final faded = _edit(audio: [_song(0, 3), _song(4, 6, from: 20)])
          .withAutoFades()
          .audio;
      // From the file's very start: no fade in; under 4s: no fade out.
      expect((faded[0].fadeIn, faded[0].fadeOut), (Duration.zero, Duration.zero));
      expect((faded[1].fadeIn, faded[1].fadeOut),
          (const Duration(milliseconds: 300), _s(1)));
    });

    test('removed', () {
      expect(_edit(audio: [_song(0, 3)]).removeTrack(0).audio, isEmpty);
    });
  });

  group('audio lanes', () {
    test('a song over another; an emptied lane closes up', () {
      final edit = _edit(audio: [
        _song(0, 6),
        _song(2, 4, path: '/in/b.mp3', lane: 1),
      ]);
      expect(edit.audioLanes, 2);
      // The second dragged onto the first lane, after the song there: the
      // lane it left is gone.
      final moved = edit.moveTrack(1, _s(7), lane: 0, maxTotal: _max);
      expect(moved.audioLanes, 1);
      expect(moved.audio.map((t) => (t.lane, t.start)),
          [(0, Duration.zero), (0, _s(7))]);
      // And off it again, onto a lane of its own.
      final apart = moved.moveTrack(1, _s(3), lane: 1, maxTotal: _max);
      expect(apart.audio.map((t) => (t.lane, t.start)),
          [(0, Duration.zero), (1, _s(3))]);
    });

    test('a song is trimmed past the songs on the other lanes', () {
      final edit = _edit(audio: [
        _song(0, 3),
        _song(1, 2, path: '/in/b.mp3', from: 10, lane: 1),
      ]);
      // Its front pulled back to the start: nothing on its own lane is in
      // the way.
      final track =
          edit.resizeTrack(1, head: _s(-5), maxTotal: _max).audio[1];
      expect(track.start, Duration.zero);
      expect(track.trim, TrimRange(_s(9), _s(12)));
    });
  });

  group('layers', () {
    test('a layer goes in at the playhead, on the lowest lane free there - '
        'and longer than the clips, the moment runs on', () {
      const clip = MediaLayer(
          source: _video, trim: TrimRange(Duration.zero, Duration(seconds: 20)));
      final one = _edit().addOverlay(clip, at: _s(2), maxTotal: _max)!;
      final layer = one.overlays.single;
      expect((layer.lane, layer.start), (0, _s(2)));
      expect(layer.clip.trim, TrimRange(Duration.zero, _s(20)));
      expect(one.naturalDuration, _s(22));
      // Cut to the room when it runs into the cap.
      expect(
          _edit()
              .addOverlay(clip, at: _s(2), maxTotal: _s(15))!
              .overlays
              .single
              .clip
              .trim,
          TrimRange(Duration.zero, _s(13)));
      // Another where the first shows: on a lane over it.
      final two = one.addOverlay(
          MediaLayer(source: _photo, duration: _s(2)),
          at: _s(4),
          maxTotal: _max)!;
      expect(two.overlays.map((o) => (o.lane, o.start)),
          [(0, _s(2)), (1, _s(4))]);
      // What shows when, the lower first - the order they are drawn.
      expect(two.overlaysAt(_s(5)), [0, 1]);
      expect(two.overlaysAt(_s(7)), [0]);
      expect(two.overlaysAt(_s(1)), isEmpty);
    });

    test('no more than the lanes allowed', () {
      final full = _edit(overlays: [
        for (var lane = 0; lane < maxOverlayLanes; lane++)
          _layer(0, 15, lane: lane),
      ]);
      expect(full.overlaySlot(_s(3), maxTotal: _max), isNull);
      expect(
          full.addOverlay(const MediaLayer(source: _photo),
              at: _s(3), maxTotal: _max),
          isNull);
    });

    test('a layer drags to another time, another lane, a lane of its own',
        () {
      final edit = _edit(overlays: [_layer(0, 3), _layer(2, 3, lane: 1)]);
      // The top one down onto the first lane: after the one there.
      final down = edit.moveOverlay(1, _s(2), lane: 0, maxTotal: _max);
      expect(down.overlays.map((o) => (o.lane, o.start)),
          [(0, Duration.zero), (0, _s(3))]);
      expect(down.overlayLanes, 1);
      // Above every lane: one of its own, on top - the lane it left closes.
      final up = edit.moveOverlay(0, Duration.zero, lane: 2, maxTotal: _max);
      expect(up.overlays.map((o) => (o.lane, o.start)),
          [(0, _s(2)), (1, Duration.zero)]);
    });

    test('forward and back: over or under the next layer it shows with', () {
      // A (0..4) under B (2..5).
      final edit = _edit(overlays: [_layer(0, 4), _layer(2, 3, lane: 1)]);
      final forward = edit.bringForward(0)!;
      // A over B now.
      expect(forward.overlays.map((o) => (o.start, o.lane)),
          [(_s(2), 0), (Duration.zero, 1)]);
      expect(forward.bringForward(1), isNull, reason: 'already on top');
      final back = forward.sendBackward(1)!;
      expect(back.overlays.map((o) => (o.start, o.lane)),
          [(Duration.zero, 0), (_s(2), 1)]);
      expect(back.sendBackward(0), isNull,
          reason: 'only the main clips are under it');
      // A lane above, but nothing on it while A shows: on top already.
      final apart = _edit(overlays: [_layer(0, 2), _layer(5, 2, lane: 1)]);
      expect(apart.bringForward(0), isNull);
    });

    test('forward onto the lane above when it is free there', () {
      // A under B (1..2); C on the lane over B, clear of A.
      final edit = _edit(overlays: [
        _layer(0, 3),
        _layer(1, 1, lane: 1),
        _layer(5, 1, lane: 2),
      ]);
      final forward = edit.bringForward(0)!;
      // Onto C's lane - no new one - and the lane A left closes up.
      expect(forward.overlayLanes, 2);
      expect(forward.overlays.map((o) => (o.start, o.lane)),
          [(_s(1), 0), (Duration.zero, 1), (_s(5), 1)]);
    });

    test('a clip lifted out of the run, onto a layer over where it played',
        () {
      final lifted = _edit().liftClip(1, maxTotal: _max)!;
      // The video (6s..12s) is out of the run, which closes up.
      expect(lifted.clips, hasLength(2));
      expect(lifted.mainEnd, _s(9));
      final layer = lifted.overlays.single;
      expect(layer.clip.source, _video);
      expect((layer.lane, layer.start), (0, _s(6)));
      // The layer runs on past the clips now: the moment keeps its 12s.
      expect(lifted.naturalDuration, _s(12));
      // Where asked for, on a lane of its own.
      final placed = _edit(overlays: [_layer(0, 9)])
          .liftClip(2, start: _s(1), lane: 1, maxTotal: _max)!;
      expect(placed.overlays.map((o) => (o.lane, o.start)),
          [(0, Duration.zero), (1, _s(1))]);
      // The only clip, lifted: a layer over black.
      final alone = const Composition(clips: [MediaLayer(source: _photo)])
          .liftClip(0, maxTotal: _max)!;
      expect(alone.clips, isEmpty);
      expect(alone.overlays.single.start, Duration.zero);
    });

    test('a layer dropped into the run, at the clip edge nearest it', () {
      final edit = _edit(overlays: [_layer(5.8, 2)]);
      final dropped = edit.dropOverlay(0, maxTotal: _max)!;
      expect(dropped.overlays, isEmpty);
      // Between the first photo and the video - the edge at 6s.
      expect(dropped.clips.map((c) => c.length), [_s(6), _s(2), _s(6), _s(3)]);
      // Where asked for.
      expect(edit.dropOverlay(0, maxTotal: _max, slot: 3)!.clips.last.length,
          _s(2));
      // Not past the most a moment can be.
      expect(edit.dropOverlay(0, maxTotal: _s(16)), isNull);
    });

    test('a layer is trimmed within its lane and the cap', () {
      final edit = _edit(overlays: [_layer(1, 2), _layer(6, 2)]);
      // Its end pulled on: stops at the next on its lane (6s).
      expect(
          edit.resizeOverlay(0, tail: _s(10), maxTotal: _max).overlays[0].end,
          _s(6));
      // Its front pulled back: stops at the start of the edit.
      final front =
          edit.resizeOverlay(0, head: _s(-5), maxTotal: _max).overlays[0];
      expect((front.start, front.length), (Duration.zero, _s(3)));
      // The last: on past the clips, up to the cap.
      expect(
          edit.resizeOverlay(1, tail: _s(20), maxTotal: _max).overlays[1].end,
          _s(28));
      expect(
          edit.resizeOverlay(1, tail: _s(20), maxTotal: _s(20)).overlays[1].end,
          _s(20));
      // A video layer: within its file.
      final video = _edit(overlays: [
        OverlayClip(
          clip: MediaLayer(source: _video, trim: TrimRange(_s(2), _s(4))),
          start: _s(3),
        ),
      ]);
      final grown =
          video.resizeOverlay(0, head: _s(-5), maxTotal: _max).overlays.single;
      expect(grown.start, _s(1));
      expect(grown.clip.trim, TrimRange(Duration.zero, _s(4)));
    });

    test('split in two; a copy after it - or over it, with no room after',
        () {
      final edit = _edit(overlays: [_layer(2, 4)]);
      final split = edit.splitOverlay(0, _s(3))!;
      expect(split.overlays.map((o) => (o.start, o.length)),
          [(_s(2), _s(1)), (_s(3), _s(3))]);
      expect(edit.splitOverlay(0, _s(2.2)), isNull);
      final copy = edit.duplicateOverlay(0, maxTotal: _max)!;
      expect(copy.overlays.map((o) => (o.lane, o.start, o.length)),
          [(0, _s(2), _s(4)), (0, _s(6), _s(4))]);
      // Ending at the most a moment can be, there is no room after it.
      final atEnd = _edit(overlays: [_layer(12, 3)])
          .duplicateOverlay(0, maxTotal: _s(15))!;
      expect(atEnd.overlays.map((o) => (o.lane, o.start)),
          [(0, _s(12)), (1, _s(12))]);
    });

    test('a layer slid along its lane: any blank, pushing only its lane', () {
      final edit = _edit(
          overlays: [_layer(0, 3), _layer(6, 2), _layer(4, 2, lane: 1)]);
      expect(
          edit.slideOverlay(1, _s(-2.8), maxTotal: _max).overlays.map((o) => o.start),
          [Duration.zero, _s(3.2), _s(4)]);
      // Pushed back to the start, the one before it goes too.
      expect(
          edit.slideOverlay(1, _s(-9), maxTotal: _max).overlays.map((o) => o.start),
          [Duration.zero, _s(3), _s(4)]);
      expect(edit.overlayBlanks(2), (before: _s(4), first: true, after: null));
    });

    test('a text layer keeps its words: saved, split, copied', () {
      const words = TextCard(text: 'Hi\nthere', argb: 0xFFFFD60A, boxed: true);
      final edit = _edit(overlays: [
        OverlayClip(
            clip: MediaLayer(source: _photo, duration: _s(4)),
            start: _s(1),
            text: words),
      ]);
      final back = OverlayClip.fromJson(edit.overlays.single.toJson());
      expect(back.text, words);
      expect(OverlayClip.fromJson(_layer(0, 1).toJson()).isText, isFalse);
      expect(edit.splitOverlay(0, _s(3))!.overlays.map((o) => o.text),
          [words, words]);
      final atEnd = _edit(overlays: [
        edit.overlays.single.copyWith(start: _s(11)),
      ]).duplicateOverlay(0, maxTotal: _s(15))!;
      expect(atEnd.overlays.map((o) => o.text), [words, words]);
    });

    test('the main clips changing leave the layers where they are', () {
      final edit = _edit(overlays: [_layer(7, 2)]);
      expect(edit.moveClip(0, 2).overlays.single.start, _s(7));
      expect(edit.removeClip(0)!.overlays.single.start, _s(7));
    });
  });
}
