// The watermark with the author's handle under the logo
// (lib/core/media/watermark_image.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/watermark_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The app's font, as on the phone (tests otherwise draw a stand-in).
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf')))
        .load();
  });

  test('the handle goes under the wordmark, beside the icon', () async {
    const mark = Watermark.chatterloop;
    final data = await rootBundle.load(mark.asset);
    final logoPng = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final logo = await _decode(logoPng);

    // The tool's layout: the wordmark right of the icon, in the upper part.
    final layout = jsonDecode(await rootBundle.loadString(mark.layout!))
        as Map<String, dynamic>;
    expect(layout['width'], logo.width);
    final box = (layout['wordmark'] as List).cast<num>();
    final wordmark = Rect.fromLTRB(box[0].toDouble(), box[1].toDouble(),
        box[2].toDouble(), box[3].toDouble());
    expect(wordmark.left, greaterThan(logo.width * 0.15));
    expect(wordmark.bottom, lessThan(logo.height * 0.75));

    final png = await watermarkWithHandle(logoPng, '@paolo.portes',
        fontSize: mark.handleSize / mark.width, wordmark: wordmark);
    final stamped = await _decode(png);
    // Over the logo's own picture: as wide, and at most a little taller.
    expect(stamped.width, logo.width);
    expect(stamped.height, greaterThanOrEqualTo(logo.height));
    expect(stamped.height, lessThan(logo.height * 1.4));

    // A far longer handle is shown whole: the picture grows to the right
    // for it (the logo stays put - the encoder scales by the logo's width).
    final long = await _decode(await watermarkWithHandle(
        logoPng, '@${'a' * 60}',
        fontSize: mark.handleSize / mark.width, wordmark: wordmark));
    expect(long.width, greaterThan(logo.width * 2));
    expect(long.height, stamped.height);

    // WATERMARK_PREVIEW=<file> [WATERMARK_HANDLE=@name]: the real picture,
    // for looking at.
    final preview = Platform.environment['WATERMARK_PREVIEW'];
    if (preview != null) {
      final handle = Platform.environment['WATERMARK_HANDLE'];
      await File(preview).writeAsBytes(handle == null
          ? png
          : await watermarkWithHandle(logoPng, handle,
              fontSize: mark.handleSize / mark.width, wordmark: wordmark));
    }
  });
}
