// The privacy / channel-type picker on the create forms.
//
// It used to be a loose row of fully-rounded pills, which had three problems
// this shape does not: pills size themselves to their LABELS (so "Text
// Channel" and "Voice Channel" were different widths and the pair overflowed a
// 360px screen), a row of them does not look like one control, and fully
// rounded reads as a filter you can switch off - which a privacy choice is
// not, one of the two is always on.
//
// What is pinned here is the part that is easy to lose: equal segments
// whatever the labels say, the accent following the SURFACE rather than the
// app, and the glyphs matching the ones the channel list already teaches.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _privacy = [
  CLSegmentedOption(false, 'Public', Icons.public),
  CLSegmentedOption(true, 'Private', Icons.lock_outline),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<CLSegmentedOption<Object?>> options,
  Object? value,
  Color? accent,
  double width = 360,
  ValueChanged<Object?>? onChanged,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CLSegmentedChoice<Object?>(
          label: 'Privacy',
          value: value,
          options: options,
          accent: accent,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('segments are equal width however long the labels are',
      (tester) async {
    // The case that overflowed as pills: one short label, one long.
    await _pump(tester, value: false, options: const [
      CLSegmentedOption(false, 'Text', Icons.tag),
      CLSegmentedOption(true, 'A very long option label', Icons.volume_up),
    ]);

    final first = tester.getRect(find.text('Text'));
    final second = tester.getRect(find.text('A very long option label'));
    // Measured on the tappable segment, not the text - the text is centred
    // inside it and is legitimately narrower.
    final boxes = find.descendant(
        of: find.byType(CLSegmentedChoice<Object?>),
        matching: find.byType(AnimatedContainer));
    expect(
        tester.getSize(boxes.at(0)).width, tester.getSize(boxes.at(1)).width);
    // Side by side, on one line.
    expect(first.center.dy, second.center.dy);
  });

  testWidgets('a long pair does not overflow a narrow phone', (tester) async {
    // The REAL channel-type labels at 320pt, the narrowest phone still in
    // service. As pills this exact pair blew the row out by ~75px.
    await _pump(tester, value: 'channel', width: 320, options: const [
      CLSegmentedOption('channel', 'Text Channel', Icons.tag),
      CLSegmentedOption('voice', 'Voice Channel', Icons.volume_up),
    ]);

    // A RenderFlex overflow fails the test on its own; this just proves the
    // control actually rendered rather than being skipped.
    expect(find.text('Text Channel'), findsOneWidget);
    expect(find.text('Voice Channel'), findsOneWidget);
  });

  testWidgets('every option carries its glyph', (tester) async {
    await _pump(tester, value: false, options: _privacy);

    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('only the selected segment is filled', (tester) async {
    await _pump(tester, value: true, options: _privacy);

    final boxes = find.descendant(
        of: find.byType(CLSegmentedChoice<Object?>),
        matching: find.byType(AnimatedContainer));
    final public = tester.widget<AnimatedContainer>(boxes.at(0)).decoration
        as BoxDecoration;
    final private = tester.widget<AnimatedContainer>(boxes.at(1)).decoration
        as BoxDecoration;

    expect(public.color, Colors.transparent);
    expect(private.color, isNot(Colors.transparent));
  });

  testWidgets('the fill follows the surface accent, not the app',
      (tester) async {
    // Gold on the Servers screens, brand blue for a group chat started from
    // Messages - the same control, two surfaces.
    await _pump(tester, value: true, options: _privacy);
    final brandFill = tester
        .widget<AnimatedContainer>(find
            .descendant(
                of: find.byType(CLSegmentedChoice<Object?>),
                matching: find.byType(AnimatedContainer))
            .at(1))
        .decoration as BoxDecoration;

    await _pump(tester,
        value: true, options: _privacy, accent: const Color(0xFFE0A012));
    final goldFill = tester
        .widget<AnimatedContainer>(find
            .descendant(
                of: find.byType(CLSegmentedChoice<Object?>),
                matching: find.byType(AnimatedContainer))
            .at(1))
        .decoration as BoxDecoration;

    expect(goldFill.color, isNot(brandFill.color));
  });

  testWidgets('is a smooth box, not a pill', (tester) async {
    await _pump(tester, value: false, options: _privacy);

    final box = tester.widget<Container>(find
        .descendant(
            of: find.byType(CLSegmentedChoice<Object?>),
            matching: find.byType(Container))
        .first);
    final radius =
        ((box.decoration as BoxDecoration).borderRadius as BorderRadius)
            .topLeft
            .x;
    expect(radius, CLRadii.sm);
    expect(radius, lessThan(CLRadii.pill));
  });

  testWidgets('tapping a segment reports that option', (tester) async {
    Object? picked;
    await _pump(tester,
        value: false, options: _privacy, onChanged: (v) => picked = v);

    await tester.tap(find.text('Private'));
    await tester.pump();

    expect(picked, true);
  });
}
