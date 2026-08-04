// One post AS A ROW IN A FEED - profile feeds today, the newsfeed next.
//
// The distinction from the two neighbouring widgets is worth stating, because
// all three render "a post":
//
//   SearchContentCard  a search HIT. Author line, clamped caption, two
//                      counters. No reactions, no actions - it exists to be
//                      recognised and tapped, not used.
//   PostItem (here)    the full post as content: author + who they're with,
//                      caption, link preview, attachments, reaction tallies
//                      and the react/comment/share bar. Everything webapp's
//                      PostItem shows above its inline comments.
//   PostPreviewScreen  the pushed screen - the same post plus its comment
//                      thread and the docked composer.
//
// It renders [PostCard] inside feed chrome rather than duplicating it. Forking
// the two would mean every future change to a post's body - a new attachment
// kind, a badge, an options menu - has to be made twice and will eventually be
// made once. What PostItem adds is what a FEED needs and a screen doesn't: a
// bounded card surface, separation from its neighbours, and the whole thing
// being a tap target that opens the post.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PostItem extends StatelessWidget {
  final PostPreview post;

  /// Reports the post back after a local change (a reaction), so the feed can
  /// keep its own list entry in step without refetching the page.
  final ValueChanged<PostPreview>? onChanged;

  /// Defaults to pushing the post screen. Overridable so a feed can intercept
  /// - e.g. to pass a warm copy through instead of refetching.
  final VoidCallback? onOpen;

  /// The feed drops this row - the post is gone server-side.
  final VoidCallback? onDeleted;

  const PostItem({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpen,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    void open() {
      if (onOpen != null) return onOpen!();
      context.push('/post/${post.postId}');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: PostCard(
        post: post,
        onChanged: onChanged,
        // onOpen marks this as a FEED row rather than the post's own screen -
        // that's what clamps the caption. It is no longer a body tap target:
        // onComment is the only way into the post from here, so tapping a
        // video in a row plays it instead of navigating off it.
        onOpen: open,
        onComment: open,
        onDeleted: onDeleted,
      ),
    );
  }
}

/// Placeholder shaped like a PostItem, for a feed page still loading.
class PostItemSkeleton extends StatelessWidget {
  const PostItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CLSkeleton(
                  width: 38,
                  height: 38,
                  borderRadius: BorderRadius.all(Radius.circular(19))),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CLSkeleton(width: 140, height: 12),
                    SizedBox(height: 7),
                    CLSkeleton(width: 80, height: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          CLSkeleton(width: double.infinity, height: 11),
          SizedBox(height: 7),
          CLSkeleton(width: 220, height: 11),
          SizedBox(height: 14),
          CLSkeleton(
              width: double.infinity,
              height: 150,
              borderRadius: BorderRadius.all(Radius.circular(CLRadii.md))),
        ],
      ),
    );
  }
}
