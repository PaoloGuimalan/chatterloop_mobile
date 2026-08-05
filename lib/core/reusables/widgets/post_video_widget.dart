import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// One [VideoPlayerController] per source, shared by every widget showing it
/// and disposed when the last one goes away.
///
/// This exists because two controllers on the SAME url is a broken state: a
/// feed row plays a video, you open that post, the screen builds its own
/// player, and the screen's draws nothing but its background - while the same
/// post opened from search, with nothing playing behind it, works. One
/// controller means there is nothing to collide with.
///
/// It also makes the handover seamless in the direction users actually go: a
/// video playing in the feed is still playing, at the same position, on the
/// screen you just opened - because it is literally the same player.
///
/// Ref-counted rather than a plain cache: the row usually outlives the push
/// (it sits behind the route) but not always - it can be scrolled out and
/// disposed while the screen holds the same video. Whoever leaves last turns
/// the decoder off.
class SharedVideoControllers {
  SharedVideoControllers._();

  static final Map<String, SharedVideoEntry> _entries = {};

  static String _keyFor(String source, bool isLocalFile) =>
      '${isLocalFile ? 'file' : 'net'}:$source';

  /// Disposal is DEFERRED, not immediate - see [release].
  static final Map<String, Timer> _pendingDisposal = {};

  /// How long a controller sticks around after its last viewer leaves.
  ///
  /// Long enough to cover swiping between a post's videos and back, short
  /// enough that a scrolled-past video isn't holding a decoder for the session.
  ///
  /// ZERO means dispose synchronously, and that is the DEFAULT UNDER TEST.
  ///
  /// A widget test fails on any timer still pending when it ends, and this one
  /// is created during teardown as the tree unmounts - so every test that ever
  /// renders a video, anywhere, would fail on a timer it never asked for.
  /// Defaulting it here rather than in each test file means a test that shows a
  /// post with a video doesn't have to know this class exists.
  ///
  /// Settable so the tests that are ABOUT the grace period can opt into it.
  @visibleForTesting
  static Duration idleGrace = Platform.environment.containsKey('FLUTTER_TEST')
      ? Duration.zero
      : const Duration(seconds: 8);

  static SharedVideoEntry acquire(String source, {required bool isLocalFile}) {
    final key = _keyFor(source, isLocalFile);
    // Coming back to something that was on its way out: keep it.
    _pendingDisposal.remove(key)?.cancel();
    final entry = _entries.putIfAbsent(key, () {
      final controller = isLocalFile
          ? VideoPlayerController.file(File(source))
          : VideoPlayerController.networkUrl(Uri.parse(source));
      // initialize() is called ONCE per source. A second acquirer awaits the
      // same future - already complete if the first one got there first, so it
      // renders on its first frame with no second round trip.
      return SharedVideoEntry(controller, controller.initialize());
    });
    entry.refs++;
    return entry;
  }

  static void release(String source, {required bool isLocalFile}) {
    final key = _keyFor(source, isLocalFile);
    final entry = _entries[key];
    if (entry == null) return;
    entry.refs--;
    if (entry.refs > 0) return;

    // Pause now, dispose LATER. Tearing the decoder down the instant the last
    // viewer left made switching between a post's videos fail: dispose() is
    // asynchronous on Android, so opening the next video created a second
    // decoder while the first was still releasing, and the new one came back
    // uninitialised - "this video couldn't be played". Holding the entry for a
    // grace period also means swiping back to a video you just left reuses the
    // same controller, at the same position, instead of reloading it.
    entry.controller.pause();
    _pendingDisposal[key]?.cancel();
    if (idleGrace == Duration.zero) {
      _pendingDisposal.remove(key);
      _entries.remove(key);
      entry.controller.dispose();
      return;
    }
    _pendingDisposal[key] = Timer(idleGrace, () {
      _pendingDisposal.remove(key);
      // Re-check: it may have been picked up again while the timer ran.
      final current = _entries[key];
      if (current == null || current.refs > 0) return;
      _entries.remove(key);
      current.controller.dispose();
    });
  }

  /// Drop a source entirely, so the next [acquire] builds a fresh controller.
  ///
  /// For the retry path: an initialize() that failed leaves an entry whose
  /// future is permanently rejected, and every later viewer would inherit that
  /// failure however transient it was.
  static void evict(String source, {required bool isLocalFile}) {
    final key = _keyFor(source, isLocalFile);
    _pendingDisposal.remove(key)?.cancel();
    final entry = _entries.remove(key);
    entry?.controller.dispose();
  }

  /// Dispose everything pending immediately. Test-only - the grace period
  /// would otherwise leave counts non-deterministic between tests.
  @visibleForTesting
  static void disposeIdleNow() {
    for (final timer in _pendingDisposal.values) {
      timer.cancel();
    }
    _pendingDisposal.clear();
    _entries.removeWhere((key, entry) {
      if (entry.refs > 0) return false;
      entry.controller.dispose();
      return true;
    });
  }

  /// Pause every other video before [keep] starts.
  ///
  /// One at a time, app-wide. Two videos playing together is never what was
  /// asked for - you tap a second one while the first is still going and get
  /// both soundtracks at once, with no way to reach the one that scrolled off.
  /// Android's audio focus makes it worse: the two decoders fight over it, and
  /// which one survives is a race.
  ///
  /// Pausing rather than stopping, so the one you left keeps its position for
  /// when you come back to it.
  static void pauseOthers(VideoPlayerController keep) {
    for (final entry in _entries.values) {
      if (identical(entry.controller, keep)) continue;
      if (entry.controller.value.isPlaying) entry.controller.pause();
    }
  }

  /// How many sources are live. Test-only - a leak here is a decoder that
  /// never got turned off, which no assertion in a widget test would catch.
  @visibleForTesting
  static int get activeCount => _entries.length;
}

/// One shared controller and the single [ready] future every viewer of it
/// awaits. Public only because [SharedVideoControllers.acquire] returns it.
class SharedVideoEntry {
  SharedVideoEntry(this.controller, this.ready);

  final VideoPlayerController controller;
  final Future<void> ready;
  int refs = 0;
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  /// True for a pending (not-yet-uploaded) video, whose "url" is actually
  /// a local file path - the file picker/camera never produces a network
  /// URL, only a path on-device.
  final bool isLocalFile;

  /// Span the full width the parent offers, instead of sizing purely to the
  /// video's own aspect ratio.
  ///
  /// Off by default because the AspectRatio-only behaviour is what a chat
  /// bubble and a diary attachment want - they size to their content. A post's
  /// media is the opposite: it's a full-bleed block in a card, and a video that
  /// sizes itself leaves ragged margins next to the image beside it.
  ///
  /// Without this, a TALL video is the visible failure: AspectRatio takes the
  /// offered width, works out a height from it, finds that height over the
  /// parent's cap, and then shrinks the WIDTH back to keep its shape - so the
  /// video ends up floating in the middle of the card. With it, the box always
  /// spans the width and a video too tall for the cap is cropped to fill it.
  final bool fillWidth;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.isLocalFile = false,
    this.fillWidth = false,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late SharedVideoEntry _entry;

  VideoPlayerController get _controller => _entry.controller;

  @override
  void initState() {
    super.initState();
    _entry = SharedVideoControllers.acquire(widget.videoUrl,
        isLocalFile: widget.isLocalFile);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl == widget.videoUrl &&
        oldWidget.isLocalFile == widget.isLocalFile) {
      return;
    }
    // Recycled onto a different video - let the old one go before taking the
    // new one, or the count for the old source never reaches zero.
    SharedVideoControllers.release(oldWidget.videoUrl,
        isLocalFile: oldWidget.isLocalFile);
    _entry = SharedVideoControllers.acquire(widget.videoUrl,
        isLocalFile: widget.isLocalFile);
  }

  @override
  void dispose() {
    SharedVideoControllers.release(widget.videoUrl,
        isLocalFile: widget.isLocalFile);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _entry.ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // "done" also covers FAILED. initialize() completing with an error
          // used to fall straight through to the player, which then rendered an
          // uninitialized controller: aspect ratio 1.0, duration 0:00 and a
          // scrubber that went nowhere. That is what "some videos always load
          // at zero duration" was - not a timing bug, a dead source drawn as if
          // it were fine.
          if (snapshot.hasError || !_controller.value.isInitialized) {
            return _Unavailable(
              message: _controller.value.errorDescription == null
                  ? "Video unavailable"
                  : "This video couldn't be played",
              // A failure here is often transient - a decoder that was still
              // being released, or a request that timed out. The entry caches a
              // permanently-rejected future, so retrying has to throw the whole
              // controller away and build a new one.
              onRetry: () {
                SharedVideoControllers.evict(widget.videoUrl,
                    isLocalFile: widget.isLocalFile);
                setState(() {
                  _entry = SharedVideoControllers.acquire(widget.videoUrl,
                      isLocalFile: widget.isLocalFile);
                });
              },
            );
          }

          // Use AspectRatio so the widget takes the exact shape of the video file
          final aspectRatio = _controller.value.aspectRatio;

          // Controls are layered on the BOX, never inside the FittedBox below -
          // that box scales its child to cover, which would blow the buttons up
          // (or shrink them) along with the frame.
          Widget withControls(Widget videoSurface) => Stack(
                fit: StackFit.expand,
                children: [
                  videoSurface,
                  VideoControlsOverlay(controller: _controller),
                ],
              );

          final player = VideoPlayer(_controller);

          if (!widget.fillWidth) {
            return AspectRatio(
              aspectRatio: aspectRatio,
              child: withControls(player),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              // Nothing to fill - an unbounded width means the parent is asking
              // this to size itself (a Row without Expanded, say), so fall back
              // rather than throw on an infinite SizedBox.
              if (!constraints.hasBoundedWidth) {
                return AspectRatio(
                  aspectRatio: aspectRatio,
                  child: withControls(player),
                );
              }

              final width = constraints.maxWidth;
              var height = width / aspectRatio;
              // Respect the caller's height cap (the post card's
              // _kMaxInlineHeightFactor) - but by SHORTENING the box, never by
              // narrowing it.
              if (constraints.hasBoundedHeight &&
                  height > constraints.maxHeight) {
                height = constraints.maxHeight;
              }

              return SizedBox(
                width: width,
                height: height,
                // COVER, not contain: the frame scales until it fills the box
                // on both axes and the overflow is clipped. When the height
                // wasn't capped the box already matches the video's shape, so
                // nothing is cropped; it only bites on a video too tall for the
                // cap, where the alternative is bars down both sides.
                //
                // The SizedBox inside carries the video's PROPORTIONS, not its
                // pixel size - FittedBox only reads the ratio, and a controller
                // reporting a zero size (a failed load) would otherwise give it
                // a zero-sized child and render nothing at all.
                child: withControls(
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: aspectRatio * 1000,
                        height: 1000,
                        child: player,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        } else {
          // Keep a minimum height placeholder while loading so it doesn't
          // collapse to 0. Deliberately a plain SizedBox: this branch runs for
          // EVERY caller, including chat bubbles, and a LayoutBuilder here
          // throws outright under an IntrinsicWidth/IntrinsicHeight ancestor
          // ("does not support returning intrinsic dimensions"). The width is
          // left to the parent - the post path wraps this in a full-width
          // Container, so it fills either way.
          return const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
      },
    );
  }
}

/// Play/pause, a scrubber, elapsed time and mute, layered over a video.
///
/// Driven by the CONTROLLER's own ValueNotifier rather than setState, because
/// the controller is shared: pausing on the post screen has to move the button
/// in the feed row behind it too, and a widget rebuilding only its own state
/// would leave two players disagreeing about whether they're playing.
///
/// Auto-hides while playing so the frame isn't permanently covered, and stays
/// up whenever the video is paused - a paused video with no visible play button
/// reads as broken rather than paused.
class VideoControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  /// How long the controls linger before fading out.
  final Duration hideAfter;

  /// Shows a fullscreen button next to mute.
  final bool showFullscreenButton;

  const VideoControlsOverlay({
    super.key,
    required this.controller,
    this.hideAfter = const Duration(seconds: 3),
    this.showFullscreenButton = true,
  });

  @override
  State<VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<VideoControlsOverlay> {
  Timer? _hideTimer;
  bool _visible = true;

  // â”€â”€ Is it actually stalled? â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // isBuffering alone is not usable. A seek sets it, and the plugin clears it
  // only when playback "resumes" - which on some sources never fires, leaving
  // the flag stuck TRUE for the rest of the video. Gating the spinner on
  // isPlaying made that worse rather than better: the spinner then appeared
  // exactly while the video was playing fine.
  //
  // So the flag is treated as a hint and corroborated against the thing the
  // viewer can actually see: whether the POSITION is moving. Frames flowing
  // means it isn't stalled, whatever the flag says. The controller polls
  // position roughly twice a second while playing, so this keeps being
  // re-evaluated during a genuine stall too.
  Duration _lastPosition = Duration.zero;
  Timer? _stallTimer;
  bool _stalled = false;

  /// How long the position may sit still, while buffering is claimed, before
  /// it counts as a stall. Comfortably over the controller's ~500ms position
  /// poll so ordinary jitter never trips it.
  static const Duration _stallAfter = Duration(milliseconds: 900);

  /// A TIMER, not a count of rebuilds, because a stall is the absence of
  /// updates: VideoPlayerValue implements ==, so a position that doesn't move
  /// notifies nobody. Counting rebuilds can never see the very thing it's
  /// looking for.
  void _onControllerValue() {
    final value = widget.controller.value;
    final advanced = value.position != _lastPosition;
    if (advanced) _lastPosition = value.position;

    if (!value.isBuffering || !value.isPlaying) {
      _clearStall();
      return;
    }

    // A WATCHDOG, armed the whole time buffering is claimed and reset by every
    // advance. Arming it only on a frozen update would never fire: the last
    // thing that happens before a stall is a position update, and after that
    // there is nothing left to listen for.
    //
    // So with a stuck flag but healthy playback, the ~500ms position polls keep
    // resetting a 900ms timer and it never fires. When playback genuinely
    // stops, the resets stop with it.
    if (advanced) {
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_stalled) setState(() => _stalled = false);
    }
    _stallTimer ??= Timer(_stallAfter, () {
      if (mounted) setState(() => _stalled = true);
    });
  }

  void _clearStall() {
    _stallTimer?.cancel();
    _stallTimer = null;
    if (_stalled && mounted) setState(() => _stalled = false);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerValue);
  }

  @override
  void didUpdateWidget(covariant VideoControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onControllerValue);
    widget.controller.addListener(_onControllerValue);
    _clearStall();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerValue);
    _stallTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Only a PLAYING video hides its controls.
    if (!widget.controller.value.isPlaying) return;
    _hideTimer = Timer(widget.hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _onSurfaceTap() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _togglePlayback() {
    final value = widget.controller.value;
    if (value.isPlaying) {
      widget.controller.pause();
      _hideTimer?.cancel();
      setState(() => _visible = true);
      return;
    }
    // Rewind first when replaying a finished video: play() on a controller
    // sitting at the end does nothing at all.
    if (value.duration > Duration.zero && value.position >= value.duration) {
      widget.controller.seekTo(Duration.zero);
    }
    // Nothing else keeps playing underneath this one.
    SharedVideoControllers.pauseOthers(widget.controller);
    widget.controller.play();
    _scheduleHide();
  }

  void _toggleMute() {
    final muted = widget.controller.value.volume == 0;
    widget.controller.setVolume(muted ? 1 : 0);
    _scheduleHide();
  }

  void _openFullscreen() {
    _hideTimer?.cancel();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _FullscreenVideoPlayerPage(controller: widget.controller),
      ),
    );
  }

  static String _clock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, "0")}:$seconds";
    }
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final playing = value.isPlaying;
        final hasDuration = value.duration > Duration.zero;
        final finished = hasDuration && value.position >= value.duration;
        // Tracked by the controller listener, not derived here - see
        // _onControllerValue.
        final stalled = _stalled;
        // Paused always shows; playing follows the auto-hide timer.
        final showing = _visible || !playing;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Under the buttons, so it can't swallow their taps.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSurfaceTap,
              child: const SizedBox.expand(),
            ),
            // Stalled, not "buffering" - see _isStalled.
            if (stalled)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            IgnorePointer(
              ignoring: !showing,
              child: AnimatedOpacity(
                opacity: showing ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: _RoundButton(
                        icon: playing
                            ? Icons.pause
                            : finished
                                ? Icons.replay
                                : Icons.play_arrow,
                        onTap: _togglePlayback,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        // No left/right inset: the scrubber inside runs edge to
                        // edge, and the clock/mute row below it carries its own.
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 2),
                        decoration: const BoxDecoration(
                          // Scrim - white controls on a bright frame are
                          // otherwise unreadable.
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x99000000)],
                          ),
                        ),
                        // Scrubber on its OWN row so it spans the full width of
                        // the video. Sharing a row with the clock and the mute
                        // button left it about a third of the width - and the
                        // seek bar is the one control whose usefulness scales
                        // directly with how long it is.
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // A source with no duration (a live stream, or one
                            // the platform couldn't measure) has nothing to
                            // scrub along - the bar would sit at zero and
                            // seeking it would do nothing.
                            if (hasDuration)
                              VideoProgressIndicator(
                                widget.controller,
                                // Draggable: a video you can't seek in is a
                                // silent gif with a play button.
                                allowScrubbing: true,
                                // Inset to match the row below it. Running the
                                // bar right into the corners looked like a
                                // progress meter welded to the frame rather
                                // than a control sitting on it.
                                padding:
                                    const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                colors: VideoProgressColors(
                                  playedColor: p.brand,
                                  bufferedColor: Colors.white24,
                                  backgroundColor: Colors.white30,
                                ),
                              ),
                            Padding(
                              // The mute button carries 6 of its own, so 6 here
                              // lands its glyph on the same 12px inset as the
                              // clock and the scrubber above.
                              padding:
                                  const EdgeInsets.only(left: 12, right: 6),
                              child: Row(
                                // spaceBetween, NOT a Spacer: Flexible is loose,
                                // so it renders narrower than the half-share it
                                // claims and the leftover falls AFTER the mute
                                // button - which is what parked the speaker
                                // short of the right edge.
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Flexible: this bar also renders over a chat
                                  // bubble's thumbnail, which can be ~120px wide.
                                  Flexible(
                                    child: Text(
                                      // No total when there isn't one to show -
                                      // "0:12 / 0:00" reads as a broken player.
                                      hasDuration
                                          ? "${_clock(value.position)} / ${_clock(value.duration)}"
                                          : _clock(value.position),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.fade,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: CLType.meta,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.showFullscreenButton)
                                        InkWell(
                                          onTap: _openFullscreen,
                                          borderRadius: BorderRadius.circular(
                                              CLRadii.pill),
                                          child: const Padding(
                                            padding: EdgeInsets.all(7),
                                            child: Icon(
                                              Icons.fullscreen,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      InkWell(
                                        onTap: _toggleMute,
                                        borderRadius:
                                            BorderRadius.circular(CLRadii.pill),
                                        child: Padding(
                                          padding: const EdgeInsets.all(7),
                                          child: Icon(
                                            value.volume == 0
                                                ? Icons.volume_off
                                                : Icons.volume_up,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FullscreenVideoPlayerPage extends StatelessWidget {
  final VideoPlayerController controller;

  const _FullscreenVideoPlayerPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    final aspectRatio =
        controller.value.isInitialized && controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : (16 / 9);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(controller),
                    VideoControlsOverlay(
                      controller: controller,
                      showFullscreenButton: false,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, size: 22, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a video cannot be played at all.
///
/// Sized like the loading placeholder so a card doesn't jump when the failure
/// lands, and left to the parent for width - the post path wraps it in a
/// full-width Container.
class _Unavailable extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _Unavailable({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 26, color: p.text3),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: CLType.caption, color: p.text3),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  "Try again",
                  style: TextStyle(fontSize: CLType.label, color: p.brand),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A video's FIRST FRAME, as a still image.
///
/// Used wherever a video is advertised rather than watched: the multi-media
/// grid, the share preview, the composer's picked files. Those used to be a
/// flat surface colour with a play glyph, which told you nothing about which
/// video you were looking at - a post with two videos was two identical grey
/// tiles.
///
/// EXTRACTS A BITMAP rather than holding a player. The first version of this
/// initialised a VideoPlayerController per tile and rendered its unplayed
/// frame, which does show the real image - but every controller is a
/// platform-level decoder, and a post with several videos plus the player
/// exhausted them: initialise started failing and the app showed "this video
/// couldn't be played" in place of videos that were fine. video_thumbnail asks
/// the platform for ONE frame and releases everything, so a grid of previews
/// costs no decoders at all.
///
/// Results are cached per source for the process: extraction is not free, and
/// the same tile is rebuilt constantly by a scrolling feed. Failures are cached
/// too - as null - so a source that cannot produce a frame is not retried on
/// every rebuild.
class VideoFirstFrame extends StatefulWidget {
  final String source;
  final bool isLocalFile;

  /// Drawn over the frame, so a still is never mistaken for a photo.
  final bool showPlayBadge;

  const VideoFirstFrame({
    super.key,
    required this.source,
    this.isLocalFile = false,
    this.showPlayBadge = true,
  });

  /// Frames already extracted, keyed by source. Null value = tried and failed.
  static final Map<String, Uint8List?> _cache = {};

  /// In-flight extractions, so four tiles of the same clip ask once.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  static Future<Uint8List?> _frameFor(String source) {
    if (_cache.containsKey(source)) return Future.value(_cache[source]);
    return _inFlight.putIfAbsent(source, () async {
      try {
        final data = await VideoThumbnail.thumbnailData(
          video: source,
          imageFormat: ImageFormat.JPEG,
          // Tiles are small; a full-resolution frame would cost more to decode
          // than it could ever show.
          maxWidth: 480,
          quality: 60,
        );
        _cache[source] = data;
        return data;
      } catch (_) {
        // A frame is a nicety - a source that won't give one still renders as
        // a video tile, it just doesn't show what's in it.
        _cache[source] = null;
        return null;
      } finally {
        _inFlight.remove(source);
      }
    });
  }

  @override
  State<VideoFirstFrame> createState() => _VideoFirstFrameState();
}

class _VideoFirstFrameState extends State<VideoFirstFrame> {
  late Future<Uint8List?> _frame;

  @override
  void initState() {
    super.initState();
    _frame = VideoFirstFrame._frameFor(widget.source);
  }

  @override
  void didUpdateWidget(covariant VideoFirstFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _frame = VideoFirstFrame._frameFor(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: p.surface2),
        FutureBuilder<Uint8List?>(
          future: _frame,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) return const SizedBox.shrink();
            return Image.memory(
              data,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            );
          },
        ),
        if (widget.showPlayBadge)
          Center(
            child: Icon(
              Icons.play_circle_fill,
              size: 40,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 30, color: Colors.white),
        ),
      ),
    );
  }
}
