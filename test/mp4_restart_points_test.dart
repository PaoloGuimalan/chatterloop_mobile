// Restart points added to an exported MP4 (lib/core/media/mp4_restart_
// points.dart): on a small MP4 built here - a video track of four frames
// (an IDR, a P, a whole picture that isn't an IDR, a P) in two chunks, with
// an audio chunk after each.

import 'dart:typed_data';

import 'package:chatterloop_app/core/media/mp4_restart_points.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

List<int> _box(String type, List<int> body) =>
    [..._u32(8 + body.length), ...type.codeUnits, ...body];

List<int> _full(String type, List<int> body) =>
    _box(type, [0, 0, 0, 0, ...body]);

/// A baseline SPS keeping [references] reference frames (read up to there).
List<int> _sps(int references) => [
      0x67, 66, 0, 30,
      // id 0, log2_max_frame_num 0, poc type 2, then the references (1 or 2).
      references == 1 ? 0xDA : 0xDB, 0x80,
    ];

/// Length-prefixed NAL units.
List<int> _sample(List<List<int>> nals) =>
    [for (final nal in nals) ...[..._u32(nal.length), ...nal]];

final _idr = _sample([
  [0x65, 0x88, 0x11, 0x22]
]);
final _p1 = _sample([
  [0x41, 0x98, 0x33]
]);
final _whole = _sample([
  [0x41, 0x88, 0x44, 0x55, 0x66]
]);
final _p2 = _sample([
  [0x41, 0x98, 0x77]
]);
const _audio1 = [0xA1, 0xA2, 0xA3];
const _audio2 = [0xB1, 0xB2, 0xB3];

Uint8List _mp4({int references = 1}) {
  final ftyp = _box('ftyp', [...'isom'.codeUnits, 0, 0, 2, 0]);
  List<int> moov(List<int> offsets) {
    final avc1 = _box('avc1', [
      ...List.filled(78, 0),
      ..._box('avcC', [1, 66, 0, 30, 0xFF, 0xE1, 0, 6, ..._sps(references)]),
    ]);
    final video = _box('trak', [
      ..._box('mdia', [
        ..._full('hdlr', [0, 0, 0, 0, ...'vide'.codeUnits, ...List.filled(13, 0)]),
        ..._box('minf', [
          ..._box('stbl', [
            ..._full('stsd', [..._u32(1), ...avc1]),
            ..._full('stsz', [
              ..._u32(0), ..._u32(4),
              for (final s in [_idr, _p1, _whole, _p2]) ..._u32(s.length),
            ]),
            ..._full('stss', [..._u32(1), ..._u32(1)]),
            ..._full('stsc', [..._u32(1), ..._u32(1), ..._u32(2), ..._u32(1)]),
            ..._full('stco', [..._u32(2), ..._u32(offsets[0]), ..._u32(offsets[2])]),
          ]),
        ]),
      ]),
    ]);
    final sound = _box('trak', [
      ..._box('mdia', [
        ..._full('hdlr', [0, 0, 0, 0, ...'soun'.codeUnits, ...List.filled(13, 0)]),
        ..._box('minf', [
          ..._box('stbl', [
            ..._full('stsd', [..._u32(0)]),
            ..._full('stsz', [..._u32(3), ..._u32(2)]),
            ..._full('stsc', [..._u32(1), ..._u32(1), ..._u32(1), ..._u32(1)]),
            ..._full('stco', [..._u32(2), ..._u32(offsets[1]), ..._u32(offsets[3])]),
          ]),
        ]),
      ]),
    ]);
    return _box('moov', [...video, ...sound]);
  }

  final chunks = [
    [..._idr, ..._p1],
    _audio1,
    [..._whole, ..._p2],
    _audio2,
  ];
  // The moov's length doesn't hang on the offsets in it.
  final start = ftyp.length + moov([0, 0, 0, 0]).length + 8;
  final offsets = <int>[];
  var at = start;
  for (final chunk in chunks) {
    offsets.add(at);
    at += chunk.length;
  }
  return Uint8List.fromList([
    ...ftyp,
    ...moov(offsets),
    ..._box('mdat', [for (final c in chunks) ...c]),
  ]);
}

/// The body of the [n]th box of [type] in [data] (found by its name - the
/// file here has no data that looks like one).
int _body(Uint8List data, String type, [int n = 0]) {
  var from = 0;
  for (var k = 0;; k++) {
    final at = _find(data, type.codeUnits, from);
    if (k == n) return at + 4;
    from = at + 4;
  }
}

int _find(Uint8List data, List<int> what, int from) {
  for (var i = from; i + what.length <= data.length; i++) {
    var hit = true;
    for (var k = 0; k < what.length && hit; k++) {
      hit = data[i + k] == what[k];
    }
    if (hit) return i;
  }
  throw StateError('no ${String.fromCharCodes(what)}');
}

int _read(Uint8List data, int at) =>
    (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3];

List<int> _entries(Uint8List data, String type, {int n = 0, int skip = 0}) {
  final body = _body(data, type, n) + 4 + skip;
  return [for (var k = 0; k < _read(data, body); k++) _read(data, body + 4 + 4 * k)];
}

void main() {
  test('a whole picture that is no IDR becomes a restart point', () {
    final before = _mp4();
    final after = Mp4RestartPoints.add(before)!;

    // Listed as a sync sample.
    expect(_entries(after, 'stss'), [1, 3]);
    // Its sample: a recovery point SEI, then the frame as it was.
    final sizes = _entries(after, 'stsz', skip: 4);
    expect(sizes, [_idr.length, _p1.length, _whole.length + 9, _p2.length]);
    final chunks = _entries(after, 'stco');
    final third = chunks[1];
    expect(after.sublist(third, third + 9),
        [0, 0, 0, 5, 0x06, 0x06, 0x01, 0xC4, 0x80]);
    expect(after.sublist(third + 9, third + 9 + _whole.length), _whole);
    // The frames and the sound, all where the offsets now say.
    expect(after.sublist(chunks[0], chunks[0] + _idr.length), _idr);
    final sound = _entries(after, 'stco', n: 1);
    expect(after.sublist(sound[0], sound[0] + 3), _audio1);
    expect(after.sublist(sound[1], sound[1] + 3), _audio2);
    expect(after.length, before.length + 9 + 4);

    // Done once: nothing more to do.
    expect(Mp4RestartPoints.add(after), isNull);
  });

  test('left as it is when frames may look back past a whole picture', () {
    expect(Mp4RestartPoints.add(_mp4(references: 2)), isNull);
  });

  test('left as it is when it is no MP4 it knows', () {
    expect(Mp4RestartPoints.add(Uint8List.fromList(List.filled(64, 7))),
        isNull);
  });
}
