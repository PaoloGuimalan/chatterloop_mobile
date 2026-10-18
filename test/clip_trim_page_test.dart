import 'dart:async';

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/views/moments/clip_trim_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PreviewVideos extends VideoPlayerPlatform {
  bool fail = true;
  bool hang = false;
  int made = 0;
  final disposed = <int>[];
  final played = <int>[];
  final events = <int, StreamController<VideoEvent>>{};
  Completer<void>? releaseGate;

  void initialized(int id) => events[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 20),
      size: const Size(1080, 1920)));

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = made++;
    events[id] = StreamController<VideoEvent>(onCancel: () async {});
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final stream = events[playerId]!;
    scheduleMicrotask(() {
      if (stream.isClosed || hang) return;
      if (fail) {
        stream.addError(
            PlatformException(code: 'preview', message: 'Decoder failed'));
      } else {
        stream.add(VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 20),
            size: const Size(1080, 1920)));
      }
    });
    return stream.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    if (releaseGate != null) await releaseGate!.future;
    await events[playerId]!.close();
  }

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox();
}

const _source = MediaSource(
    path: '/in/video.mp4',
    kind: MediaKind.video,
    width: 1080,
    height: 1920,
    duration: Duration(seconds: 20),
    hasAudio: true);

Future<void> _open(WidgetTester tester, _PreviewVideos platform) async {
  VideoPlayerPlatform.instance = platform;
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => ClipTrimPage.open(context,
                        source: _source, maxSpan: const Duration(seconds: 10)),
                    child: const Text('Open')),
              ))));
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

void main() {
  testWidgets('error controls remain available while native disposal waits',
      (tester) async {
    final platform = _PreviewVideos()..releaseGate = Completer<void>();
    await _open(tester, platform);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    platform.releaseGate!.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('initializing in background waits for resume to play',
      (tester) async {
    final platform = _PreviewVideos()..hang = true;
    await _open(tester, platform);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    platform.initialized(0);
    await tester.pump();
    expect(platform.played, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.played, [0]);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
  });

  testWidgets('preview failure offers Retry and Skip, retry can recover',
      (tester) async {
    final platform = _PreviewVideos();
    await _open(tester, platform);
    expect(find.text('Could not preview this video.'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    platform.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.made, 2);
    expect(platform.disposed, [0]);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.disposed, [0, 1]);
  });

  testWidgets('stalled initialization times out and Skip closes the page',
      (tester) async {
    final platform = _PreviewVideos()..hang = true;
    await _open(tester, platform);
    await tester.pump(const Duration(seconds: 16));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('Could not preview this video.'), findsOneWidget);
    expect(platform.disposed, [0]);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('leaving while initialization is pending releases the player',
      (tester) async {
    final platform = _PreviewVideos()..hang = true;
    await _open(tester, platform);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(platform.disposed, [0]);
    await tester.pump(const Duration(seconds: 16));
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
