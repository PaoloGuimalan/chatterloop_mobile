import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// RESTART POINTS for an exported MP4 - without encoding it again.
///
/// A player can only start decoding a video, or pick it up again after it
/// stalled while streaming, at a frame marked as a restart point (a "sync
/// sample"). The phone's hardware encoder writes a whole picture every 2s
/// as asked (`-g`), but as an ordinary frame - not an IDR - so the file had
/// one restart point, its first frame: streamed, every stall meant catching
/// up from far back, and posted moments stuttered on the web and in the
/// app while the same file played smoothly from disk. (FFmpeg's MediaCodec
/// encoder has no way to ask for IDR frames, and the bundled FFmpeg has no
/// software H.264 encoder.)
///
/// So after an export, each of those whole pictures gets a recovery-point
/// SEI in front of it - H.264's own mark for "decoding can start here" -
/// and is listed in the file's sync sample table. It is only done when the
/// encoder keeps a single reference frame: then no frame after a whole
/// picture looks back past it, and starting there is exact.
///
/// Anything unexpected - another codec, several reference frames, an
/// unusual layout - and the file is left as it was.
class Mp4RestartPoints {
  Mp4RestartPoints._();

  /// Recovery point SEI: recovery_frame_cnt 0, exact_match 1, broken_link
  /// 0, changing_slice_group_idc 0, then the trailing bits.
  static const _sei = [0x06, 0x06, 0x01, 0xC4, 0x80];

  /// Adds restart points to the MP4 at [path], in place. Whether it did -
  /// false when it needed none, or couldn't (the file is then untouched).
  static Future<bool> addToFile(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final plan = _plan(bytes);
      if (plan == null) return false;
      final temp = File('$path.restart');
      final sink = temp.openWrite();
      plan.writeTo(bytes, sink.add);
      await sink.close();
      await temp.rename(path);
      return true;
    } catch (e) {
      debugPrint('Mp4RestartPoints: left as it was: $e');
      return false;
    }
  }

  /// [mp4] with restart points added - null when it needs none, or isn't
  /// a file this knows how to fix.
  static Uint8List? add(Uint8List mp4) {
    final _Plan? plan;
    try {
      plan = _plan(mp4);
    } catch (_) {
      return null; // Not an MP4 as it expects: left as it is.
    }
    if (plan == null) return null;
    final out = BytesBuilder(copy: false);
    plan.writeTo(mp4, out.add);
    return out.takeBytes();
  }

  static _Plan? _plan(Uint8List data) {
    final top = _Box.children(data, 0, data.length);
    final moov = top.where((b) => b.type == 'moov').toList();
    final mdat = top.where((b) => b.type == 'mdat').toList();
    if (moov.length != 1 || mdat.length != 1) return null;

    final tracks = <_Track>[];
    for (final trak in moov.single.kids(data).where((b) => b.type == 'trak')) {
      final track = _Track.read(data, trak);
      if (track == null) return null;
      tracks.add(track);
    }
    final videos = tracks.where((t) => t.isVideo).toList();
    if (videos.length != 1) return null;
    final video = videos.single;
    final avc = video.avc;
    // No sync table: every frame is already a restart point.
    if (avc == null || video.stss == null) return null;
    if (avc.referenceFrames != 1) return null;

    final syncs = video.stss!.toSet();
    final insertAt = <int>[];
    final sizes = [...video.sizes];
    final offsets = video.sampleOffsets();
    for (var i = 0; i < sizes.length; i++) {
      if (syncs.contains(i + 1)) continue;
      final at = _wholePictureAt(data, offsets[i], sizes[i], avc.lengthSize);
      if (at == null) continue;
      insertAt.add(at);
      sizes[i] += avc.lengthSize + _sei.length;
      syncs.add(i + 1);
    }
    if (insertAt.isEmpty) return null;
    // Every original sample stays whole; those get longer, so everything
    // after them in the file moves on.
    insertAt.sort();

    final mdatBox = mdat.single;
    final added = insertAt.length * (avc.lengthSize + _sei.length);
    final mdatSize = mdatBox.end - mdatBox.start + added;
    if (mdatBox.headerSize == 8 && mdatSize > 0xFFFFFFFF) return null;

    int insertedBefore(int offset) {
      // Samples start where their SEI goes: a chunk that starts with one
      // points at the SEI (strictly before).
      var lo = 0, hi = insertAt.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (insertAt[mid] < offset) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo * (avc.lengthSize + _sei.length);
    }

    Uint8List buildMoov(int shift) {
      final replace = <int, Uint8List>{};
      for (final track in tracks) {
        final moved = [
          for (final o in track.chunkOffsets) o + shift + insertedBefore(o)
        ];
        final box = track.chunkOffsetBox;
        replace[box.start] = box.type == 'co64'
            ? _fullBox('co64', 8, moved.length, (b) {
                for (final o in moved) {
                  b.add(_u64(o));
                }
              })
            : _fullBox('stco', 4, moved.length, (b) {
                for (final o in moved) {
                  if (o > 0xFFFFFFFF) throw const FormatException('offset');
                  b.add(_u32(o));
                }
              });
      }
      replace[video.stszBox.start] = _stsz(sizes);
      replace[video.stssBox!.start] =
          _fullBox('stss', 4, syncs.length, (b) {
        for (final s in syncs.toList()..sort()) {
          b.add(_u32(s));
        }
      });
      return _rebuild(data, moov.single, replace);
    }

    // Where the samples' data starts, before and after: whatever comes
    // before the mdat, the moov among it maybe, rebuilt.
    List<Uint8List> head(Uint8List newMoov) => [
          for (final box in top)
            if (box.start < mdatBox.start)
              box.type == 'moov'
                  ? newMoov
                  : Uint8List.sublistView(data, box.start, box.end)
        ];
    final firstMoov = buildMoov(0);
    final headLength =
        head(firstMoov).fold<int>(0, (sum, part) => sum + part.length);
    final shift = headLength - mdatBox.start;
    final newMoov = shift == 0 ? firstMoov : buildMoov(shift);

    return _Plan(
      head: head(newMoov),
      mdatHeader: mdatBox.headerSize == 8
          ? (BytesBuilder()
                ..add(_u32(mdatSize))
                ..add('mdat'.codeUnits))
              .takeBytes()
          : (BytesBuilder()
                ..add(_u32(1))
                ..add('mdat'.codeUnits)
                ..add(_u64(mdatSize)))
              .takeBytes(),
      bodyStart: mdatBox.start + mdatBox.headerSize,
      bodyEnd: mdatBox.end,
      insertAt: insertAt,
      // Length-prefixed like the file's other NAL units.
      sei: Uint8List.fromList(
          [..._u32(_sei.length).sublist(4 - avc.lengthSize), ..._sei]),
      tail: [
        for (final box in top)
          if (box.start > mdatBox.start)
            box.type == 'moov'
                ? newMoov
                : Uint8List.sublistView(data, box.start, box.end)
      ],
    );
  }

  /// Where in the sample at [offset] a recovery point goes - just before
  /// its first slice - when that slice is a whole picture (an I slice) that
  /// isn't an IDR already. Null otherwise.
  static int? _wholePictureAt(
      Uint8List data, int offset, int size, int lengthSize) {
    var p = offset;
    final end = offset + size;
    while (p + lengthSize < end) {
      var length = 0;
      for (var k = 0; k < lengthSize; k++) {
        length = (length << 8) | data[p + k];
      }
      final nal = p + lengthSize;
      if (length <= 0 || nal + length > end) return null;
      final type = data[nal] & 0x1F;
      if (type == 5) return null; // An IDR: already one.
      if (type == 1) {
        final bits = _Bits(_unescape(data, nal + 1, nal + length, 16));
        bits.ue(); // first_mb_in_slice
        final sliceType = bits.ue() % 5;
        return sliceType == 2 ? p : null;
      }
      if (type == 6) {
        // A recovery point already there: nothing to add.
        if (length > 1 && data[nal + 1] == 6) return null;
      }
      p = nal + length;
    }
    return null;
  }

  static Uint8List _rebuild(
      Uint8List data, _Box box, Map<int, Uint8List> replace) {
    final swapped = replace[box.start];
    if (swapped != null) return swapped;
    if (!_Box.containers.contains(box.type)) {
      return Uint8List.sublistView(data, box.start, box.end);
    }
    final parts = [for (final kid in box.kids(data)) _rebuild(data, kid, replace)];
    final length = 8 + parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = BytesBuilder(copy: false)
      ..add(_u32(length))
      ..add(box.type.codeUnits);
    for (final part in parts) {
      out.add(part);
    }
    return out.takeBytes();
  }

  static Uint8List _stsz(List<int> sizes) =>
      _fullBox('stsz', 4, sizes.length, (b) {
        for (final s in sizes) {
          b.add(_u32(s));
        }
      }, beforeCount: _u32(0));

  /// A version-0 full box: its [count] entries of [entrySize] written by
  /// [entries].
  static Uint8List _fullBox(String type, int entrySize, int count,
      void Function(BytesBuilder) entries,
      {List<int>? beforeCount}) {
    final body = BytesBuilder(copy: false)
      ..add(_u32(0)) // version, flags
      ..add(beforeCount ?? const [])
      ..add(_u32(count));
    entries(body);
    final bytes = body.takeBytes();
    return (BytesBuilder(copy: false)
          ..add(_u32(8 + bytes.length))
          ..add(type.codeUnits)
          ..add(bytes))
        .takeBytes();
  }

  /// [data] from [start] to [end] (at most [limit] bytes of it), emulation
  /// prevention bytes (00 00 03) taken out.
  static Uint8List _unescape(Uint8List data, int start, int end, int limit) {
    final out = <int>[];
    var zeros = 0;
    for (var i = start; i < end && out.length < limit; i++) {
      final b = data[i];
      if (zeros >= 2 && b == 3) {
        zeros = 0;
        continue;
      }
      out.add(b);
      zeros = b == 0 ? zeros + 1 : 0;
    }
    return Uint8List.fromList(out);
  }

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u64(int v) => [..._u32(v >> 32), ..._u32(v & 0xFFFFFFFF)];
}

/// What to write: [head], the mdat with a recovery point put in at each of
/// [insertAt] (offsets in the original file), then [tail].
class _Plan {
  final List<Uint8List> head;
  final Uint8List mdatHeader;
  final int bodyStart;
  final int bodyEnd;
  final List<int> insertAt;
  final Uint8List sei;
  final List<Uint8List> tail;

  _Plan({
    required this.head,
    required this.mdatHeader,
    required this.bodyStart,
    required this.bodyEnd,
    required this.insertAt,
    required this.sei,
    required this.tail,
  });

  void writeTo(Uint8List data, void Function(List<int>) write) {
    head.forEach(write);
    write(mdatHeader);
    var from = bodyStart;
    for (final at in insertAt) {
      write(Uint8List.sublistView(data, from, at));
      write(sei);
      from = at;
    }
    write(Uint8List.sublistView(data, from, bodyEnd));
    tail.forEach(write);
  }
}

class _Box {
  final String type;
  final int start;
  final int headerSize;
  final int end;

  _Box(this.type, this.start, this.headerSize, this.end);

  static const containers = {'moov', 'trak', 'mdia', 'minf', 'stbl'};

  int get bodyStart => start + headerSize;

  List<_Box> kids(Uint8List data) => children(data, bodyStart, end);

  static List<_Box> children(Uint8List data, int start, int end) {
    final boxes = <_Box>[];
    var i = start;
    while (i + 8 <= end) {
      var size = _read(data, i, 4);
      final type = String.fromCharCodes(data.sublist(i + 4, i + 8));
      var header = 8;
      if (size == 1) {
        size = _read(data, i + 8, 8);
        header = 16;
      } else if (size == 0) {
        size = end - i;
      }
      if (size < header || i + size > end) {
        throw FormatException('bad box $type');
      }
      boxes.add(_Box(type, i, header, i + size));
      i += size;
    }
    return boxes;
  }

  _Box? find(Uint8List data, String path) {
    _Box? at = this;
    for (final type in path.split('/')) {
      final kids = at!.kids(data).where((b) => b.type == type);
      if (kids.isEmpty) return null;
      at = kids.first;
    }
    return at;
  }
}

int _read(Uint8List data, int at, int bytes) {
  var v = 0;
  for (var k = 0; k < bytes; k++) {
    v = (v << 8) | data[at + k];
  }
  return v;
}

/// The H.264 setup a video track's frames were encoded with.
class _Avc {
  final int lengthSize;
  final int referenceFrames;

  _Avc(this.lengthSize, this.referenceFrames);

  /// From the avcC record at [at] (its body); null when its SPS is one this
  /// doesn't read.
  static _Avc? read(Uint8List data, int at) {
    final lengthSize = (data[at + 4] & 3) + 1;
    if (data[at + 5] & 0x1F < 1) return null;
    final spsLength = _read(data, at + 6, 2);
    final sps = Mp4RestartPoints._unescape(
        data, at + 8 + 1, at + 8 + spsLength, 64);
    final bits = _Bits(sps);
    final profile = bits.u(8);
    bits.u(16); // constraints, level
    bits.ue(); // seq_parameter_set_id
    const high = {100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135};
    if (high.contains(profile)) {
      if (bits.ue() == 3) bits.u(1); // chroma_format_idc, separate planes
      bits.ue(); // bit_depth_luma
      bits.ue(); // bit_depth_chroma
      bits.u(1); // qpprime_y_zero_transform_bypass
      if (bits.u(1) == 1) return null; // Scaling matrices: not read.
    }
    bits.ue(); // log2_max_frame_num
    final poc = bits.ue();
    if (poc == 0) {
      bits.ue();
    } else if (poc == 1) {
      bits.u(1);
      bits.se();
      bits.se();
      final cycle = bits.ue();
      for (var k = 0; k < cycle; k++) {
        bits.se();
      }
    }
    return _Avc(lengthSize, bits.ue());
  }
}

class _Track {
  final bool isVideo;
  final _Avc? avc;
  final List<int> sizes;
  final List<int>? stss;
  final List<(int, int)> stsc;
  final List<int> chunkOffsets;
  final _Box stszBox;
  final _Box? stssBox;
  final _Box chunkOffsetBox;

  _Track({
    required this.isVideo,
    required this.avc,
    required this.sizes,
    required this.stss,
    required this.stsc,
    required this.chunkOffsets,
    required this.stszBox,
    required this.stssBox,
    required this.chunkOffsetBox,
  });

  static _Track? read(Uint8List data, _Box trak) {
    final hdlr = trak.find(data, 'mdia/hdlr');
    final stbl = trak.find(data, 'mdia/minf/stbl');
    if (hdlr == null || stbl == null) return null;
    final isVideo =
        String.fromCharCodes(data.sublist(hdlr.bodyStart + 8, hdlr.bodyStart + 12)) ==
            'vide';
    final stsz = stbl.find(data, 'stsz');
    final stsc = stbl.find(data, 'stsc');
    final co = stbl.find(data, 'stco') ?? stbl.find(data, 'co64');
    if (stsz == null || stsc == null || co == null) return null;

    final uniform = _read(data, stsz.bodyStart + 4, 4);
    final count = _read(data, stsz.bodyStart + 8, 4);
    // One size for all: never so for video, and audio's aren't touched.
    if (isVideo && uniform != 0) return null;
    final sizes = [
      for (var k = 0; k < count; k++)
        uniform != 0 ? uniform : _read(data, stsz.bodyStart + 12 + 4 * k, 4)
    ];

    final wide = co.type == 'co64';
    final chunks = _read(data, co.bodyStart + 4, 4);
    final offsets = [
      for (var k = 0; k < chunks; k++)
        wide
            ? _read(data, co.bodyStart + 8 + 8 * k, 8)
            : _read(data, co.bodyStart + 8 + 4 * k, 4)
    ];
    final runs = _read(data, stsc.bodyStart + 4, 4);
    final stscEntries = [
      for (var k = 0; k < runs; k++)
        (
          _read(data, stsc.bodyStart + 8 + 12 * k, 4),
          _read(data, stsc.bodyStart + 12 + 12 * k, 4),
        )
    ];

    _Avc? avc;
    List<int>? stss;
    _Box? stssBox;
    if (isVideo) {
      final stsd = stbl.find(data, 'stsd');
      if (stsd == null) return null;
      final entry = _Box.children(data, stsd.bodyStart + 8, stsd.end);
      if (entry.isEmpty || !{'avc1', 'avc3'}.contains(entry.first.type)) {
        return null;
      }
      // After the 78 bytes of a visual sample entry: its boxes.
      final avcC = _Box.children(
              data, entry.first.bodyStart + 78, entry.first.end)
          .where((b) => b.type == 'avcC');
      if (avcC.isEmpty) return null;
      avc = _Avc.read(data, avcC.first.bodyStart);
      stssBox = stbl.find(data, 'stss');
      if (stssBox != null) {
        final n = _read(data, stssBox.bodyStart + 4, 4);
        stss = [
          for (var k = 0; k < n; k++) _read(data, stssBox.bodyStart + 8 + 4 * k, 4)
        ];
      }
    }
    return _Track(
      isVideo: isVideo,
      avc: avc,
      sizes: sizes,
      stss: stss,
      stsc: stscEntries,
      chunkOffsets: offsets,
      stszBox: stsz,
      stssBox: stssBox,
      chunkOffsetBox: co,
    );
  }

  /// Where each sample starts in the file.
  List<int> sampleOffsets() {
    final out = <int>[];
    var sample = 0;
    for (var chunk = 0; chunk < chunkOffsets.length; chunk++) {
      var perChunk = 0;
      for (final (first, count) in stsc) {
        if (first <= chunk + 1) perChunk = count;
      }
      var at = chunkOffsets[chunk];
      for (var k = 0; k < perChunk && sample < sizes.length; k++) {
        out.add(at);
        at += sizes[sample++];
      }
    }
    return out;
  }
}

class _Bits {
  final Uint8List bytes;
  int _pos = 0;

  _Bits(this.bytes);

  int u(int n) {
    var v = 0;
    for (var k = 0; k < n; k++) {
      final byte = bytes[_pos >> 3];
      v = (v << 1) | ((byte >> (7 - (_pos & 7))) & 1);
      _pos++;
    }
    return v;
  }

  int ue() {
    var zeros = 0;
    while (u(1) == 0) {
      zeros++;
      if (zeros > 31) throw const FormatException('ue');
    }
    return (1 << zeros) - 1 + (zeros == 0 ? 0 : u(zeros));
  }

  int se() {
    final k = ue();
    return k.isOdd ? (k + 1) ~/ 2 : -(k ~/ 2);
  }
}
