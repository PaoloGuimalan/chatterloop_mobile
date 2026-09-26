import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
///
/// Every VIDEO gets its own player, as in a browser: any number can be open
/// and several can play at once (they mix their sound rather than pausing
/// each other). What keeps that reliable:
///  - the Android plugin is patched (patched/video_player_android) to fall
///    back to a software decoder when the hardware ones are all taken - the
///    failure behind "this video couldn't be played" whenever several videos
///    were open - and to start after 0.5s of buffer, from a disk cache;
///  - players nobody is showing are let go oldest-first once more than
///    [maxLive] exist, and a new player waits for that to FINISH before it
///    starts, so it never races a decoder that is still being released;
///  - a player that still fails to start frees every idle one and tries once
///    more on a fresh player, so a transient failure heals by itself.
class SharedVideoControllers {
  SharedVideoControllers._();

  static final Map<String, SharedVideoEntry> _entries = {};

  static String _keyFor(String source, bool isLocalFile) =>
      '${isLocalFile ? 'file' : 'net'}:$source';

  /// Live players (shown or idle) kept before idle ones are let go early.
  /// Shown players are never let go - this only trims the idle ones.
  @visibleForTesting
  static int maxLive = 6;

  /// Order of last use, for letting the stalest idle player go first.
  static int _useClock = 0;

  static VideoPlayerController _newController(String source, bool isLocalFile) {
    // Mixing, not taking the audio focus: with it, starting one video paused
    // every other one, and "play several at once" could never happen.
    final options = VideoPlayerOptions(mixWithOthers: true);
    return isLocalFile
        ? VideoPlayerController.file(File(source), videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(Uri.parse(source),
            videoPlayerOptions: options);
  }

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
    var entry = _entries[key];
    if (entry == null) {
      // Room first: idle players past the budget go, and the new one starts
      // only once they are really gone.
      final freeing = _trimIdle(roomFor: 1);
      entry = SharedVideoEntry(_newController(source, isLocalFile));
      _entries[key] = entry;
      // initialize() runs ONCE per source. A second acquirer awaits the same
      // future - already complete if the first one got there first, so it
      // renders on its first frame with no second round trip.
      entry.ready = _start(entry, source, isLocalFile, freeing);
    }
    entry.refs++;
    entry.lastUsed = ++_useClock;
    return entry;
  }

  static Future<void> _start(SharedVideoEntry entry, String source,
      bool isLocalFile, List<Future<void>> freeing) async {
    // Only waits when something is being freed - otherwise initialize() is
    // called right here, in the same turn as acquire().
    if (freeing.isNotEmpty) await _settle(freeing);
    try {
      await entry.controller.initialize();
    } catch (_) {
      // Most often a decoder or a request that was momentarily unavailable.
      // Give back everything idle, then one more try on a fresh player - a
      // failed controller can't be initialised again.
      await _settle(_trimIdle(roomFor: maxLive));
      final failed = entry.controller;
      entry.controller = _newController(source, isLocalFile);
      // NOT awaited: when creation itself threw, video_player's dispose()
      // waits on that creation forever.
      unawaited(failed.dispose());
      await entry.controller.initialize();
    }
  }

  /// Waits for [disposals] - but never more than a second, and never by
  /// failing: a platform that hangs or errors while releasing one video must
  /// not stop the next from starting.
  static Future<void> _settle(List<Future<void>> disposals) async {
    if (disposals.isEmpty) return;
    try {
      await Future.wait(disposals).timeout(const Duration(seconds: 1));
    } catch (_) {
      // Timed out or failed: start anyway, as before this waited at all.
    }
  }

  /// Lets idle players go, stalest first, until [roomFor] more fit within
  /// [maxLive] (roomFor: maxLive = every idle one). Returns the disposals,
  /// to be awaited before a new player starts.
  static List<Future<void>> _trimIdle({required int roomFor}) {
    final idle = _entries.entries.where((e) => e.value.refs <= 0).toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    final disposals = <Future<void>>[];
    for (final e in idle) {
      if (_entries.length + roomFor <= maxLive) break;
      _pendingDisposal.remove(e.key)?.cancel();
      _entries.remove(e.key);
      disposals.add(e.value.controller.dispose());
    }
    return disposals;
  }

  /// Lets every idle player go now - for a screen about to start its own
  /// player outside this pool (the Moment editor's preview).
  static Future<void> releaseIdle() => _settle(_trimIdle(roomFor: maxLive));

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

  /// How many sources are live. Test-only - a leak here is a decoder that
  /// never got turned off, which no assertion in a widget test would catch.
  @visibleForTesting
  static int get activeCount => _entries.length;

  /// Records how much of [entry]'s video [viewer] can see (null: it has
  /// stopped showing it), and plays or pauses to match. Post videos only -
  /// a player nobody reports on is left entirely to its own controls.
  ///
  /// Judged across EVERY place showing the video, because they share one
  /// player: a feed row covered by the post it opened reports hidden while
  /// the post screen over it reports watching, and the video must play on
  /// through that hand-over rather than pause and restart.
  ///  - someone starts watching (more than half in view): play, muted the
  ///    first time it plays by itself - it started unasked, so it starts
  ///    quiet; the viewer's unmute sticks after that;
  ///  - nobody can see it at all: pause;
  ///  - in between (only partly in view): leave it as it is.
  static void setVisibility(
      SharedVideoEntry entry, Object viewer, VideoVisibility? visibility) {
    if (visibility == null) {
      if (entry.viewers.remove(viewer) == null) return;
    } else {
      if (entry.viewers[viewer] == visibility) return;
      entry.viewers[viewer] = visibility;
    }
    if (entry.reconcileQueued) return;
    entry.reconcileQueued = true;
    // A microtask: a hand-over arrives as two reports (the row hidden, the
    // screen over it watching) and is judged once, as the pair.
    scheduleMicrotask(() => _reconcile(entry));
  }

  /// [setVisibility] for a viewer holding the controller rather than the
  /// entry - the full-screen page. Only where the video is already managed
  /// by visibility (a post's), so opening a chat video full screen doesn't
  /// start autoplaying it.
  static void setVisibilityOf(VideoPlayerController controller, Object viewer,
      VideoVisibility? visibility) {
    for (final entry in _entries.values) {
      if (!identical(entry.controller, controller)) continue;
      if (visibility != null && entry.viewers.isEmpty) return;
      setVisibility(entry, viewer, visibility);
      return;
    }
  }

  static Future<void> _reconcile(SharedVideoEntry entry) async {
    entry.reconcileQueued = false;
    try {
      await entry.ready;
    } catch (_) {
      return; // Failed to load - the error state renders itself.
    }
    // Let go of while it loaded.
    if (!_entries.containsValue(entry)) return;
    final controller = entry.controller;
    if (!controller.value.isInitialized) return;

    final seen = entry.viewers.values;
    final watching = seen.contains(VideoVisibility.watching);
    if (watching) {
      if (entry.watched) return;
      entry.watched = true;
      if (controller.value.isPlaying) return;
      // if (!entry.autoMuted) {
      //   entry.autoMuted = true;
      //   await controller.setVolume(0);
      // }
      await controller.play();
      return;
    }
    entry.watched = false;
    if (seen.every((v) => v == VideoVisibility.hidden) &&
        controller.value.isPlaying) {
      await controller.pause();
    }
  }
}

/// How much of a post's video one place showing it can see - see
/// [SharedVideoControllers.setVisibility].
enum VideoVisibility {
  /// None of it: off screen, under another screen, or on a hidden tab.
  hidden,

  /// Some of it, but not more than half.
  partly,

  /// More than half - enough to be watching it.
  watching,
}

/// One shared controller and the single [ready] future every viewer of it
/// awaits. Public only because [SharedVideoControllers.acquire] returns it.
///
/// Read [controller] AFTER [ready] completes: a first attempt that fails is
/// replaced by a fresh controller before [ready] settles.
class SharedVideoEntry {
  SharedVideoEntry(this.controller);

  VideoPlayerController controller;
  late Future<void> ready;
  int refs = 0;
  int lastUsed = 0;

  /// What each place showing it can see - post videos only. See
  /// [SharedVideoControllers.setVisibility].
  final Map<Object, VideoVisibility> viewers = {};

  /// Someone was watching at the last check, so play happens on the way IN
  /// to view, not on every report while it stays there - a video you paused
  /// while watching stays paused.
  bool watched = false;

  /// It has played by itself once, muted. The volume is the viewer's after.
  bool autoMuted = false;

  bool reconcileQueued = false;
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

  /// Letterbox the video inside the space offered and anchor the CONTROLS to
  /// that space's edges, rather than to the video's own box.
  ///
  /// For any viewer that owns a whole screen - the fullscreen page, and a
  /// carousel page in the attachment viewer. Nested in the video's box, the
  /// scrubber floats wherever the letterbox happens to end, which on a 16:9
  /// clip on a tall phone is the middle of a mostly-black screen.
  ///
  /// Off by default: a feed row or a chat bubble WANTS the controls on the
  /// frame, because there the frame is the only thing on screen that is the
  /// video.
  final bool anchorControlsToBounds;

  /// How much of this player is in view, for a post's video - which plays by
  /// itself once it is more than half in view and pauses once it is out of
  /// it (see [SharedVideoControllers.setVisibility]). [InlinePostVideo]
  /// measures it. Null leaves the player to its own controls.
  final VideoVisibility? visibility;

  /// Whether the controls offer the expand button at all.
  ///
  /// False inside [MediaViewerScreen], which IS the full-screen view - the
  /// button there pushed a second full-screen page on top of the first.
  final bool showFullscreenButton;

  /// What the expand button does, when the default is not what is wanted.
  ///
  /// Null keeps the built-in behaviour (push the bare full-screen player). A
  /// chat bubble overrides it so expanding a video lands in the same viewer a
  /// photo opens into, download action and all, rather than in a second
  /// player with no relationship to it.
  final VoidCallback? onFullscreen;

  /// Told the video's width-over-height once the player has loaded it - the
  /// true shape, for a parent that sized the box before it knew it
  /// ([InlinePostVideo] goes by the first frame until then).
  final ValueChanged<double>? onAspectRatio;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.isLocalFile = false,
    this.fillWidth = false,
    this.anchorControlsToBounds = false,
    this.visibility,
    this.showFullscreenButton = true,
    this.onFullscreen,
    this.onAspectRatio,
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
    _reportAspectWhenReady();
    _reportVisibility();
  }

  /// Tells the shared player how much of it this viewer can see.
  void _reportVisibility() {
    if (widget.visibility == null) return;
    SharedVideoControllers.setVisibility(_entry, this, widget.visibility);
  }

  /// Hands [VideoPlayerScreen.onAspectRatio] the loaded video's shape. Per
  /// entry, so a retry or a recycled widget reports its own video.
  void _reportAspectWhenReady() {
    if (widget.onAspectRatio == null) return;
    final entry = _entry;
    entry.ready.then((_) {
      if (!mounted || !identical(entry, _entry)) return;
      final value = _controller.value;
      if (value.isInitialized && value.aspectRatio > 0) {
        widget.onAspectRatio?.call(value.aspectRatio);
      }
    }, onError: (_) {
      // Failed to load - the error state renders itself, and the parent
      // keeps the shape it already had.
    });
  }

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl == widget.videoUrl &&
        oldWidget.isLocalFile == widget.isLocalFile) {
      if (oldWidget.visibility != widget.visibility) {
        SharedVideoControllers.setVisibility(_entry, this, widget.visibility);
      }
      return;
    }
    // Recycled onto a different video - let the old one go before taking the
    // new one, or the count for the old source never reaches zero.
    SharedVideoControllers.setVisibility(_entry, this, null);
    SharedVideoControllers.release(oldWidget.videoUrl,
        isLocalFile: oldWidget.isLocalFile);
    _entry = SharedVideoControllers.acquire(widget.videoUrl,
        isLocalFile: widget.isLocalFile);
    _reportAspectWhenReady();
    _reportVisibility();
  }

  @override
  void dispose() {
    SharedVideoControllers.setVisibility(_entry, this, null);
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
                SharedVideoControllers.setVisibility(_entry, this, null);
                setState(() {
                  _entry = SharedVideoControllers.acquire(widget.videoUrl,
                      isLocalFile: widget.isLocalFile);
                });
                _reportAspectWhenReady();
                _reportVisibility();
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
                  VideoControlsOverlay(
                    controller: _controller,
                    showFullscreenButton: widget.showFullscreenButton,
                    onFullscreen: widget.onFullscreen,
                  ),
                ],
              );

          final player = VideoPlayer(_controller);

          // Same arrangement as _FullscreenVideoPlayerPage: video letterboxed
          // in the middle, overlay a SIBLING filling the bounds, so the
          // scrubber lands on the bottom edge of the space rather than the
          // bottom edge of the frame.
          if (widget.anchorControlsToBounds) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(aspectRatio: aspectRatio, child: player),
                ),
                VideoControlsOverlay(
                  controller: _controller,
                  showFullscreenButton: widget.showFullscreenButton,
                  onFullscreen: widget.onFullscreen,
                ),
              ],
            );
          }

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

  /// Overrides what the expand button does - see
  /// [VideoPlayerScreen.onFullscreen], which is the only thing that sets it.
  final VoidCallback? onFullscreen;

  const VideoControlsOverlay({
    super.key,
    required this.controller,
    this.hideAfter = const Duration(seconds: 3),
    this.showFullscreenButton = true,
    this.onFullscreen,
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
    // Others keep playing - each video is its own player, as in a browser.
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
    final override = widget.onFullscreen;
    if (override != null) {
      override();
      return;
    }
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

class _FullscreenVideoPlayerPage extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullscreenVideoPlayerPage({required this.controller});

  @override
  State<_FullscreenVideoPlayerPage> createState() =>
      _FullscreenVideoPlayerPageState();
}

class _FullscreenVideoPlayerPageState
    extends State<_FullscreenVideoPlayerPage> {
  // Watching, for as long as it is open. It covers the post it was opened
  // from, which then reports its video hidden - and a post's video pauses
  // once nothing showing it can be seen.
  @override
  void initState() {
    super.initState();
    SharedVideoControllers.setVisibilityOf(
        widget.controller, this, VideoVisibility.watching);
  }

  @override
  void dispose() {
    SharedVideoControllers.setVisibilityOf(widget.controller, this, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
            // The video is letterboxed to its own aspect ratio...
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            // ...but the controls are a SIBLING of it, filling the screen, not
            // a child of the AspectRatio.
            //
            // Nested inside it they inherited the video's box, so on any clip
            // that doesn't match the screen's shape the scrubber floated in the
            // middle of the display with black above and below it - and on a
            // tall phone with a 16:9 video that is most of the screen. Out here
            // the overlay's own bottom-aligned scrubber lands on the bottom of
            // the SCREEN, which is where a fullscreen player's controls belong,
            // and the centre play button centres on the screen rather than on
            // the letterbox.
            VideoControlsOverlay(
              controller: controller,
              showFullscreenButton: false,
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
    _ratios.clear();
  }

  /// Width over height of each source's first frame, once read. Null value =
  /// no frame to read it from.
  static final Map<String, double?> _ratios = {};

  /// The shape [source] plays at, if it is already known - so a post scrolled
  /// back into view is built at its size straight away rather than growing
  /// into it a frame later.
  static double? knownAspectRatio(String source) => _ratios[source];

  /// The shape [source] plays at, read off its first frame.
  ///
  /// This is what lets a post size its video before anyone presses play: the
  /// platform hands the frame over upright, so its proportions are the
  /// video's, and getting them costs no player - only the frame the post
  /// shows anyway. Just the image's header is read, not its pixels.
  static Future<double?> aspectRatioOf(String source) async {
    if (_ratios.containsKey(source)) return _ratios[source];
    final data = await _frameFor(source);
    double? ratio;
    if (data != null) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 0 && descriptor.height > 0) {
          ratio = descriptor.width / descriptor.height;
        }
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {
        // Unreadable - the post keeps its default shape until a player
        // reports the real one.
      }
    }
    return _ratios[source] = ratio;
  }

  /// Seeds a source's shape, standing in for a frame the platform would
  /// extract - there is no platform to extract one under test.
  @visibleForTesting
  static void debugSetAspectRatio(String source, double? ratio) =>
      _ratios[source] = ratio;

  /// Where extracted frames are kept between app launches.
  ///
  /// The in-memory map above only survives while the process does, so every
  /// cold start re-extracted every frame in the feed - each one a native
  /// decode of a remote video, for an image that never changes. On disk they
  /// are read back as bytes and reused.
  ///
  /// The temp directory on purpose: these are derived data, cheap to rebuild,
  /// and the OS is welcome to reclaim them under pressure.
  static Directory? _cacheDir;

  static Future<Directory?> _ensureCacheDir() async {
    if (_cacheDir != null) return _cacheDir;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/video_thumbs');
      if (!await dir.exists()) await dir.create(recursive: true);
      return _cacheDir = dir;
    } catch (_) {
      // No disk cache available - fall back to memory only rather than
      // failing to show a frame at all.
      return null;
    }
  }

  /// A stable filename for a source url. Hashed because a url is not a legal
  /// filename and can be longer than the filesystem allows.
  static String _fileNameFor(String source) =>
      '${md5.convert(utf8.encode(source)).toString()}.jpg';

  static Future<Uint8List?> _frameFor(String source) {
    if (_cache.containsKey(source)) return Future.value(_cache[source]);
    return _inFlight.putIfAbsent(source, () async {
      try {
        final dir = await _ensureCacheDir();
        final file =
            dir == null ? null : File('${dir.path}/${_fileNameFor(source)}');

        // Already extracted on a previous run.
        if (file != null && await file.exists()) {
          final cached = await file.readAsBytes();
          if (cached.isNotEmpty) {
            _cache[source] = cached;
            return cached;
          }
        }

        final data = await VideoThumbnail.thumbnailData(
          video: source,
          imageFormat: ImageFormat.JPEG,
          // Tiles are small; a full-resolution frame would cost more to decode
          // than it could ever show.
          maxWidth: 480,
          quality: 60,
        );
        _cache[source] = data;
        if (data != null && file != null) {
          // Not awaited on the render path - the frame is already in memory,
          // and writing it is only for the NEXT launch.
          unawaited(file.writeAsBytes(data, flush: false).catchError((_) {
            return file;
          }));
        }
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

/// A post's video, as a player with its controls - no still to tap first.
/// It plays by itself (muted, the first time) once more than half of it is
/// in view, and pauses once none of it is: scrolled away, under another
/// screen, or on a tab you left.
///
/// The player is made the first time the video comes into view, not when the
/// row is built: a feed builds rows ahead of the screen, and a player each
/// would hold decoders for videos nobody has seen. Until it has loaded, the
/// first frame (an extracted bitmap, see [VideoFirstFrame]) stands in, so the
/// box shows the picture rather than an empty grey block. Once made, it stays
/// until the row goes (see SharedVideoControllers for the budget on them).
///
/// The box takes the VIDEO's shape: always the full width, as tall as the
/// video's proportions make it, up to [maxHeight]. A video taller than that is
/// cropped to cover the box rather than letterboxed - the full-screen player
/// shows it whole. The shape comes from the first frame, so it is right before
/// the player loads, and the player corrects it if the two ever disagree.
///
/// With [onTap] (a post being previewed - the share composer, moderation) it
/// is a still with a play badge instead, and the tap is the caller's.
class InlinePostVideo extends StatefulWidget {
  final String source;
  final double maxHeight;

  /// Makes it a still whose tap is this - the share composer and moderation
  /// open the full-screen viewer. Null: a player that plays by itself.
  final VoidCallback? onTap;

  const InlinePostVideo({
    super.key,
    required this.source,
    required this.maxHeight,
    this.onTap,
  });

  @override
  State<InlinePostVideo> createState() => _InlinePostVideoState();
}

class _InlinePostVideoState extends State<InlinePostVideo> {
  /// Until the frame says otherwise - the common shape of a phone video shot
  /// sideways, and webapp's FittedPostMedia default.
  static const double _defaultRatio = 16 / 9;

  /// The player exists - from the first time any of the video was in view.
  bool _live = false;

  VideoVisibility _visibility = VideoVisibility.hidden;

  /// One per box: two posts can show the same video.
  final Key _detectorKey = UniqueKey();

  /// Width over height; null until known.
  double? _ratio;

  /// The player has reported the real shape, which the frame must not then
  /// overwrite if it lands late.
  bool _ratioFromPlayer = false;

  @override
  void initState() {
    super.initState();
    _resolveRatio();
  }

  @override
  void didUpdateWidget(covariant InlinePostVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _ratioFromPlayer = false;
      _resolveRatio();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // The detector's last report comes as the box is unmounted.
    if (!mounted) return;
    final fraction = info.visibleFraction;
    final visibility = fraction <= 0
        ? VideoVisibility.hidden
        : fraction > 0.5
            ? VideoVisibility.watching
            : VideoVisibility.partly;
    final live = _live || fraction > 0;
    if (visibility == _visibility && live == _live) return;
    setState(() {
      _visibility = visibility;
      _live = live;
    });
  }

  void _resolveRatio() {
    final source = widget.source;
    _ratio = VideoFirstFrame.knownAspectRatio(source);
    if (_ratio != null) return;
    VideoFirstFrame.aspectRatioOf(source).then((ratio) {
      if (!mounted || ratio == null || _ratioFromPlayer) return;
      if (source != widget.source) return;
      setState(() => _ratio = ratio);
    });
  }

  void _onPlayerRatio(double ratio) {
    _ratioFromPlayer = true;
    if (_ratio != null && (ratio - _ratio!).abs() < 0.01) return;
    setState(() => _ratio = ratio);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final onTap = widget.onTap;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final height =
          math.min(width / (_ratio ?? _defaultRatio), widget.maxHeight);

      final box = SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: p.surface2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover, like the player: the frame fills the box whatever it
              // was sized from. Under the player it shows while that loads.
              VideoFirstFrame(
                  source: widget.source, showPlayBadge: onTap != null),
              if (onTap != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                )
              else if (_live)
                // Its loading spinner and, once ready, the video and its
                // controls fill this same box - fillWidth covers it.
                VideoPlayerScreen(
                  videoUrl: widget.source,
                  fillWidth: true,
                  visibility: _visibility,
                  onAspectRatio: _onPlayerRatio,
                ),
            ],
          ),
        ),
      );
      if (onTap != null) return box;
      return VisibilityDetector(
        key: _detectorKey,
        onVisibilityChanged: _onVisibilityChanged,
        child: box,
      );
    });
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
