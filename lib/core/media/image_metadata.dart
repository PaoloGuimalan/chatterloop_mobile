// Removing what a photo says about where, when and with what it was taken -
// EXIF (GPS position, time, camera, serial numbers), XMP, IPTC and comments -
// before it is uploaded. image_picker keeps all of it: on Android it even
// copies the GPS tags onto a resized copy.
//
// Nothing is re-encoded: only metadata blocks are dropped, and the image data
// is copied byte for byte, so quality and size are untouched. The one thing
// kept is the ORIENTATION, which says how to turn the picture upright (phones
// store portrait photos sideways and rely on it). It is written back as a
// minimal EXIF block holding that single value.
//
// JPEG, PNG and WebP. Anything else, or a file that doesn't parse as what it
// claims, is uploaded exactly as it was.
//
// Mirrors webapp's src/reusables/hooks/imageMetadata.ts; the two should stay
// in step.

import 'dart:io';
import 'dart:typed_data';

/// "Exif\0\0" - what opens an EXIF block inside a JPEG.
const _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];

/// Bigger files are sent as they are rather than read whole into memory.
/// Phone photos are a small fraction of this.
const _maxStripBytes = 64 * 1024 * 1024;

const _strippable = {'image/jpeg', 'image/png', 'image/webp'};

bool _startsWith(Uint8List bytes, int at, List<int> prefix) {
  if (at + prefix.length > bytes.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}

List<int> _ascii(String text) => text.codeUnits;

/// The orientation (1-8) recorded in a TIFF structure - the body of every
/// EXIF block - or null when it has none.
int? _readOrientation(Uint8List tiff) {
  if (tiff.length < 8) return null;
  final Endian endian;
  if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    endian = Endian.little; // "II"
  } else if (tiff[0] == 0x4d && tiff[1] == 0x4d) {
    endian = Endian.big; // "MM"
  } else {
    return null;
  }
  final view = ByteData.sublistView(tiff);
  final ifd = view.getUint32(4, endian);
  if (ifd + 2 > tiff.length) return null;
  final count = view.getUint16(ifd, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > tiff.length) return null;
    if (view.getUint16(entry, endian) == 0x0112) {
      final value = view.getUint16(entry + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

/// A TIFF structure holding nothing but [orientation].
Uint8List _orientationTiff(int orientation) => Uint8List.fromList([
      0x4d, 0x4d, 0x00, 0x2a, // "MM", 42: big-endian TIFF
      0x00, 0x00, 0x00, 0x08, // the one IFD starts right after this header
      0x00, 0x01, // one entry:
      0x01, 0x12, 0x00, 0x03, // Orientation, SHORT
      0x00, 0x00, 0x00, 0x01, // one value
      0x00, orientation, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, // no further IFD
    ]);

/// Worth writing back: 1 means "already upright", the same as having none.
bool _keepsOrientation(int? orientation) =>
    orientation != null && orientation != 1;

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.takeBytes();
}

// ---- JPEG ----

/// Keeps the segments the picture needs to decode and look right - JFIF, the
/// colour profile (APP2 ICC_PROFILE), Adobe's colour-transform flag (APP14)
/// and every non-APP segment - and drops all other APPn segments and
/// comments. Anything after the end-of-image marker goes too: phone cameras
/// append extra data there (motion-photo clips, secondary images, vendor
/// trailers).
Uint8List? _stripJpeg(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  final kept = <Uint8List>[];
  int? orientation;
  var changed = false;
  var insertAt = 1; // after SOI, or after a leading JFIF segment
  var pos = 2;

  while (true) {
    if (pos + 4 > bytes.length || bytes[pos] != 0xff) return null;
    final marker = bytes[pos + 1];
    if (marker == 0xff) {
      pos += 1; // a fill byte
      continue;
    }
    if (marker == 0xda) {
      // Start of scan: the image data. It runs to the end-of-image marker -
      // the first FF D9, since an FF inside image data is always followed by
      // 00 or a restart marker.
      var end = pos + 2;
      while (end + 1 < bytes.length &&
          !(bytes[end] == 0xff && bytes[end + 1] == 0xd9)) {
        end++;
      }
      if (end + 1 >= bytes.length) return null;
      if (end + 2 < bytes.length) changed = true;
      kept.add(Uint8List.sublistView(bytes, pos, end + 2));
      break;
    }
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      kept.add(Uint8List.sublistView(bytes, pos, pos + 2));
      pos += 2;
      continue;
    }
    final length = (bytes[pos + 2] << 8) | bytes[pos + 3];
    final end = pos + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    final body = pos + 4;

    final bool keep;
    if (marker == 0xe0) {
      keep = _startsWith(bytes, body, _ascii('JFIF\x00'));
      if (keep && kept.isEmpty) insertAt = 2;
    } else if (marker == 0xe1) {
      if (_startsWith(bytes, body, _exifHeader)) {
        orientation ??=
            _readOrientation(Uint8List.sublistView(bytes, body + 6, end));
      }
      keep = false;
    } else if (marker == 0xe2) {
      keep = _startsWith(bytes, body, _ascii('ICC_PROFILE\x00'));
    } else if (marker == 0xee) {
      keep = _startsWith(bytes, body, _ascii('Adobe'));
    } else if ((marker >= 0xe3 && marker <= 0xef) || marker == 0xfe) {
      keep = false;
    } else {
      keep = true;
    }
    if (keep) {
      kept.add(Uint8List.sublistView(bytes, pos, end));
    } else {
      changed = true;
    }
    pos = end;
  }

  if (!changed) return null;
  final parts = <List<int>>[Uint8List.sublistView(bytes, 0, 2), ...kept];
  if (_keepsOrientation(orientation)) {
    final tiff = _orientationTiff(orientation!);
    final length = 2 + _exifHeader.length + tiff.length;
    parts.insert(insertAt, [
      0xff, 0xe1, length >> 8, length & 0xff, ..._exifHeader, ...tiff, //
    ]);
  }
  return _concat(parts);
}

// ---- PNG ----

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return c ^ 0xffffffff;
}

const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// Text, timestamps and EXIF - none of them needed to draw the image.
const _pngMetadata = {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'};

Uint8List _pngChunk(String type, Uint8List data) {
  final typed = [..._ascii(type), ...data];
  final out = ByteData(12 + data.length);
  out.setUint32(0, data.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(4, 8 + data.length, typed);
  out.setUint32(8 + data.length, _crc32(typed));
  return bytes;
}

Uint8List? _stripPng(Uint8List bytes) {
  if (!_startsWith(bytes, 0, _pngSignature)) return null;
  final view = ByteData.sublistView(bytes);
  final kept = <Uint8List>[];
  int? orientation;
  var changed = false;
  var pos = 8;

  while (true) {
    if (pos + 12 > bytes.length) return null;
    final length = view.getUint32(pos);
    final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
    final end = pos + 12 + length;
    if (end > bytes.length) return null;
    if (_pngMetadata.contains(type)) {
      if (type == 'eXIf') {
        orientation ??= _readOrientation(
            Uint8List.sublistView(bytes, pos + 8, pos + 8 + length));
      }
      changed = true;
    } else {
      kept.add(Uint8List.sublistView(bytes, pos, end));
    }
    pos = end;
    if (type == 'IEND') {
      if (pos < bytes.length) changed = true;
      break;
    }
  }

  if (!changed) return null;
  // eXIf has to come before the image data; right after IHDR always is.
  if (_keepsOrientation(orientation)) {
    kept.insert(1, _pngChunk('eXIf', _orientationTiff(orientation!)));
  }
  return _concat([Uint8List.sublistView(bytes, 0, 8), ...kept]);
}

// ---- WebP ----

Uint8List? _stripWebp(Uint8List bytes) {
  if (!_startsWith(bytes, 0, _ascii('RIFF')) ||
      !_startsWith(bytes, 8, _ascii('WEBP'))) {
    return null;
  }
  final view = ByteData.sublistView(bytes);
  final kept = <Uint8List>[];
  int? orientation;
  var changed = false;
  Uint8List? vp8x;
  var pos = 12;

  while (pos + 8 <= bytes.length) {
    final type = String.fromCharCodes(bytes, pos, pos + 4);
    final size = view.getUint32(pos + 4, Endian.little);
    final end = pos + 8 + size + (size & 1);
    if (end > bytes.length) return null;
    if (type == 'EXIF' || type == 'XMP ') {
      if (type == 'EXIF') {
        var tiff = Uint8List.sublistView(bytes, pos + 8, pos + 8 + size);
        // Some writers put JPEG's "Exif\0\0" in front.
        if (_startsWith(tiff, 0, _exifHeader)) {
          tiff = Uint8List.sublistView(tiff, 6);
        }
        orientation ??= _readOrientation(tiff);
      }
      changed = true;
    } else {
      // A copy, so the flags can be changed without touching the original.
      final chunk = Uint8List.fromList(bytes.sublist(pos, end));
      if (type == 'VP8X') vp8x = chunk;
      kept.add(chunk);
    }
    pos = end;
  }

  if (!changed) return null;
  final keep = vp8x != null && _keepsOrientation(orientation);
  if (vp8x != null) {
    // Flags: 0x08 = has EXIF, 0x04 = has XMP.
    vp8x[8] = (vp8x[8] & ~0x0c) | (keep ? 0x08 : 0);
  }
  if (keep) {
    final tiff = _orientationTiff(orientation!);
    final header = ByteData(8)..setUint32(4, tiff.length, Endian.little);
    final headerBytes = header.buffer.asUint8List()..setRange(0, 4, _ascii('EXIF'));
    kept.addAll([headerBytes, tiff]); // EXIF belongs after the image data
  }
  final body = _concat(kept);
  final out = Uint8List(12 + body.length)
    ..setRange(0, 12, bytes)
    ..setRange(12, 12 + body.length, body);
  ByteData.sublistView(out).setUint32(4, 4 + body.length, Endian.little);
  return out;
}

/// [bytes] without their metadata, or null when there was nothing to remove
/// (or [mime] isn't a format handled here).
Uint8List? stripImageMetadata(Uint8List bytes, String mime) {
  try {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
        return _stripJpeg(bytes);
      case 'image/png':
        return _stripPng(bytes);
      case 'image/webp':
        return _stripWebp(bytes);
    }
  } catch (_) {
    // A malformed file: sent as it is rather than not at all.
  }
  return null;
}

/// A copy of the photo at [path] without its metadata, under the same file
/// name (in a folder of its own in the temp directory) - or null when there
/// was nothing to remove. The caller deletes the copy's folder when done.
Future<File?> stripImageMetadataToCopy(String path, String mime) async {
  if (!_strippable.contains(mime.toLowerCase())) return null;
  final source = File(path);
  if (await source.length() > _maxStripBytes) return null;
  final stripped = stripImageMetadata(await source.readAsBytes(), mime);
  if (stripped == null) return null;
  final folder = await Directory.systemTemp.createTemp('cl_upload_');
  final name = path.split(RegExp(r'[\\/]')).last;
  return File('${folder.path}${Platform.pathSeparator}$name')
      .writeAsBytes(stripped, flush: true);
}
