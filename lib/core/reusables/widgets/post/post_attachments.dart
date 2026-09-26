// A post's media, and the full-screen viewer it opens into.
//
// Layout is chosen by COUNT, which is the thing that actually decides what
// reads well in a feed:
//
//   1        one image or video, full width, at its own aspect ratio (capped,
//            and cropped to cover past the cap - the viewer shows it whole) -
//            a lone photo in a fixed-height box is the classic letterboxing
//            mistake
//   2        two equal halves
//   3        one large left, two stacked right
//   4+       2x2 grid, with a "+N" scrim on the last tile
//
// Deliberately a GRID rather than an inline carousel: a feed is already a
// vertical scroll, and a horizontally-swiping child inside it fights the
// parent gesture (and hides everything after the first slide, so you can't
// tell a 2-image post from a 9-image one at a glance). The carousel belongs
// in the full-screen viewer, where swiping is the only gesture - that's what
// [openPostGallery] opens. Same reasoning webapp's grid-then-lightbox uses.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
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

  /// Whether a lone video is a player here - controls showing, playing by
  /// itself while in view (see [InlinePostVideo]) - or a still that opens the
  /// full-screen viewer.
  ///
  /// True for posts - the feed and the post screen. Two players on one video
  /// used to collide (the screen opened over a playing row drew nothing); the
  /// shared controllers made that one player (SharedVideoControllers). False
  /// where a post is only being previewed: the share composer, moderation.
  final bool playInline;

  const PostAttachments({
    super.key,
    required this.references,
    this.playInline = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = displayableReferences(references);
    if (media.isEmpty) return const SizedBox.shrink();

    final maxHeight =
        MediaQuery.of(context).size.height * _kMaxInlineHeightFactor;

    Widget layout;
    if (media.length == 1) {
      layout = _SingleAttachment(
        reference: media.first,
        maxHeight: maxHeight,
        playInline: playInline,
      );
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
  final bool playInline;

  const _SingleAttachment({
    required this.reference,
    required this.maxHeight,
    this.playInline = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    if (reference.isVideo) {
      // The video's own shape either way - full width, capped, covering (see
      // InlinePostVideo). Without playInline a tap opens the same full-screen
      // viewer a photo does instead of a player here.
      return InlinePostVideo(
        source: reference.reference,
        maxHeight: maxHeight,
        onTap:
            playInline ? null : () => openPostGallery(context, [reference], 0),
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
            // A grid tile never PLAYS inline, but it does show the video's
            // first frame - two videos in one post were otherwise two identical
            // grey rectangles with no clue which was which. The frame comes
            // from the shared registry, so a tile and the full player for the
            // same source share one controller rather than each holding a
            // decoder.
            VideoFirstFrame(source: reference.reference),
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
///
/// A thin mapping onto the app-wide [openMediaViewer] - the gallery this used
/// to own (a PageView of InteractiveViewers and players) was the same screen a
/// conversation needed for its attachments, and keeping two copies of it meant
/// only one of them ever got the download action. `canDownload` is false here
/// because saving media is a messaging affordance; a post's media has no such
/// action anywhere else in the app.
void openPostGallery(
  BuildContext context,
  List<PostReference> media,
  int initialIndex,
) {
  openMediaViewer(
    context,
    media
        .map((reference) => MediaViewerItem(
              source: reference.reference,
              isVideo: reference.isVideo,
              mimeType: reference.mediaType,
            ))
        .toList(),
    initialIndex,
    canDownload: false,
  );
}
