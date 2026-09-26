// Inter is bundled, not just named.
//
// The theme asked for 'Inter' from the start, but no font files shipped, so
// every text in the app silently fell back to the platform font (Roboto on
// Android). These check the files are in the bundle for every weight the app
// draws, and that the theme points at them.

import 'dart:convert';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every weight the app draws is in the bundle', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final inter = manifest.cast<Map<String, dynamic>>().firstWhere(
        (family) => family['family'] == 'Inter',
        orElse: () => fail('Inter is not in the font manifest'));
    final fonts = (inter['fonts'] as List).cast<Map<String, dynamic>>();

    expect({for (final font in fonts) font['weight'] ?? 400},
        containsAll([400, 500, 600, 700, 800]));
    expect(fonts.any((font) => font['style'] == 'italic'), isTrue);

    // Real font files, not placeholders.
    for (final font in fonts) {
      final data = await rootBundle.load(font['asset'] as String);
      expect(data.lengthInBytes, greaterThan(100000), reason: font['asset']);
    }
  });

  test('the theme sets its text in Inter, both themes', () {
    for (final brightness in Brightness.values) {
      final theme = buildCLTheme(brightness);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.textTheme.titleLarge?.fontFamily, 'Inter');
      expect(theme.primaryTextTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'Inter');
    }
  });

  test('the wordmark is set like webapp\'s: Inter ExtraBold, tracked in', () {
    final style =
        clWordmark(fontSize: CLType.screenTitle, color: CLColors.textLight);
    expect(style.fontFamily, 'Inter');
    expect(style.fontWeight, FontWeight.w800);
    // webapp's letter-spacing: -0.02em.
    expect(style.letterSpacing, closeTo(-0.02 * CLType.screenTitle, 1e-9));
  });

  // Inter has plain glyphs for these, drawn in the TEXT colour - a white ❤ on
  // a dark screen - and as the first font it beat the phone's colour emoji.
  // tool/inter_drop_emoji.py takes them out of the bundled files; this fails
  // if new Inter files arrive without that.
  test('no emoji is drawn by Inter - the system colour emoji draws them',
      () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final inter = manifest
        .cast<Map<String, dynamic>>()
        .firstWhere((family) => family['family'] == 'Inter');
    for (final font in (inter['fonts'] as List).cast<Map<String, dynamic>>()) {
      final asset = font['asset'] as String;
      final mapped = _mappedCodePoints(await rootBundle.load(asset));
      for (final emoji in _emojiInInter) {
        expect(mapped.contains(emoji), isFalse,
            reason: '$asset still maps ${String.fromCharCode(emoji)}');
      }
      // And the text it IS for is all still there.
      for (final text in 'Aa0·…©®™→✓'.runes) {
        expect(mapped.contains(text), isTrue,
            reason: '$asset lost ${String.fromCharCode(text)}');
      }
    }
  });

  test("Inter's licence ships with it", () async {
    final licence = await rootBundle.loadString('assets/fonts/Inter-OFL.txt');
    expect(licence, contains('SIL Open Font License'));
  });
}

/// The emoji Inter shipped its own glyph for - tool/inter_drop_emoji.py's DROP.
const _emojiInInter = [
  0x203C, 0x2049, //
  0x2194, 0x2195, 0x2196, 0x2197, 0x2198, 0x2199, 0x21A9, 0x21AA,
  0x23CF, 0x24C2, 0x25AA, 0x25B6, 0x25C0,
  0x2600, 0x2665, 0x26A0, 0x2764,
  0x2B06, 0x2B1C,
];

/// Every code point a TrueType font's cmap maps to a glyph, read from its
/// format 12 subtable (the complete one; the format 4 copy is the same
/// mapping cut to the BMP).
Set<int> _mappedCodePoints(ByteData font) {
  final numTables = font.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + 16 * i;
    final tag = String.fromCharCodes(
        List.generate(4, (k) => font.getUint8(record + k)));
    if (tag == 'cmap') cmap = font.getUint32(record + 8);
  }
  expect(cmap, isNot(-1), reason: 'no cmap table');
  final subtables = font.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final at = cmap + font.getUint32(cmap + 4 + 8 * i + 4);
    if (font.getUint16(at) != 12) continue;
    final groups = font.getUint32(at + 12);
    final codes = <int>{};
    for (var g = 0; g < groups; g++) {
      final start = font.getUint32(at + 16 + 12 * g);
      final end = font.getUint32(at + 20 + 12 * g);
      for (var c = start; c <= end; c++) {
        codes.add(c);
      }
    }
    return codes;
  }
  fail('no format 12 cmap');
}
