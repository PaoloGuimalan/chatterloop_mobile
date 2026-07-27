// Read-only post view, opened by tapping an Explore content card. Backed by
// the same /api/newsfeed/preview/<post_id>/ endpoint webapp's PostPreviewModal
// uses, and showing the same parts of a post: media, author, caption, link
// preview and the reaction/comment tallies.
//
// Deliberately read-only. Reacting, commenting and sharing are the composer's
// job and this app has no post-authoring surface yet - so this screen shows a
// post rather than pretending to be a feed item. It exists because Explore
// surfaces posts and a search hit you can't open is a dead end.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/linkify_text.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PostPreviewScreen extends StatefulWidget {
  final String postId;

  const PostPreviewScreen({super.key, required this.postId});

  @override
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> {
  PostPreview? _post;
  bool _isLoading = true;

  /// Which media page the carousel is on - only shown when there's more than
  /// one attachment.
  int _mediaIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await FeedApi().getPostPreviewRequest(widget.postId);
    if (!mounted) return;
    setState(() {
      _post = result;
      _isLoading = false;
    });
  }

  void _openAuthor(PostPreviewAuthor author) {
    if (author.handle.isEmpty) return;
    context
        .push(author.isRealm ? '/realm/${author.handle}' : '/user/${author.handle}');
  }

  Widget _media(PostPreview post, CLPalette p) {
    // A shared post's media belongs to the post it references, not to this one.
    if (post.isShared || post.references.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          height: 320,
          color: p.surface2,
          child: PageView.builder(
            itemCount: post.references.length,
            onPageChanged: (index) => setState(() => _mediaIndex = index),
            itemBuilder: (context, index) {
              final reference = post.references[index];
              if (reference.isVideo) {
                return VideoPlayerScreen(videoUrl: reference.reference);
              }
              if (reference.isImage) {
                return CLNetworkImage(
                  src: reference.reference,
                  height: 320,
                  fit: BoxFit.contain,
                  placeholderHeight: 320,
                );
              }
              // Neither image nor video - an attachment kind this screen can't
              // render inline.
              return Center(
                child: Icon(Icons.insert_drive_file_outlined,
                    size: 34, color: p.text3),
              );
            },
          ),
        ),
        if (post.references.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                post.references.length,
                (index) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _mediaIndex ? p.brand : p.border2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(PostPreview post, CLPalette p) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _media(post, p),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => _openAuthor(post.author),
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                    child: CLAvatar(
                      id: post.author.entityId,
                      name: post.author.displayName,
                      src: post.author.profile,
                      size: 38,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAuthor(post.author),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  post.author.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: p.text,
                                  ),
                                ),
                              ),
                              if (post.author.isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.verified, size: 14, color: p.brand),
                              ],
                            ],
                          ),
                          if (post.datePosted != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              timeSince(post.datePosted!),
                              style: TextStyle(fontSize: 12, color: p.text3),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    children: linkifySpans(
                      post.caption,
                      TextStyle(fontSize: 14.5, height: 1.45, color: p.text),
                    ),
                  ),
                ),
              ],
              if (post.linkPreview != null) ...[
                const SizedBox(height: 12),
                LinkPreviewCard(preview: post.linkPreview),
              ],
              const SizedBox(height: 16),
              Divider(height: 1, color: p.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (post.reactions.isNotEmpty)
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: post.reactions
                            .map((reaction) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(reaction.emoji,
                                        style: const TextStyle(fontSize: 15)),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${reaction.count}",
                                      style: TextStyle(
                                          fontSize: 12.5, color: p.text3),
                                    ),
                                  ],
                                ))
                            .toList(),
                      ),
                    )
                  else
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.favorite_border, size: 15, color: p.text3),
                          const SizedBox(width: 4),
                          Text("${post.likesCount}",
                              style:
                                  TextStyle(fontSize: 12.5, color: p.text3)),
                        ],
                      ),
                    ),
                  Icon(Icons.mode_comment_outlined, size: 15, color: p.text3),
                  const SizedBox(width: 4),
                  Text("${post.commentsCount}",
                      style: TextStyle(fontSize: 12.5, color: p.text3)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = _post;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Post")),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: p.brand))
          : post == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CLEmptyState(
                      icon: Icons.article_outlined,
                      iconBg: p.surface2,
                      iconColor: p.text2,
                      iconBorderColor: p.border,
                      title: "Post unavailable",
                      subtitle:
                          "It may have been deleted, or you may not have access to it.",
                    ),
                  ),
                )
              : _body(post, p),
    );
  }
}
