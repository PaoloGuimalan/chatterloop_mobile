// A photo's location and camera details are removed before upload; its
// pixels and its orientation are not. Real JPEG/PNG files are made with the
// `image` package (GPS, camera make, orientation), stripped, and decoded again.

import 'dart:io';
import 'dart:typed_data';

import 'package:chatterloop_app/core/media/image_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A 40x20 picture - left half red, right half blue - carrying GPS, a camera
/// make and [orientation].
img.Image _photo({int orientation = 6}) {
  final image = img.Image(width: 40, height: 20);
  img.fillRect(image, x1: 0, y1: 0, x2: 19, y2: 19, color: img.ColorRgb8(255, 0, 0));
  img.fillRect(image, x1: 20, y1: 0, x2: 39, y2: 19, color: img.ColorRgb8(0, 0, 255));
  image.exif.imageIfd.orientation = orientation;
  image.exif.imageIfd.make = 'Pixel 7';
  image.exif.gpsIfd.gpsLatitudeRef = 'N';
  image.exif.gpsIfd.gpsLatitude = 14.5995;
  return image;
}

bool _contains(Uint8List bytes, String text) =>
    String.fromCharCodes(bytes).contains(text);

int _crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xffffffff;
}

/// [image] as a PNG with its EXIF in an eXIf chunk after IHDR - written by
/// hand, since the image package's PNG encoder leaves EXIF out.
Uint8List _pngWithExif(img.Image image) {
  final png = img.encodePng(image);
  final tiff = img.OutputBuffer(bigEndian: true);
  image.exif.write(tiff);
  final data = tiff.getBytes();
  final typed = [...'eXIf'.codeUnits, ...data];
  final chunk = ByteData(12 + data.length)..setUint32(0, data.length);
  final bytes = chunk.buffer.asUint8List()..setRange(4, 8 + data.length, typed);
  chunk.setUint32(8 + data.length, _crc32(typed));
  const ihdrEnd = 8 + 25;
  return Uint8List.fromList(
      [...png.sublist(0, ihdrEnd), ...bytes, ...png.sublist(ihdrEnd)]);
}

/// Each chunk of [png] in order, with whether its CRC is right.
List<({String type, Uint8List data, bool crcOk})> _pngChunks(Uint8List png) {
  final view = ByteData.sublistView(png);
  final chunks = <({String type, Uint8List data, bool crcOk})>[];
  var pos = 8;
  while (pos + 12 <= png.length) {
    final length = view.getUint32(pos);
    final typed = png.sublist(pos + 4, pos + 8 + length);
    chunks.add((
      type: String.fromCharCodes(typed, 0, 4),
      data: Uint8List.sublistView(typed, 4),
      crcOk: view.getUint32(pos + 8 + length) == _crc32(typed),
    ));
    pos += 12 + length;
  }
  return chunks;
}

/// The EXIF in [png]'s eXIf chunk - read here because the image package's
/// PNG decoder skips that chunk.
img.ExifData? _pngExif(Uint8List png) {
  for (final chunk in _pngChunks(png)) {
    if (chunk.type == 'eXIf') {
      return img.ExifData.fromInputBuffer(img.InputBuffer(chunk.data));
    }
  }
  return null;
}

void main() {
  group('JPEG', () {
    final original = img.encodeJpg(_photo());

    test('loses GPS and camera, keeps only the orientation', () {
      expect(img.decodeJpgExif(original)!.gpsIfd.gpsLatitude, isNotNull);
      final stripped = stripImageMetadata(original, 'image/jpeg')!;
      final exif = img.decodeJpgExif(stripped)!;
      expect(exif.imageIfd.orientation, 6);
      expect(exif.imageIfd.make, isNull);
      expect(exif.gpsIfd.isEmpty, isTrue);
      expect(_contains(stripped, 'Pixel 7'), isFalse);
    });

    test('decodes to the same pixels', () {
      final before = img.decodeJpg(original)!;
      final after = img.decodeJpg(stripImageMetadata(original, 'image/jpeg')!)!;
      expect((after.width, after.height), (before.width, before.height));
      for (final (x, y) in [(5, 5), (35, 5), (19, 10), (20, 10)]) {
        expect(after.getPixel(x, y), before.getPixel(x, y));
      }
    });

    test('an upright photo carries no EXIF at all', () {
      final stripped =
          stripImageMetadata(img.encodeJpg(_photo(orientation: 1)), 'image/jpeg')!;
      expect(_contains(stripped, 'Exif'), isFalse);
    });

    test('a photo with nothing to remove is left alone', () {
      final clean = stripImageMetadata(original, 'image/jpeg')!;
      // Only the minimal orientation block is left, which is kept as is.
      final bare = img.encodeJpg(img.Image(width: 4, height: 4));
      expect(stripImageMetadata(bare, 'image/jpeg'), isNull);
      expect(clean.length, lessThan(original.length));
    });
  });

  group('PNG', () {
    test('loses its EXIF; the orientation is rebuilt with a valid CRC', () {
      final original = _pngWithExif(_photo(orientation: 8));
      expect(_pngExif(original)!.gpsIfd.gpsLatitude, isNotNull);
      final stripped = stripImageMetadata(original, 'image/png');
      expect(stripped, isNotNull);
      expect(_contains(stripped!, 'Pixel 7'), isFalse);
      final chunks = _pngChunks(stripped);
      expect(chunks.map((c) => c.type).toList(),
          ['IHDR', 'eXIf', ...chunks.skip(2).map((c) => c.type)]);
      expect(chunks.every((c) => c.crcOk), isTrue);
      final exif = _pngExif(stripped)!;
      expect(exif.imageIfd.orientation, 8);
      expect(exif.imageIfd.make, isNull);
      expect(exif.gpsIfd.isEmpty, isTrue);
      // Still a PNG that decodes to the same picture.
      final decoded = img.decodePng(stripped)!;
      expect((decoded.width, decoded.height), (40, 20));
      expect(decoded.getPixel(35, 5), img.decodePng(original)!.getPixel(35, 5));
    });
  });

  test('other types, garbage and truncated files are sent as they are', () {
    final jpeg = img.encodeJpg(_photo());
    expect(stripImageMetadata(jpeg, 'image/heic'), isNull);
    expect(stripImageMetadata(Uint8List.fromList('not an image'.codeUnits), 'image/jpeg'),
        isNull);
    expect(stripImageMetadata(Uint8List.sublistView(jpeg, 0, 40), 'image/jpeg'), isNull);
  });

  test('a copy keeps the file name, in a folder of its own', () async {
    final dir = await Directory.systemTemp.createTemp('strip_test');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/beach day.jpg')
      ..writeAsBytesSync(img.encodeJpg(_photo()));

    final copy = await stripImageMetadataToCopy(source.path, 'image/jpeg');
    addTearDown(() => copy?.parent.delete(recursive: true));
    expect(copy, isNotNull);
    expect(copy!.path.endsWith('beach day.jpg'), isTrue);
    expect(copy.parent.path, isNot(dir.path));
    expect(img.decodeJpgExif(copy.readAsBytesSync())!.gpsIfd.isEmpty, isTrue);
    // A PDF is never touched.
    expect(await stripImageMetadataToCopy(source.path, 'application/pdf'), isNull);
  });
}
