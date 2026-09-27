// The editor's preview player (lib/core/media/sequence_player.dart) keeping
// time while it plays.
//
// The judder this pins: the playhead ran on its own clock and pulled the
// video after it - a seek whenever the two were 300ms apart. A seek stalls a
// video; a phone's decoder took longer than that to land one, so the next
// check found it behind again, and the preview went from seek to seek. Now
// a playing video keeps time and is never seeked mid-play.
//
// The fake platform below plays nothing: each test moves the players'
// positions along itself, the way a real video would report them.

import 'dart:async';

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/sequence_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FakeVideos extends VideoPlayerPlatform {
  _FakeVideos({this.startTakes = Duration.zero});

  /// How long a player takes to start - a phone's is a few hundred ms.
  final Duration startTakes;

  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, String> _uris = {};
  final Map<int, Duration> positions = {};
  final Set<int> playing = {};

  /// Every seek asked for, and every volume sent, by file name.
  final List<(String, Duration)> seeks = [];
  final List<(String, double)> volumes = [];
  int _next = 0;

  String _name(int id) => _uris[id]!.split('/').last;

  int _id(String file) =>
      _uris.entries.lastWhere((e) => e.value.endsWith(file)).key;

  Duration positionOf(String file) => positions[_id(file)]!;
  bool isPlaying(String file) => playing.contains(_id(file));
  List<Duration> seeksOf(String file) =>
      [for (final (name, to) in seeks) if (name == file) to];

  /// How many players were made for [file].
  int madeFor(String file) =>
      _uris.values.where((uri) => uri.endsWith(file)).length;

  /// [file] plays to its end, the way a real one reports it.
  void runToEnd(String file) {
    final id = _id(file);
    positions[id] = const Duration(seconds: 20);
    _events[id]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  /// [by] of playback: every playing player moves on - at [speed] for the
  /// files named there (a video falling behind).
  void playFor(Duration by, {Map<String, double> speed = const {}}) {
    for (final id in playing) {
      final rate = speed[_name(id)] ?? 1;
      positions[id] = positions[id]! +
          Duration(microseconds: (by.inMicroseconds * rate).round());
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    _uris[id] = options.dataSource.uri ?? '';
    positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final events =
        _events.putIfAbsent(playerId, () => StreamController<VideoEvent>());
    // Queued: the controller subscribes after this returns.
    void started() {
      if (events.isClosed) return;
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 20),
        size: const Size(1080, 1920),
        rotationCorrection: 0,
      ));
    }

    if (startTakes == Duration.zero) {
      scheduleMicrotask(started);
    } else {
      Timer(startTakes, started);
    }
    return events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    playing.remove(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add((_name(playerId), position));
    positions[playerId] = position;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes.add((_name(playerId), volume));

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

MediaSource _video(String name) => MediaSource(
      path: '/in/$name.mp4',
      kind: MediaKind.video,
      width: 1080,
      height: 1920,
      duration: const Duration(seconds: 20),
      hasAudio: true,
    );

const _photo = MediaSource(
    path: '/in/photo.jpg', kind: MediaKind.image, width: 1080, height: 1920);

Duration _ms(int ms) => Duration(milliseconds: ms);

/// Plays for [time] in 20ms frames, the fake's videos moving on with it -
/// or, [stalled], standing still.
Future<void> _run(WidgetTester tester, _FakeVideos fake, Duration time,
    {bool stalled = false, Map<String, double> speed = const {}}) async {
  const frame = Duration(milliseconds: 20);
  for (var done = Duration.zero; done < time; done += frame) {
    if (!stalled) fake.playFor(frame, speed: speed);
    await tester.pump(frame);
  }
}

/// Lets the players start (initialize, the first seek).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  late _FakeVideos fake;

  setUp(() {
    fake = _FakeVideos();
    VideoPlayerPlatform.instance = fake;
  });

  testWidgets(
      'a playing video keeps time: never seeked mid-play, the playhead '
      'follows it, and waits for it when it stalls', (tester) async {
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(clips: [
      MediaLayer(source: _video('a'), trim: TrimRange(_ms(2000), _ms(10000))),
    ]));
    await _settle(tester);
    // Waiting at the start of its part.
    expect(fake.positionOf('a.mp4'), _ms(2000));

    player.play();
    await tester.pump();
    fake.seeks.clear();
    fake.volumes.clear();

    await _run(tester, fake, const Duration(seconds: 1));
    expect(fake.seeks, isEmpty);
    // A second into its part, a second into the edit.
    expect(player.position.value.inMilliseconds, closeTo(1000, 150));

    // The video stalls: the playhead doesn't run on without it.
    final before = player.position.value;
    await _run(tester, fake, _ms(600), stalled: true);
    expect(player.position.value - before, lessThanOrEqualTo(_ms(150)));
    expect(fake.seeks, isEmpty);

    // Its volume went to the platform once, not on every frame.
    expect(fake.volumes, isEmpty);

    player.dispose();
  });

  testWidgets('the next clip waits at its start, so it just plays',
      (tester) async {
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(clips: [
      MediaLayer(source: _video('a'), trim: TrimRange(_ms(0), _ms(2000))),
      MediaLayer(source: _video('b'), trim: TrimRange(_ms(5000), _ms(8000))),
    ]));
    await _settle(tester);
    // Made ready while the first plays.
    expect(fake.positionOf('b.mp4'), _ms(5000));

    player.play();
    await tester.pump();
    fake.seeks.clear();

    await _run(tester, fake, _ms(2600));
    // Past the first clip: the second playing, from where it waited - no
    // seek at the join.
    expect(player.currentIndex, 1);
    expect(fake.seeksOf('b.mp4'), isEmpty);
    expect(fake.isPlaying('b.mp4'), isTrue);
    expect(fake.isPlaying('a.mp4'), isFalse);
    expect(player.position.value.inMilliseconds, closeTo(2600, 200));

    player.dispose();
  });

  testWidgets('a layer plays along, pulled back only when well off',
      (tester) async {
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(
      clips: const [MediaLayer(source: _photo, duration: Duration(seconds: 10))],
      overlays: [
        OverlayClip(
          clip: MediaLayer(
              source: _video('o'), trim: TrimRange(_ms(0), _ms(8000))),
          start: _ms(1000),
        ),
      ],
    ));
    await _settle(tester);
    player.play();
    await tester.pump();
    fake.seeks.clear();

    // Up to it: it starts from where it waited, no seek.
    await _run(tester, fake, _ms(1100));
    expect(fake.isPlaying('o.mp4'), isTrue);
    expect(fake.seeksOf('o.mp4'), isEmpty);

    // Falling behind: a little is left alone; well off, it is pulled back -
    // once, then given time to land.
    await _run(tester, fake, _ms(2500), speed: {'o.mp4': 0.7});
    expect(fake.seeksOf('o.mp4'), hasLength(1));

    player.dispose();
  });

  testWidgets('a player let go while it was starting is made again when '
      'wanted', (tester) async {
    // A reorder, a scrub: a clip's player goes before it has started, and
    // comes back into play straight after.
    fake = _FakeVideos(startTakes: _ms(300));
    VideoPlayerPlatform.instance = fake;
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(clips: [
      MediaLayer(source: _video('a'), trim: TrimRange(_ms(0), _ms(4000))),
      MediaLayer(source: _video('b'), trim: TrimRange(_ms(0), _ms(4000))),
      MediaLayer(source: _video('c'), trim: TrimRange(_ms(0), _ms(4000))),
    ]));
    await tester.pump(_ms(50));
    // Away to the last clip before the first's player has started...
    player.seek(_ms(9000));
    await tester.pump(_ms(50));
    // ...and back.
    player.seek(_ms(500));
    await tester.pump(_ms(400));
    await _settle(tester);
    expect(fake.madeFor('a.mp4'), 2);
    expect(player.videoFor(0), isNotNull);

    player.dispose();
    // The ones let go never finish starting: their time limit runs out.
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets("a video that ran to its file's end is sent back and plays on",
      (tester) async {
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(clips: [
      MediaLayer(source: _video('a'), trim: TrimRange(_ms(2000), _ms(10000))),
    ]));
    await _settle(tester);
    player.play();
    await tester.pump();
    await _run(tester, fake, _ms(500));
    // It ends (video_player then parks it on its last frame, paused).
    fake.runToEnd('a.mp4');
    await _settle(tester);
    expect(fake.isPlaying('a.mp4'), isFalse);
    // Past the grace a seek is given to land...
    await tester.runAsync(() => Future<void>.delayed(_ms(1300)));
    fake.seeks.clear();
    await _run(tester, fake, _ms(200));
    // ...it is sent back to the playhead, and plays.
    expect(fake.seeksOf('a.mp4'), hasLength(1));
    expect(fake.seeksOf('a.mp4').single, lessThan(_ms(10000)));
    expect(fake.isPlaying('a.mp4'), isTrue);

    player.dispose();
  });

  testWidgets('a blank plays through by the clock; the clip after it waits '
      'at its start', (tester) async {
    final player = SequencePlayer(vsync: tester);
    player.setEdit(Composition(clips: [
      MediaLayer(source: _video('a'), trim: TrimRange(_ms(0), _ms(1000))),
      MediaLayer(
        source: _video('b'),
        trim: TrimRange(_ms(2000), _ms(4000)),
        gapBefore: _ms(1000),
      ),
    ]));
    await _settle(tester);
    expect(fake.positionOf('b.mp4'), _ms(2000));
    player.play();
    await tester.pump();
    fake.seeks.clear();

    await _run(tester, fake, _ms(1400));
    // In the blank: no clip, the first one stopped.
    expect(player.currentIndex, isNull);
    expect(fake.isPlaying('a.mp4'), isFalse);
    expect(player.position.value.inMilliseconds, closeTo(1400, 150));

    await _run(tester, fake, _ms(900));
    // The second, from where it waited.
    expect(player.currentIndex, 1);
    expect(fake.isPlaying('b.mp4'), isTrue);
    expect(fake.seeksOf('b.mp4'), isEmpty);

    player.dispose();
  });
}
