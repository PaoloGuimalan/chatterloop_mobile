import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The ORIGINAL post id of a reshare. The feed marks a reshare `is_shared`,
/// and its reference is the original's id - typed "shared_post" when the
/// composer wrote it, but not by every writer, so the first reference is the
/// fallback.
String? reshareOriginalId(PostPreview post) {
  if (!post.isShared) return null;
  return post.sharedPostId ??
      (post.references.isEmpty ? null : post.references.first.reference);
}

/// A post as a Moment carries it - Create Moment's preview and the viewer's
/// stage: author, caption, and its media, a VIDEO playing (muted, on a
/// loop) rather than only photos; and when the post is itself a share, the
/// original nested inside, the way a post card draws it.
class MomentSharedPostCard extends StatefulWidget {
  final PostPreview post;

  /// Tapping the card (not its video) - the viewer opens the post.
  final VoidCallback? onOpen;
  final double mediaHeight;

  /// Drawn inside another card: flat, and never nests again.
  final bool nested;

  const MomentSharedPostCard({
    super.key,
    required this.post,
    this.onOpen,
    this.mediaHeight = 200,
    this.nested = false,
  });

  @override
  State<MomentSharedPostCard> createState() => _MomentSharedPostCardState();
}

class _MomentSharedPostCardState extends State<MomentSharedPostCard> {
  PostPreview? _original;
  bool _originalMissing = false;

  @override
  void initState() {
    super.initState();
    _loadOriginal();
  }

  @override
  void didUpdateWidget(MomentSharedPostCard old) {
    super.didUpdateWidget(old);
    if (old.post.postId != widget.post.postId) {
      _original = null;
      _originalMissing = false;
      _loadOriginal();
    }
  }

  Future<void> _loadOriginal() async {
    final id = widget.nested ? null : reshareOriginalId(widget.post);
    if (id == null) return;
    final original = await FeedApi().getPostPreviewRequest(id);
    if (!mounted || reshareOriginalId(widget.post) != id) return;
    setState(() {
      _original = original;
      _originalMissing = original == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = widget.post;
    final isReshare = post.isShared;
    // A reshare's own reference is the original, not media.
    final media = isReshare
        ? null
        : post.references
            .where((r) => r.isImage || r.isVideo)
            .cast<PostReference?>()
            .firstWhere((_) => true, orElse: () => null);

    final card = Container(
      padding: EdgeInsets.all(widget.nested ? 10 : 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: widget.nested ? Border.all(color: p.border) : null,
        boxShadow: widget.nested
            ? null
            : const [
                BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 30,
                    offset: Offset(0, 10))
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CLAvatar(
                  id: post.author.entityId,
                  name: post.author.displayName,
                  src: post.author.profile,
                  size: widget.nested ? 24 : 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(post.author.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: widget.nested ? CLType.caption : CLType.body,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
              ),
            ],
          ),
          if (post.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(post.caption,
                maxLines: widget.nested ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: widget.nested ? CLType.caption : CLType.body,
                    color: p.text)),
          ],
          if (media != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(CLRadii.sm),
              child: SizedBox(
                width: double.infinity,
                height: widget.nested
                    ? widget.mediaHeight * 0.7
                    : widget.mediaHeight,
                child: media.isVideo
                    ? _LoopingVideo(src: media.reference)
                    : CLNetworkImage(src: media.reference, fit: BoxFit.cover),
              ),
            ),
          ],
          if (isReshare && !widget.nested) ...[
            const SizedBox(height: 8),
            if (_original != null)
              MomentSharedPostCard(
                  post: _original!,
                  nested: true,
                  mediaHeight: widget.mediaHeight)
            else if (_originalMissing)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                  border: Border.all(color: p.border),
                ),
                child: Text("The original post is no longer available.",
                    style: TextStyle(fontSize: CLType.caption, color: p.text3)),
              )
            else
              CLSkeleton(
                  width: double.infinity,
                  height: 64,
                  borderRadius: BorderRadius.circular(CLRadii.sm)),
          ],
        ],
      ),
    );

    return widget.onOpen == null
        ? card
        : GestureDetector(onTap: widget.onOpen, child: card);
  }
}

/// A shared post's video, playing muted on a loop - from the app's shared
/// controller cache (see SharedVideoControllers), so it is not a second
/// decoder racing the first.
class _LoopingVideo extends StatefulWidget {
  final String src;

  const _LoopingVideo({required this.src});

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  late final SharedVideoEntry _entry =
      SharedVideoControllers.acquire(widget.src, isLocalFile: false);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _entry.ready.then((_) async {
      if (!mounted) return;
      final controller = _entry.controller;
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    SharedVideoControllers.release(widget.src, isLocalFile: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _entry.controller;
    if (!_ready || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child: Icon(Icons.play_circle_outline_rounded,
                color: Colors.white70, size: 34)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
