import 'dart:math' as math;

import 'package:chatterloop_app/core/media/canvas_geometry.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 360.0, _h = 640.0;
const _mediaW = 1600.0, _mediaH = 1200.0;

/// Where canvas point ([x], [y]) falls in the media's own pixels, with the
/// layer placed per [t] - the inverse of what the renderer draws.
(double, double) _mediaPointAt(LayerTransform t, double x, double y) {
  final p = placeLayer(
    mediaWidth: _mediaW,
    mediaHeight: _mediaH,
    canvasWidth: _w,
    canvasHeight: _h,
    transform: t,
  );
  final f = p.width / _mediaW;
  final dx = x - p.centerX, dy = y - p.centerY;
  final c = math.cos(p.rotation), s = math.sin(p.rotation);
  return (
    (dx * c + dy * s) / f + _mediaW / 2,
    (-dx * s + dy * c) / f + _mediaH / 2,
  );
}

LayerTransform _gesture(
  LayerTransform start, {
  required Offset from,
  required Offset to,
  double scale = 1,
  double rotation = 0,
}) =>
    transformForGesture(
      start: start,
      canvasWidth: _w,
      canvasHeight: _h,
      startFocalX: from.dx,
      startFocalY: from.dy,
      focalX: to.dx,
      focalY: to.dy,
      scale: scale,
      rotation: rotation,
    );

void main() {
  group('editor gestures', () {
    test('a drag moves the layer by the finger travel', () {
      final t = _gesture(LayerTransform.fit,
          from: const Offset(100, 100), to: const Offset(136, 36));
      expect(t.cx, closeTo(0.5 + 36 / _w, 1e-9));
      expect(t.cy, closeTo(0.5 - 64 / _h, 1e-9));
      expect(t.scale, 1);
      expect(t.rotationDeg, 0);
    });

    test('a pinch keeps the pixel under the fingers under them', () {
      const start = LayerTransform(cx: 0.45, cy: 0.52, scale: 1.3);
      const fingers = Offset(250, 300);
      final before = _mediaPointAt(start, fingers.dx, fingers.dy);
      final t = _gesture(start, from: fingers, to: fingers, scale: 1.8);
      final after = _mediaPointAt(t, fingers.dx, fingers.dy);
      expect(t.scale, closeTo(1.3 * 1.8, 1e-9));
      expect(after.$1, closeTo(before.$1, 1e-6));
      expect(after.$2, closeTo(before.$2, 1e-6));
    });

    test('a twist turns the layer about the fingers, clockwise', () {
      const start = LayerTransform(cx: 0.5, cy: 0.5, scale: 1.2);
      const fingers = Offset(200, 380);
      final before = _mediaPointAt(start, fingers.dx, fingers.dy);
      final t =
          _gesture(start, from: fingers, to: fingers, rotation: math.pi / 6);
      final after = _mediaPointAt(t, fingers.dx, fingers.dy);
      expect(t.rotationDeg, closeTo(30, 1e-9));
      expect(after.$1, closeTo(before.$1, 1e-6));
      expect(after.$2, closeTo(before.$2, 1e-6));
    });

    test('pinch, twist and drag together still track the fingers', () {
      const start =
          LayerTransform(cx: 0.4, cy: 0.6, scale: 0.9, rotationDeg: 10);
      const from = Offset(120, 420), to = Offset(210, 330);
      final before = _mediaPointAt(start, from.dx, from.dy);
      final t =
          _gesture(start, from: from, to: to, scale: 1.25, rotation: -0.4);
      final after = _mediaPointAt(t, to.dx, to.dy);
      expect(after.$1, closeTo(before.$1, 1e-6));
      expect(after.$2, closeTo(before.$2, 1e-6));
    });

    test('the layer centre stays on the canvas', () {
      final t = _gesture(LayerTransform.fit,
          from: const Offset(10, 10), to: const Offset(2000, -900));
      expect(t.cx, 1);
      expect(t.cy, 0);
    });

    test('zoom is held within its limits', () {
      expect(
        _gesture(LayerTransform.fit,
                from: Offset.zero, to: Offset.zero, scale: 0.01)
            .scale,
        0.2,
      );
      expect(
        _gesture(LayerTransform.fit,
                from: Offset.zero, to: Offset.zero, scale: 50)
            .scale,
        10,
      );
    });

    test('rotation snaps to straight within 4 degrees', () {
      expect(snapRotation(3.5), 0);
      expect(snapRotation(-3.9), 0);
      expect(snapRotation(87), 90);
      expect(snapRotation(-92), -90);
      expect(snapRotation(184), 180);
      expect(snapRotation(5), 5);
      expect(snapRotation(45), 45);
    });
  });

  group('trim window', () {
    const total = Duration(minutes: 5);
    const max = Duration(minutes: 2);
    const min = Duration(seconds: 1);
    TrimRange constrain(TrimRange previous, int startS, int endS,
            {Duration total = total}) =>
        TrimBar.constrain(
          previous: previous,
          start: Duration(seconds: startS),
          end: Duration(seconds: endS),
          total: total,
          minSpan: min,
          maxSpan: max,
        );
    const s = Duration(seconds: 1);

    test('an allowed range is kept as picked', () {
      final r = constrain(const TrimRange(Duration.zero, max), 10, 70);
      expect((r.start, r.end), (s * 10, s * 70));
    });

    test('pulling the end past 2 minutes drags the start along', () {
      final r = constrain(const TrimRange(Duration.zero, max), 0, 150);
      expect((r.start, r.end), (s * 30, s * 150));
    });

    test('pulling the start back past 2 minutes drags the end along', () {
      final r = constrain(TrimRange(s * 60, s * 180), 20, 180);
      expect((r.start, r.end), (s * 20, s * 140));
    });

    test('the window never gets shorter than a second', () {
      final r = constrain(TrimRange(s * 10, s * 40), 40, 40);
      expect((r.start, r.end), (s * 40, s * 41));
    });

    test('a minimum pushed past the end slides back inside', () {
      final r = constrain(TrimRange(s * 250, s * 300), 300, 300);
      expect((r.start, r.end), (s * 299, s * 300));
    });

    test('a clip shorter than the limits can be used whole', () {
      const short = Duration(milliseconds: 700);
      final r = TrimBar.constrain(
        previous: const TrimRange(Duration.zero, short),
        start: Duration.zero,
        end: short,
        total: short,
        minSpan: min,
        maxSpan: max,
      );
      expect((r.start, r.end), (Duration.zero, short));
    });

    test('lengths read naturally', () {
      expect(TrimBar.lengthLabel(const Duration(seconds: 30)), '30s');
      expect(TrimBar.lengthLabel(const Duration(milliseconds: 7500)), '7.5s');
      expect(TrimBar.lengthLabel(const Duration(seconds: 102)), '1:42');
      expect(TrimBar.clock(const Duration(seconds: 65)), '1:05');
    });

    testWidgets('the bar shows the picked part and the whole', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: TrimBar(
            icon: Icons.content_cut_rounded,
            title: 'Trim',
            total: const Duration(seconds: 200),
            range: TrimRange(s * 5, s * 47),
            maxSpan: max,
            onChanged: (_) {},
          ),
        ),
      ));
      expect(find.text('Trim'), findsOneWidget);
      expect(find.text('42s'), findsOneWidget);
      expect(find.text('0:05'), findsOneWidget);
      expect(find.text('0:47'), findsOneWidget);
      expect(find.text('of 3:20'), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
    });
  });
}
