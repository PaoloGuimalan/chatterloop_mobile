// A post's media, and the full-screen viewer it opens into.
//
// Layout is chosen by COUNT, which is the thing that actually decides what
// reads well in a feed:
//
//   1        one image, full width, at its own aspect ratio (capped) - a lone
//            photo in a fixed-height box is the classic letterboxing mistake
//   2        two equal halves
//   3        one large left, two stacked right
//   4+       2x2 grid, with a "+N" scrim on the last tile
//
// Deliberately a GRID rather than an inline carousel: a feed is already a
// vertical scroll, and a horizontally-swiping child inside it fights the
// parent gesture (and hides everything after the first slide, so you can't
// tell a 2-image post from a 9-image one at a glance). The carousel belongs
// in the full-screen viewer, where swiping is the only gesture - that's what
// [PostGalleryScreen] is. Same reasoning webapp's grid-then-lightbox uses.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

/// Tallest an inline attachment block may get, as a fraction of screen height
/// - a portrait photo would otherwise fill the whole viewport and push the
/// caption and actions off screen.
const double _kMaxInlineHeightFactor = 0.55;

/// Media only. A "shared_post" reference is a pointer to another post, not a
/// file, and must never reach an image widget.
List<PostReference> displayableReferences(List<PostReference> references) =>
    references.where((r) => r.isImage || r.isVideo).toList();

class PostAttachments extends StatelessWidget {
  final List<PostReference> references;

  const PostAttachments({super.key, required this.references});

  @override
  Widget build(BuildContext context) {
    final media = displayableReferences(references);
    if (media.isEmpty) return const SizedBox.shrink();

    final maxHeight =
        MediaQuery.of(context).size.height * _kMaxInlineHeightFactor;

    Widget layout;
    if (media.length == 1) {
      layout = _SingleAttachment(reference: media.first, maxHeight: maxHeight);
    } else if (media.length == 2) {
      layout = SizedBox(
        height: 220,
        child: Row(children: [
          Expanded(child: _tile(context, media, 0)),
          const SizedBox(width: 2),
          Expanded(child: _tile(context, media, 1)),
        ]),
      );
    } else if (media.length == 3) {
      layout = SizedBox(
        height: 260,
        child: Row(children: [
          Expanded(child: _tile(context, media, 0)),
          const SizedBox(width: 2),
          Expanded(
            child: Column(children: [
              Expanded(child: _tile(context, media, 1)),
              const SizedBox(height: 2),
              Expanded(child: _tile(context, media, 2)),
            ]),
          ),
        ]),
      );
    } else {
      layout = SizedBox(
        height: 300,
        child: Column(children: [
          Expanded(
            child: Row(children: [
              Expanded(child: _tile(context, media, 0)),
              const SizedBox(width: 2),
              Expanded(child: _tile(context, media, 1)),
            ]),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(children: [
              Expanded(child: _tile(context, media, 2)),
              const SizedBox(width: 2),
              // The 4th tile carries the overflow count when there are more.
              Expanded(
                  child: _tile(context, media, 3, overflow: media.length - 4)),
            ]),
          ),
        ]),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(CLRadii.md),
      child: layout,
    );
  }

  Widget _tile(
    BuildContext context,
    List<PostReference> media,
    int index, {
    int overflow = 0,
  }) =>
      _AttachmentTile(
        reference: media[index],
        overflow: overflow,
        onTap: () => openPostGallery(context, media, index),
      );
}

/// A lone attachment keeps its own shape rather than being cropped into a box.
class _SingleAttachment extends StatelessWidget {
  final PostReference reference;
  final double maxHeight;

  const _SingleAttachment({required this.reference, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    if (reference.isVideo) {
      return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        color: p.surface2,
        child: VideoPlayerScreen(videoUrl: reference.reference),
      );
    }
    return GestureDetector(
      onTap: () => openPostGallery(context, [reference], 0),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        width: double.infinity,
        color: p.surface2,
        child: CLNetworkImage(
          src: reference.reference,
          fit: BoxFit.cover,
          placeholderHeight: 240,
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final PostReference reference;
  final int overflow;
  final VoidCallback onTap;

  const _AttachmentTile({
    required this.reference,
    required this.overflow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: p.surface2),
          if (reference.isImage)
            CLNetworkImage(
              src: reference.reference,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          else
            // A grid tile never plays inline - initialising several video
            // controllers at once in a scrolling feed is the reliable way to
            // stutter it. The tile advertises the video and the viewer plays it.
            Center(
              child: Icon(Icons.play_circle_fill,
                  size: 40, color: Colors.white.withValues(alpha: 0.85)),
            ),
          if (overflow > 0)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: Text(
                "+$overflow",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the full-screen viewer at [initialIndex].
void openPostGallery(
  BuildContext context,
  List<PostReference> media,
  int initialIndex,
) {
  if (media.isEmpty) return;
  Navigator.of(context).push(
    // Opaque on purpose: this covers the screen, and a see-through route over
    // a page triggers the router's parallax (see CLPageRoute.canTransitionTo).
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          PostGalleryScreen(media: media, initialIndex: initialIndex),
    ),
  );
}

/// Full-screen media viewer: swipe between attachments, pinch/double-tap to
/// zoom an image, videos play in place.
class PostGalleryScreen extends StatefulWidget {
  final List<PostReference> media;
  final int initialIndex;

  const PostGalleryScreen({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });

  @override
  State<PostGalleryScreen> createState() => _PostGalleryScreenState();
}

class _PostGalleryScreenState extends State<PostGalleryScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Black regardless of theme - it's a media viewer, and any surface colour
    // here would tint the photo it's supposed to be showing.
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: widget.media.length > 1
            ? Text(
                "${_index + 1} of ${widget.media.length}",
                style: const TextStyle(
                    color: Colors.white, fontSize: CLType.title),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.media.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          final reference = widget.media[index];
          if (reference.isVideo) {
            return Center(
                child: VideoPlayerScreen(videoUrl: reference.reference));
          }
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: CLNetworkImage(
                src: reference.reference,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          );
        },
      ),
    );
  }
}
