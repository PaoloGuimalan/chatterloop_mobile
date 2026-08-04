import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

  static SharedVideoEntry acquire(String source, {required bool isLocalFile}) {
    final key = _keyFor(source, isLocalFile);
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
    _entries.remove(key);
    // Pause first: dispose() on a playing controller has been known to leave
    // audio running for a beat on Android.
    entry.controller.pause().whenComplete(entry.controller.dispose);
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

  void _togglePlayback() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _entry.ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // Use AspectRatio so the widget takes the exact shape of the video file
          final aspectRatio = _controller.value.aspectRatio;
          final player = GestureDetector(
            onTap: _togglePlayback,
            child: VideoPlayer(_controller),
          );

          if (!widget.fillWidth) {
            return AspectRatio(aspectRatio: aspectRatio, child: player);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              // Nothing to fill - an unbounded width means the parent is asking
              // this to size itself (a Row without Expanded, say), so fall back
              // rather than throw on an infinite SizedBox.
              if (!constraints.hasBoundedWidth) {
                return AspectRatio(aspectRatio: aspectRatio, child: player);
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
                child: ClipRect(
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
