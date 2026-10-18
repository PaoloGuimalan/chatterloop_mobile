import 'dart:async';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/views/moments/create_moment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/pending_render_harness.dart';

class _DisposalVideos extends VideoPlayerPlatform {
  final gate = Completer<void>();
  final _events = <int, StreamController<VideoEvent>>{};
  var _next = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;
  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    final events = _events[id] = StreamController<VideoEvent>();
    scheduleMicrotask(() => events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 20),
        size: const Size(1080, 1920),
        rotationCorrection: 0)));
    return events.stream;
  }

  @override
  Future<void> dispose(int id) async {
    await gate.future;
    await _events[id]?.close();
  }

  @override
  Future<void> play(int id) async {}
  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> seekTo(int id, Duration at) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mix) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

void main() {
  final harness = PendingRenderHarness();
  setUpAll(harness.install);
  tearDownAll(harness.dispose);
  testWidgets('a new share cannot revive an attempt awaiting native disposal',
      (tester) async {
    final original = VideoPlayerPlatform.instance;
    final videos = _DisposalVideos();
    VideoPlayerPlatform.instance = videos;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: CreateMomentScreen(
            initialEdit: Composition(clips: [
      MediaLayer(
          source: MediaSource(
              path: '/in/clip.mp4',
              kind: MediaKind.video,
              width: 1080,
              height: 1920,
              duration: Duration(seconds: 20)))
    ]))));
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(harness.encodes, 0);
    await tester.tap(find.byTooltip('Close editor'));
    await harness.until(
        tester, () => find.text('Leave this edit?').evaluate().isNotEmpty);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    videos.gate.complete();
    await harness.until(tester, () => harness.activeSession != null);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(harness.encodes, 1,
        reason: 'only the current attempt may create a render job');
    await tester.tap(find.byTooltip('Close editor'));
    await harness.until(
        tester, () => find.text('Leave this edit?').evaluate().isNotEmpty);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  });
}
