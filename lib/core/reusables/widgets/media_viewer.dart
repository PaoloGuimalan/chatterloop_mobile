// The full-screen media viewer: one page per attachment, swipe between them,
// pinch or double-tap to zoom a photo, videos play in place.
//
// ONE viewer for the whole app rather than one per surface. It started as
// post_attachments.dart's PostGalleryScreen, which only ever spoke
// PostReference - so a conversation, whose attachment is a bare url plus a
// messageType, had no way to open it and photos in chat had no full-screen
// view at all. [MediaViewerItem] is that shared shape; posts map their
// references onto it (see openPostGallery) and messages build one directly.
//
// The DOWNLOAD action lives here rather than at each call site because this
// is where a file is being looked at properly - and because the viewer is the
// one place that already knows which of several attachments is on screen.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:flutter/material.dart';

/// One thing the viewer can show.
///
/// [source] is the RAW content string, not a resolved URL: the downloader
/// needs the original to recover a legacy "url%%%filename" name, and
/// [chatMediaUrl] normalises it for playback and fetching. For a post
/// reference the two are the same string.
class MediaViewerItem {
  final String source;
  final bool isVideo;

  /// The server's `messageType` / media type when the caller has one - it
  /// beats guessing the content type from the file extension.
  final String? mimeType;

  const MediaViewerItem({
    required this.source,
    required this.isVideo,
    this.mimeType,
  });

  String get url => chatMediaUrl(source);
}

/// Opens the viewer at [initialIndex].
void openMediaViewer(
  BuildContext context,
  List<MediaViewerItem> items,
  int initialIndex, {
  bool canDownload = true,
}) {
  if (items.isEmpty) return;
  Navigator.of(context).push(
    // Opaque on purpose: this covers the screen, and a see-through route over
    // a page triggers the router's parallax (see CLPageRoute.canTransitionTo).
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MediaViewerScreen(
        items: items,
        initialIndex: initialIndex,
        canDownload: canDownload,
      ),
    ),
  );
}

class MediaViewerScreen extends StatefulWidget {
  final List<MediaViewerItem> items;
  final int initialIndex;

  /// Whether the app bar offers a download. Posts pass false - their media is
  /// a feed surface with no save affordance anywhere else, and adding one
  /// there was not part of what this viewer was built for.
  final bool canDownload;

  const MediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.canDownload = true,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MediaViewerItem get _current => widget.items[_index];

  @override
  Widget build(BuildContext context) {
    // Black regardless of theme - it is a media viewer, and any surface colour
    // here would tint the photo it is supposed to be showing.
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: widget.items.length > 1
            ? Text(
                "${_index + 1} of ${widget.items.length}",
                style: const TextStyle(
                    color: Colors.white, fontSize: CLType.title),
              )
            : null,
        actions: [
          if (widget.canDownload)
            // Rebuilt from the downloader's own notifier rather than local
            // state: the download outlives this route, so a viewer reopened on
            // the same attachment has to pick the spinner back up rather than
            // offer to start a second one.
            ValueListenableBuilder<Map<String, double>>(
              valueListenable: MediaDownloader.instance.progress,
              builder: (context, running, _) {
                final value = running[_current.url];
                if (value == null) {
                  return IconButton(
                    tooltip: "Download",
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => MediaDownloader.instance.download(
                      _current.source,
                      mimeType: _current.mimeType,
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                        // 0 means the response had no Content-Length, so there
                        // is no percentage to draw - spin instead of sitting
                        // at an empty ring that looks stuck.
                        value: value > 0 ? value : null,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          if (item.isVideo) {
            // No Center wrapper: the player fills the page and anchors its own
            // controls to the page's bottom edge. Centring it would hand it
            // only the video's box back, which is the thing being fixed.
            //
            // SafeArea on the BOTTOM only: this Scaffold draws edge to edge, so
            // "the bottom of the page" is behind the system navigation bar -
            // the controls cleared the video's box and then landed under the
            // nav buttons instead. Top stays unsafe because the transparent
            // AppBar is meant to float over the media.
            return SafeArea(
              top: false,
              child: VideoPlayerScreen(
                videoUrl: item.url,
                anchorControlsToBounds: true,
                // This page already IS the full-screen view. The button used
                // to push a second full-screen player on top of it, which had
                // its own close affordance and none of this one's actions.
                showFullscreenButton: false,
              ),
            );
          }
          return _ZoomableImage(url: item.url);
        },
      ),
    );
  }
}

/// A photo that pinches AND double-taps to zoom.
///
/// InteractiveViewer gives the pinch for free but has no tap handling at all,
/// which is the gesture most people reach for first on a phone. The transform
/// is animated rather than snapped so the two gestures feel like the same
/// control.
class _ZoomableImage extends StatefulWidget {
  final String url;

  const _ZoomableImage({required this.url});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  static const double _zoomedScale = 2.5;

  final TransformationController _transform = TransformationController();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<Matrix4>? _zoom;

  /// Where the last double-tap landed. A field rather than a local in build():
  /// onDoubleTap carries no details of its own, so the position has to survive
  /// from onDoubleTapDown - across any rebuild that happens in between.
  TapDownDetails? _lastTapDown;

  @override
  void initState() {
    super.initState();
    _animation.addListener(() {
      final value = _zoom?.value;
      if (value != null) _transform.value = value;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final zoomedIn = _transform.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomedIn) {
      target = Matrix4.identity();
    } else {
      // Zoom around the point that was tapped: scale about the origin, then
      // translate so the tapped point stays under the finger. The typed
      // translateByDouble/scaleByDouble rather than translate/scale - the
      // dynamic-argument pair is deprecated in vector_math 2.2.0.
      final focal = _lastTapDown?.localPosition ?? Offset.zero;
      target = Matrix4.identity()
        ..translateByDouble(-focal.dx * (_zoomedScale - 1),
            -focal.dy * (_zoomedScale - 1), 0, 1)
        ..scaleByDouble(_zoomedScale, _zoomedScale, _zoomedScale, 1);
    }
    _zoom = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _animation, curve: Curves.easeOut));
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _lastTapDown = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: CLNetworkImage(
            src: widget.url,
            fit: BoxFit.contain,
            width: double.infinity,
          ),
        ),
      ),
    );
  }
}
