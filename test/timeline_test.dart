// The timeline's edits (lib/core/media/timeline.dart): what the editor's
// cards do to the edit - reorder, trim, split and remove clips; place, trim,
// split and remove songs - and the rules they keep.

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

const _max = Duration(minutes: 2);

AudioTrack _song(num start, num length,
        {String path = '/in/song.mp3', num from = 0}) =>
    AudioTrack(
      path: path,
      fileLength: _s(60),
      start: _s(start),
      trim: TrimRange(_s(from), _s(from + length)),
    );

/// A 6s photo, a video's 4..10 (6s), a 3s photo: 15s.
Composition _edit({List<AudioTrack> audio = const []}) => Composition(
      clips: [
        const MediaLayer(source: _photo),
        MediaLayer(source: _video, trim: TrimRange(_s(4), _s(10))),
        MediaLayer(source: _photo, duration: _s(3)),
      ],
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

    test('removing the last one leaves nothing', () {
      expect(_edit().removeClip(1)!.clips, hasLength(2));
      expect(const Composition(clips: [MediaLayer(source: _photo)])
          .removeClip(0), isNull);
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

    test('no split right at a clip edge', () {
      expect(_edit().splitAt(_s(6)), isNull);
      expect(_edit().splitAt(_s(6.2)), isNull);
      expect(_edit().splitAt(_s(11.9)), isNull);
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

    test('a clip only grows into the room the edit has left', () {
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

  group('audio', () {
    test('a new song goes in at the playhead, cut to the room there', () {
      // A song already from 5s to 9s; a 20s song added at 1s fits 1..5.
      final edit = _edit(audio: [_song(5, 4)]);
      final added = edit.addTrack(_song(0, 20, path: '/in/b.mp3'), at: _s(1))!;
      final track = added.audio.firstWhere((t) => t.path == '/in/b.mp3');
      expect(track.start, _s(1));
      expect(track.length, _s(4));
      // Kept in time order.
      expect(added.audio.map((t) => t.start), [_s(1), _s(5)]);
    });

    test('added past the others, it runs to the end of the edit', () {
      final edit = _edit(audio: [_song(0, 4)]);
      final added = edit.addTrack(_song(0, 60, path: '/in/b.mp3'), at: _s(2))!;
      final track = added.audio.last;
      // The next free stretch starts at 4s; the edit ends at 15s.
      expect(track.start, _s(4));
      expect(track.length, _s(11));
    });

    test('the slot a new song would get, and how long it can be there', () {
      final edit = _edit(audio: [_song(5, 4)]);
      // At 1s: up to the song at 5s.
      expect(edit.trackSlot(_s(1)), (start: _s(1), room: _s(4)));
      // Inside that song: the next free stretch, 9s to the end (15s).
      expect(edit.trackSlot(_s(6)), (start: _s(9), room: _s(6)));
      expect(_edit(audio: [_song(0, 15)]).trackSlot(Duration.zero), isNull);
    });

    test('no room from the playhead on: not added', () {
      final full = _edit(audio: [_song(0, 15)]);
      expect(full.addTrack(_song(0, 5, path: '/in/b.mp3'), at: _s(3)), isNull);
    });

    test('a dragged song lands in the free stretch nearest the finger', () {
      // Songs at 0..3 and 6..9; the first dragged to 5s doesn't fit there
      // (3s long, 3..6 is free) - it goes as near as it can: 3..6.
      final edit = _edit(audio: [_song(0, 3), _song(6, 3, from: 10)]);
      final moved = edit.moveTrack(0, _s(5));
      expect(moved.audio.map((t) => t.start), [_s(3), _s(6)]);
      // Dragged well past the other: it goes after it - the two swap.
      final swapped = edit.moveTrack(0, _s(11));
      expect(swapped.audio.map((t) => (t.start, t.trim.start)),
          [(_s(6), _s(10)), (_s(11), Duration.zero)]);
    });

    test('a song is never dragged off the start, or past the end', () {
      final edit = _edit(audio: [_song(4, 3)]);
      expect(edit.moveTrack(0, _s(-5)).audio.single.start, Duration.zero);
      // It can start no later than just before the edit ends.
      expect(edit.moveTrack(0, _s(40)).audio.single.start,
          _s(15) - minPiece);
    });

    test('trimming a song: within its file and the songs either side', () {
      final edit = _edit(audio: [
        _song(0, 3),
        _song(5, 4, path: '/in/b.mp3', from: 10),
        _song(11, 2, path: '/in/c.mp3'),
      ]);
      // Its front pulled back by 5s: stops at the previous song's end (3s),
      // uncovering 2s more of its file.
      final front = edit.resizeTrack(1, head: _s(-5)).audio[1];
      expect(front.start, _s(3));
      expect(front.trim, TrimRange(_s(8), _s(14)));
      // Its end pulled on: stops at the next song (11s).
      final back = edit.resizeTrack(1, tail: _s(10)).audio[1];
      expect(back.end, _s(11));
      expect(back.trim, TrimRange(_s(10), _s(16)));
      // The last one: to the end of its 60s file at most.
      final last = edit.resizeTrack(2, tail: _s(100)).audio[2];
      expect(last.trim.end, _s(60));
      // Never under half a second.
      expect(edit.resizeTrack(1, head: _s(10)).audio[1].length, minPiece);
    });

    test('its front not pulled back past the start of its file', () {
      final edit = _edit(audio: [_song(5, 4, from: 1)]);
      final track = edit.resizeTrack(0, head: _s(-4)).audio.single;
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
}
