// A post's inline video always spans the card's width.
//
// The regression this pins: a video sized purely by AspectRatio takes the width
// on offer, derives a height, finds that height over the card's cap, and then
// shrinks the WIDTH to keep its shape - so a tall video floated in the middle
// of the card with gaps either side, while the photo in the post below it went
// edge to edge. A portrait clip is the case that shows it, which is why one is
// measured here alongside a landscape one.
//
// video_player needs a platform implementation to reach its "initialized"
// state; without one the widget never leaves its loading placeholder and the
// geometry under test never runs. Hence the fake below - it reports a size and
// nothing else.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_attachments.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Reports one fixed video size. Everything else is a no-op - nothing here
/// plays anything.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform(
    this.videoSize, {
    this.emitInitialized = true,
    this.failToCreate = false,
    this.duration = const Duration(seconds: 10),
  });

  final Size videoSize;

  /// Makes create() throw, the way an unplayable source does. The controller's
  /// initialize() future then completes with an ERROR - which is still
  /// ConnectionState.done, the case that used to render a dead player.
  final bool failToCreate;

  /// Zero is what a live stream (or a source the platform can't measure)
  /// reports.
  final Duration duration;

  /// How many controllers the app actually asked the platform for - the only
  /// way to see a duplicate, since each widget looks right on its own.
  int created = 0;

  /// False leaves the player stuck loading - the only way to hold the
  /// placeholder still long enough to measure it, since a fake that answers
  /// immediately has already resolved by the first frame.
  final bool emitInitialized;
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  /// Fails this many creations, then works - a transient failure.
  int failNextCreates = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failToCreate) throw PlatformException(code: 'VideoError');
    if (failNextCreates > 0) {
      failNextCreates--;
      throw PlatformException(code: 'VideoError');
    }
    created++;
    final id = _nextId++;
    _events[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller =
        _events.putIfAbsent(playerId, () => StreamController<VideoEvent>());
    // Queued rather than emitted now: the controller subscribes after this
    // returns, and an event sent before then is dropped - leaving initialize()
    // awaiting forever.
    scheduleMicrotask(() {
      if (!emitInitialized || controller.isClosed) return;
      controller.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: videoSize,
        rotationCorrection: 0,
      ));
    });
    return controller.stream;
  }

  /// Where getPosition() answers from - the app polls this while playing, and
  /// a moving position is what tells the controls playback is healthy.
  Duration position = Duration.zero;

  /// Push a buffering event the way a seek does. Nothing else in this fake
  /// sets isBuffering, and that flag is the whole subject of the seek test.
  void emitBuffering(bool buffering) {
    for (final controller in _events.values) {
      if (controller.isClosed) continue;
      controller.add(VideoEvent(
        eventType: buffering
            ? VideoEventType.bufferingStart
            : VideoEventType.bufferingEnd,
      ));
    }
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

const _videoUrl = 'https://example.invalid/clip.mp4';
const _otherUrl = 'https://example.invalid/other.mp4';

const PostReference _video = PostReference(
  referenceId: 'r1',
  reference: 'https://example.invalid/clip.mp4',
  mediaType: 'video/mp4',
);

void main() {
  // A post's video plays and pauses by how much of it is in view, which
  // VisibilityDetector reports - by default on a 500ms timer that would still
  // be pending when each test ends. Zero reports within the frame.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  // Controllers now outlive their widgets by a grace period (see
  // SharedVideoControllers.release), and the registry is static - so without
  // this, one test's controller is handed to the next, which then measures the
  // PREVIOUS video's aspect ratio. Isolation has to be explicit.
  setUp(() {
    // Extracted frames are cached per source for the process; a stale entry
    // would let one test's thumbnail satisfy another's.
    VideoFirstFrame.clearCache();
    // Zero = dispose synchronously, so no 8-second timer is left pending when
    // the tree unmounts. The two tests that are ABOUT the grace period opt back
    // into it explicitly.
    SharedVideoControllers.idleGrace = Duration.zero;
    SharedVideoControllers.disposeIdleNow();
  });
  tearDown(() {
    SharedVideoControllers.idleGrace = Duration.zero;
    SharedVideoControllers.disposeIdleNow();
  });

  const screen = Size(360, 900);

  /// The card's own cap - PostAttachments' _kMaxInlineHeightFactor.
  const maxInlineHeight = 900 * 0.55;

  Future<Size> pumpVideo(WidgetTester tester, Size videoSize) async {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(videoSize);

    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(
          // The real card path, so the geometry measured is what a post
          // actually renders - not a player pumped in isolation.
          child: PostAttachments(references: [_video]),
        ),
      ),
    ));
    // The first frame reports it in view, the next makes its player, the next
    // takes the initialized event.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    return tester.getSize(find.byType(VideoPlayerScreen));
  }

  // What actually broke playback: a player per row.
  //
  // Every controller is a platform decoder. A feed row mounting one meant ten
  // video posts held ten decoders, after which initialise simply failed and
  // every video said "cannot be played" - and retrying could not help, because
  // the decoders were still held by the rows above. A post's video is a player
  // from the moment it is SEEN, not the moment its row is built: a feed builds
  // rows ahead of the screen, and those hold nothing.
  group('a feed of videos holds decoders only for what is seen', () {
    const second = PostReference(
      referenceId: 'r2',
      reference: _otherUrl,
      mediaType: 'video/mp4',
    );

    testWidgets('a video below the screen has no player until scrolled to',
        (tester) async {
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: const Column(children: [
              PostAttachments(references: [_video]),
              // Built - it is in the tree - but a screen below the first.
              SizedBox(height: 1200),
              PostAttachments(references: [second]),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(InlinePostVideo), findsNWidgets(2));
      expect(fake.created, 1, reason: 'only the one on screen');
      expect(find.byType(VideoPlayerScreen), findsOneWidget);

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(fake.created, 2);
      // Each keeps its own player once made - as in a browser.
      expect(find.byType(VideoPlayerScreen), findsNWidgets(2));
      expect(SharedVideoControllers.activeCount, 2);
    });

    testWidgets('two videos on screen at once both play', (tester) async {
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(const Size(1280, 720));
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              PostAttachments(references: [_video]),
              PostAttachments(references: [second]),
            ]),
          ),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(find.byType(VideoPlayerScreen), findsNWidgets(2));
      expect(find.byIcon(Icons.pause), findsNWidgets(2),
          reason: 'both in view, both playing - neither pauses the other');
    });
  });

  group('the player pool', () {
    tearDown(() => SharedVideoControllers.maxLive = 6);

    const shown = MaterialApp(
      home: Scaffold(
          body: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true)),
    );
    const hidden = MaterialApp(home: Scaffold(body: SizedBox()));

    testWidgets('a player that fails to start is retried on a fresh one',
        (tester) async {
      // A decoder that was momentarily unavailable, a request that blipped:
      // the first attempt fails, the second works - and the viewer never sees
      // "couldn't be played".
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720))
        ..failNextCreates = 1;
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(shown);
      await tester.pump();
      await tester.pump();

      expect(fake.created, 1, reason: 'the retry got a player');
      expect(find.textContaining('unavailable'), findsNothing);
      expect(find.textContaining("couldn't"), findsNothing);
      expect(find.byType(VideoPlayer), findsOneWidget);
    });

    testWidgets('idle players past the budget go, stalest first',
        (tester) async {
      SharedVideoControllers.idleGrace = const Duration(seconds: 8);
      SharedVideoControllers.maxLive = 2;
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Widget playing(String url) => MaterialApp(
            home: Scaffold(
                body: VideoPlayerScreen(videoUrl: url, fillWidth: true)),
          );

      // Three videos in a row, each left before the next - two parked idle.
      for (final url in [
        _videoUrl,
        _otherUrl,
        'https://example.invalid/third.mp4'
      ]) {
        await tester.pumpWidget(playing(url));
        // The pool waits for a released player's dispose() before starting
        // the next, and part of video_player's dispose settles on the real
        // event loop, outside the test's fake clock - so let it run.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        await tester.pump();
        await tester.pumpWidget(hidden);
        await tester.pump();
      }
      expect(fake.created, 3);
      // The budget holds: the stalest idle one went to make room.
      expect(SharedVideoControllers.activeCount, 2);

      // The newest idle one was kept - coming back to it is instant.
      await tester.pumpWidget(playing(_otherUrl));
      await tester.pump();
      await tester.pump();
      expect(fake.created, 3, reason: 'reused, not rebuilt');

      await tester.pumpWidget(hidden);
      await tester.pump(const Duration(seconds: 9));
      expect(SharedVideoControllers.activeCount, 0);
    });
  });

  /// A player mounted directly, so it starts PAUSED.
  ///
  /// The card path can't be used for control tests any more: a post's video
  /// plays by itself once it is in view, and every assertion about the
  /// resting state would be measuring a playing video.
  Future<void> pumpPlayer(WidgetTester tester, Size videoSize) async {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(videoSize);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a landscape video fills the card width', (tester) async {
    final size = await pumpVideo(tester, const Size(1280, 720));

    expect(size.width, screen.width);
    // Under the cap, so the box is exactly the video's shape - no bars.
    expect(size.height, closeTo(screen.width * 720 / 1280, 0.5));
  });

  testWidgets('a portrait video still fills the card width', (tester) async {
    // 360 / (720/1280) = 640, past the 495 cap - the case that used to shrink
    // the width to 278 to keep the shape.
    final size = await pumpVideo(tester, const Size(720, 1280));

    expect(size.width, screen.width);
    expect(size.height, closeTo(maxInlineHeight, 0.5));
  });

  testWidgets(
      'a video narrower than the box covers it rather than leaving bars',
      (tester) async {
    await pumpVideo(tester, const Size(720, 1280));

    // Contain would fit the frame inside at 278 wide and leave bars either
    // side; cover scales it until it fills both axes and crops the overflow.
    final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
    expect(fitted.fit, BoxFit.cover);

    // And the frame keeps its own proportions on the way - the box FittedBox
    // scales carries the video's ratio, so nothing is stretched. `.first` is
    // that box; the fake platform's own view is a SizedBox too, further down.
    final frame = tester.getSize(find
        .descendant(of: find.byType(FittedBox), matching: find.byType(SizedBox))
        .first);
    expect(frame.width / frame.height, closeTo(720 / 1280, 0.001));
  });

  // Two widgets showing the same video share ONE controller.
  //
  // The bug this replaces: a feed row playing a video, then opening that post,
  // gave the screen a SECOND controller on the same url - and the screen drew
  // nothing but its background. The same post opened from search, with nothing
  // playing behind it, was fine. Counting creations is the only way to see it;
  // both widgets look correct on their own.
  group('one controller per source', () {
    setUp(() {
      // The file-level setUp above has already flushed; this just makes the
      // precondition these counts depend on explicit.
      expect(SharedVideoControllers.activeCount, 0);
    });

    testWidgets('a row and the screen share it, and it survives the push',
        (tester) async {
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Both on screen at once is exactly the state a pushed post leaves
      // behind: the row is still mounted under the route.
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(VideoPlayerScreen), findsNWidgets(2));
      expect(fake.created, 1, reason: 'two widgets, one decoder');
      expect(SharedVideoControllers.activeCount, 1);

      // Closing the screen leaves the row's copy playing - the controller is
      // only released when the LAST viewer of it goes.
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
            ]),
          ),
        ),
      ));
      await tester.pump();

      expect(fake.created, 1, reason: 'not rebuilt on the way back');
      expect(SharedVideoControllers.activeCount, 1);
    });

    testWidgets('two different videos still get one each', (tester) async {
      // Keeps the test above honest: it would also pass if the counter were
      // stuck at 1, or if every video in the app shared one controller.
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
              VideoPlayerScreen(videoUrl: _otherUrl, fillWidth: true),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(fake.created, 2);
      expect(SharedVideoControllers.activeCount, 2);
    });

    testWidgets('the last one out disposes it', (tester) async {
      SharedVideoControllers.idleGrace = const Duration(seconds: 8);
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(SharedVideoControllers.activeCount, 1);

      // Scrolled away, screen closed - whatever removed it, the decoder has to
      // go with it or a feed leaves one running per video ever shown.
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();

      // Still parked, deliberately: switching between a post's videos used to
      // fail because the old decoder was torn down the instant its widget went,
      // and the next one initialised while it was still releasing.
      // (grace enabled at the top of this test)
      expect(SharedVideoControllers.activeCount, 1);

      // Gone once the grace period expires.
      await tester.pump(const Duration(seconds: 9));
      expect(SharedVideoControllers.activeCount, 0);
    });

    testWidgets('coming back within the grace period reuses the controller',
        (tester) async {
      SharedVideoControllers.idleGrace = const Duration(seconds: 8);
      // Swiping to the next video in a post and back again - the case that
      // reported "video cannot play". No second controller is built, so there
      // is nothing to collide with a decoder that is still releasing.
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const shown = MaterialApp(
        home: Scaffold(
            body: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true)),
      );
      const hidden = MaterialApp(home: Scaffold(body: SizedBox()));

      await tester.pumpWidget(shown);
      await tester.pump();
      await tester.pump();
      expect(fake.created, 1);

      await tester.pumpWidget(hidden);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(shown);
      await tester.pump();
      await tester.pump();

      expect(fake.created, 1, reason: 'reused, not rebuilt');
      expect(SharedVideoControllers.activeCount, 1);

      await tester.pumpWidget(hidden);
      await tester.pump(const Duration(seconds: 9));
      expect(SharedVideoControllers.activeCount, 0);
    });
  });

  group('controls', () {
    testWidgets('a paused video shows play, a scrubber and a clock',
        (tester) async {
      await pumpPlayer(tester, const Size(1280, 720));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(VideoProgressIndicator), findsOneWidget);
      // 10s duration from the fake, nothing played yet.
      expect(find.text('0:00 / 0:10'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('play flips the button, and the controls follow the CONTROLLER',
        (tester) async {
      await pumpPlayer(tester, const Size(1280, 720));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('two widgets on one video agree on play state', (tester) async {
      // The controller is shared, so the controls have to read from IT rather
      // than from their own state - otherwise pausing on the post screen would
      // leave the row behind it still showing a pause button.
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(const Size(1280, 720));
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();

      // BOTH flip, from one tap.
      expect(find.byIcon(Icons.pause), findsNWidgets(2));
    });

    testWidgets('mute toggles', (tester) async {
      // A post's video starts muted - it played by itself.
      await pumpVideo(tester, const Size(1280, 720));

      await tester.tap(find.byIcon(Icons.volume_off));
      await tester.pump();
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('the scrubber runs the width of the video, inset at both edges',
        (tester) async {
      // Two bugs in one assertion. It first shared a row with the clock and the
      // mute button, which left it about a third of the width - and the seek
      // bar is the one control whose usefulness scales with its length. Given
      // its own row it then ran corner to corner, which looked welded to the
      // frame rather than sitting on it.
      //
      // Measured on the BAR, not the widget: VideoProgressIndicator's padding
      // is internal, so its own box is full width either way and would report
      // the inset as zero.
      for (final videoSize in [const Size(1280, 720), const Size(720, 1280)]) {
        await pumpVideo(tester, videoSize);

        final player = tester.getRect(find.byType(VideoPlayerScreen));
        final bar = tester.getRect(find.byType(LinearProgressIndicator).first);

        expect(bar.left - player.left, closeTo(12, 0.5), reason: '$videoSize');
        expect(player.right - bar.right, closeTo(12, 0.5),
            reason: '$videoSize');
      }
    });

    testWidgets('the clock and the mute button sit on opposite edges',
        (tester) async {
      // Flexible + Spacer left the speaker short of the right edge - Flexible
      // is loose, so it renders narrower than the half-share it claims and the
      // leftover falls AFTER the button. Same trap as the composer row.
      await pumpVideo(tester, const Size(1280, 720));

      final player = tester.getRect(find.byType(VideoPlayerScreen));
      final clock = tester.getRect(find.text('0:00 / 0:10'));
      // Off: a post's video starts muted.
      final mute = tester.getRect(find.byIcon(Icons.volume_off));

      // Both on the same inset as the scrubber above them.
      expect(clock.left - player.left, closeTo(12, 0.5));
      expect(player.right - mute.right, closeTo(12, 1.5));
    });

    testWidgets('a source that fails to load says so, rather than showing 0:00',
        (tester) async {
      // initialize() completing with an ERROR is still ConnectionState.done.
      // Falling through to the player rendered an UNINITIALISED controller:
      // aspect ratio 1.0, "0:00 / 0:00", a scrubber that went nowhere. That is
      // what "some videos always load at zero duration" was.
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(const Size(1280, 720), failToCreate: true);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.text('0:00 / 0:00'), findsNothing);
      expect(find.byType(VideoProgressIndicator), findsNothing);
    });

    testWidgets('a source with no duration hides the total and the scrubber',
        (tester) async {
      // A live stream reports zero legitimately. "0:12 / 0:00" reads as broken,
      // and a bar with nothing to scrub along is worse than no bar.
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(
          const Size(1280, 720),
          duration: Duration.zero);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:00 / 0:00'), findsNothing);
      expect(find.byType(VideoProgressIndicator), findsNothing);
    });

    testWidgets('playing one video leaves the other playing', (tester) async {
      // Each video is its own player, as in a browser: starting a second one
      // doesn't stop the first. (Their sound mixes rather than fighting over
      // audio focus - see SharedVideoControllers.)
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(const Size(1280, 720));
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
              VideoPlayerScreen(videoUrl: _otherUrl, fillWidth: true),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      // Start the first.
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Starting the second: both playing, no play button left.
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsNWidgets(2));
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('a stuck buffering flag does not strand the spinner',
        (tester) async {
      // The reported symptom, exactly: isBuffering gets set by a seek and is
      // never cleared, so the spinner sat there for the rest of the video -
      // WHILE it was playing perfectly well. The flag can't be trusted on its
      // own, so it's corroborated against the position actually moving.
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      // Buffering claimed, and it never gets cleared.
      fake.emitBuffering(true);
      await tester.pump();

      // Frames ARE flowing: the position keeps advancing on each poll.
      for (var i = 1; i <= 4; i++) {
        fake.position = Duration(seconds: i);
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'position is advancing, so it is not stalled');

      // Now it genuinely stalls - same flag, but the position stops moving.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'position frozen while buffering IS a stall');
    });

    testWidgets('seeking while paused does not strand the spinner',
        (tester) async {
      // A seek sets isBuffering, but the plugin only clears it when playback
      // actually RESUMES - so on a paused video the spinner stayed up forever.
      // That's the "loader never disappears when I seek" report.
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      // Paused + buffering: nothing the viewer is waiting on, so no spinner.
      fake.emitBuffering(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Playing + buffering IS worth reporting - dropping the spinner
      // entirely would have been the lazy fix - but only once the position has
      // actually stopped moving for a beat. See the test above.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      fake.emitBuffering(true);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('the bar survives a chat-bubble-sized video', (tester) async {
      // Same overlay renders over a message thumbnail, which can be narrower
      // than the clock and the mute button put together.
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(const Size(1280, 720));
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child:
                  VideoPlayerScreen(videoUrl: 'https://example.invalid/c.mp4'),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('controls are not scaled by the cover FittedBox',
        (tester) async {
      // They're layered on the BOX, outside the FittedBox - inside it, a
      // portrait video (which scales up hard to cover) would blow the buttons
      // up with the frame.
      await pumpPlayer(tester, const Size(720, 1280));

      final button = tester.getSize(find.byIcon(Icons.play_arrow));
      expect(button.width, closeTo(30, 0.5));
      expect(button.height, closeTo(30, 0.5));
    });
  });

  testWidgets('the loading placeholder is full width too', (tester) async {
    // Before the video resolves there is no aspect ratio to work from, so the
    // placeholder is a plain height-only SizedBox and the WIDTH comes from the
    // caller - PostAttachments wraps it in a full-width Container. That's what
    // this holds: whatever the placeholder does internally, the post path must
    // not reflow when the video lands.
    VideoPlayerPlatform.instance =
        _FakeVideoPlayerPlatform(const Size(1280, 720), emitInitialized: false);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: VideoPlayerScreen(videoUrl: _videoUrl, fillWidth: true),
        ),
      ),
    ));
    await tester.pump();

    // Still loading - otherwise this measures the resolved player and proves
    // nothing about the placeholder.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(VideoPlayerScreen)).width, screen.width);
  });

  // A post's video has the video's shape from the start - full width, as tall
  // as its proportions make it up to the cap, cropped to cover past that - the
  // way webapp's lone-video post does. It used to be a fixed 220px still that
  // jumped to a 200px spinner on play, then to the video's shape.
  //
  // The shape comes from the first frame, which stands in while the player
  // loads; there is no platform to extract one here, so the tests seed what it
  // would say - and use a player that never finishes loading, so what is
  // measured is the frame's shape and not the player's correction of it.
  group('the video takes its own shape', () {
    Future<Size> pumpPost(
      WidgetTester tester, {
      double? frameRatio,
      bool playInline = true,
      _FakeVideoPlayerPlatform? platform,
    }) async {
      VideoPlayerPlatform.instance = platform ??
          _FakeVideoPlayerPlatform(const Size(1280, 720),
              emitInitialized: false);
      VideoFirstFrame.debugSetAspectRatio(_videoUrl, frameRatio);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostAttachments(
                references: const [_video], playInline: playInline),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return tester.getSize(find.byType(InlinePostVideo));
    }

    testWidgets('a landscape video is its own shape, full width',
        (tester) async {
      final size = await pumpPost(tester, frameRatio: 4 / 3);

      expect(size.width, screen.width);
      expect(size.height, closeTo(screen.width * 3 / 4, 0.5));
    });

    testWidgets('a portrait video is capped, and covers rather than bars',
        (tester) async {
      final size = await pumpPost(tester, frameRatio: 9 / 16);

      expect(size.width, screen.width);
      expect(size.height, closeTo(maxInlineHeight, 0.5));
    });

    testWidgets('an unknown shape falls back to 16:9', (tester) async {
      final size = await pumpPost(tester);

      expect(size.width, screen.width);
      expect(size.height, closeTo(screen.width * 9 / 16, 0.5));
    });

    testWidgets('the player loads over the frame, in the same box',
        (tester) async {
      final size = await pumpPost(tester, frameRatio: 4 / 3);

      // A player straight away - no play badge to press first.
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsNothing);
      // Still loading, and filling the box rather than collapsing it.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(VideoPlayerScreen)), size);
    });

    testWidgets('the player corrects a shape the frame got wrong',
        (tester) async {
      // A square video whose frame could not be read: 16:9 until it loads.
      await pumpPost(tester,
          platform: _FakeVideoPlayerPlatform(const Size(720, 720)));
      await tester.pump();

      final size = tester.getSize(find.byType(InlinePostVideo));
      expect(size.width, screen.width);
      expect(size.height, closeTo(screen.width, 0.5));
    });

    testWidgets(
        'a preview (share, moderation) is a still: same shape, no player',
        (tester) async {
      final size = await pumpPost(tester, frameRatio: 4 / 3, playInline: false);

      expect(size.width, screen.width);
      expect(size.height, closeTo(screen.width * 3 / 4, 0.5));
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    });
  });

  // A post's video plays by itself once more than half of it is in view, and
  // pauses once none of it is - scrolled away, under another screen. Muted the
  // first time: it started unasked.
  group('plays while in view', () {
    /// The video at [top] px down a scrolling page 3 screens tall.
    Future<(_FakeVideoPlayerPlatform, ScrollController)> pumpFeed(
        WidgetTester tester,
        {double top = 0}) async {
      final fake = _FakeVideoPlayerPlatform(const Size(1280, 720));
      VideoPlayerPlatform.instance = fake;
      VideoFirstFrame.debugSetAspectRatio(_videoUrl, 16 / 9);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(children: [
              SizedBox(height: top),
              const PostAttachments(references: [_video]),
              SizedBox(height: screen.height * 3),
            ]),
          ),
        ),
      ));
      await settle(tester);
      return (fake, scroll);
    }

    /// The one video player in the tree, on screen or not.
    VideoPlayerController player(WidgetTester tester) => tester
        .widget<VideoPlayer>(find.byType(VideoPlayer, skipOffstage: false))
        .controller;

    // The box is 360 x 202.5 (16:9 at full width); the screen 900 tall.
    const boxHeight = 360 * 9 / 16;

    testWidgets('in view, it plays - muted, since it started unasked',
        (tester) async {
      await pumpFeed(tester);

      expect(player(tester).value.isPlaying, isTrue);
      expect(player(tester).value.volume, 0);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('less than half in view, it waits', (tester) async {
      // 60px of it showing at the bottom of the screen: a third.
      await pumpFeed(tester, top: screen.height - 60);

      expect(find.byType(VideoPlayerScreen), findsOneWidget,
          reason: 'on screen, so it has its player and controls');
      expect(player(tester).value.isPlaying, isFalse);
    });

    testWidgets('scrolled out of view it pauses, and plays on the way back',
        (tester) async {
      final (_, scroll) = await pumpFeed(tester);
      expect(player(tester).value.isPlaying, isTrue);

      // Two thirds out: still partly in view, so it carries on.
      scroll.jumpTo(boxHeight * 2 / 3);
      await settle(tester);
      expect(player(tester).value.isPlaying, isTrue);

      // All the way out.
      scroll.jumpTo(boxHeight + 50);
      await settle(tester);
      expect(player(tester).value.isPlaying, isFalse);

      scroll.jumpTo(0);
      await settle(tester);
      expect(player(tester).value.isPlaying, isTrue);
    });

    testWidgets('a video you paused in view stays paused', (tester) async {
      await pumpFeed(tester);
      await player(tester).pause();
      await settle(tester);

      expect(player(tester).value.isPlaying, isFalse,
          reason: 'playing by itself is for coming INTO view, not staying');
    });

    testWidgets('your unmute sticks when it plays by itself again',
        (tester) async {
      final (_, scroll) = await pumpFeed(tester);
      await player(tester).setVolume(1);

      scroll.jumpTo(boxHeight + 50);
      await settle(tester);
      scroll.jumpTo(0);
      await settle(tester);

      expect(player(tester).value.isPlaying, isTrue);
      expect(player(tester).value.volume, 1);
    });

    testWidgets('another screen over it pauses it', (tester) async {
      await pumpFeed(tester);
      expect(player(tester).value.isPlaying, isTrue);

      Navigator.of(tester.element(find.byType(InlinePostVideo))).push(
          MaterialPageRoute(builder: (_) => const Scaffold(body: SizedBox())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      expect(player(tester).value.isPlaying, isFalse);
    });

    testWidgets('opening the post over its row keeps it playing',
        (tester) async {
      final (fake, _) = await pumpFeed(tester);

      // The post screen shows the same video - the same player.
      Navigator.of(tester.element(find.byType(InlinePostVideo))).push(
          MaterialPageRoute(
              builder: (_) => const Scaffold(
                  body: SingleChildScrollView(
                      child: PostAttachments(references: [_video])))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      expect(fake.created, 1, reason: 'one player for both');
      final controller = tester
          .widget<VideoPlayer>(
              find.byType(VideoPlayer, skipOffstage: false).first)
          .controller;
      expect(controller.value.isPlaying, isTrue);
    });

    testWidgets('full screen keeps it playing', (tester) async {
      await pumpFeed(tester);
      final controller = player(tester);

      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      expect(controller.value.isPlaying, isTrue);
    });
  });
}

/// Enough frames for a visibility report to land, the player it asks for to
/// be made and loaded, and play or pause to follow.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}
