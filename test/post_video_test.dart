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

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failToCreate) throw PlatformException(code: 'VideoError');
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

const PostReference _video = PostReference(
  referenceId: 'r1',
  reference: 'https://example.invalid/clip.mp4',
  mediaType: 'video/mp4',
);

void main() {
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
          child: PostAttachments(references: [_video]),
        ),
      ),
    ));
    // One frame to create the controller, one for the initialized event.
    await tester.pump();
    await tester.pump();

    return tester.getSize(find.byType(VideoPlayerScreen));
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

  testWidgets('a video narrower than the box covers it rather than leaving bars',
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
              PostAttachments(references: [_video]),
              PostAttachments(references: [_video]),
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
              PostAttachments(references: [_video]),
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
      const other = PostReference(
        referenceId: 'r2',
        reference: 'https://example.invalid/other.mp4',
        mediaType: 'video/mp4',
      );
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
              PostAttachments(references: [_video]),
              PostAttachments(references: [other]),
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
          body: PostAttachments(references: [_video]),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(SharedVideoControllers.activeCount, 1);

      // Scrolled away, screen closed - whatever removed it, the decoder has to
      // go with it or a feed leaves one running per video ever shown.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
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
        home: Scaffold(body: PostAttachments(references: [_video])),
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
      await pumpVideo(tester, const Size(1280, 720));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(VideoProgressIndicator), findsOneWidget);
      // 10s duration from the fake, nothing played yet.
      expect(find.text('0:00 / 0:10'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('play flips the button, and the controls follow the CONTROLLER',
        (tester) async {
      await pumpVideo(tester, const Size(1280, 720));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('two widgets on one video agree on play state',
        (tester) async {
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
              PostAttachments(references: [_video]),
              PostAttachments(references: [_video]),
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
      await pumpVideo(tester, const Size(1280, 720));

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
        expect(player.right - bar.right, closeTo(12, 0.5), reason: '$videoSize');
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
      final mute = tester.getRect(find.byIcon(Icons.volume_up));

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
            child: PostAttachments(references: [_video]),
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
            child: PostAttachments(references: [_video]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:00 / 0:00'), findsNothing);
      expect(find.byType(VideoProgressIndicator), findsNothing);
    });

    testWidgets('playing one video pauses the other', (tester) async {
      // Two soundtracks at once is never what was asked for - and on Android
      // the two decoders fight over audio focus, so which one survives is a
      // race rather than a choice.
      const other = PostReference(
        referenceId: 'r2',
        reference: 'https://example.invalid/other.mp4',
        mediaType: 'video/mp4',
      );
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
              PostAttachments(references: [other]),
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

      // Starting the second stops the first: exactly one pause button, and one
      // play button left behind.
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
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
            child: PostAttachments(references: [_video]),
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
            child: PostAttachments(references: [_video]),
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
              child: VideoPlayerScreen(videoUrl: 'https://example.invalid/c.mp4'),
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
      await pumpVideo(tester, const Size(720, 1280));

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
          child: PostAttachments(references: [_video]),
        ),
      ),
    ));
    await tester.pump();

    // Still loading - otherwise this measures the resolved player and proves
    // nothing about the placeholder.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(VideoPlayerScreen)).width, screen.width);
  });
}
