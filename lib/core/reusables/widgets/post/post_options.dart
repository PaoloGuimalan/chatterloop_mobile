// The ⋯ menus on a post and on a comment, and the rules for what they offer.
//
// Ported from webapp's PostOptions.tsx and the CommentOptions it renders from
// PostComment.tsx. The conditions matter more than the buttons:
//
//   POST
//     Save / Unsave     ANYONE who can see the post - it's a bookmark, not an
//                       authorship action - but HIDDEN while archived.
//     Archive/Unarchive AUTHOR only.
//     Delete            AUTHOR only.
//     Report            everyone EXCEPT the author. The report lands on the
//                       post's authoring entity, so reporting your own post
//                       would be reporting yourself, which the server rejects.
//   COMMENT
//     Delete            its AUTHOR only. (Web exposes no edit, though the
//                       endpoint has a PUT - so neither does this.)
//     Report            everyone EXCEPT its author, for the same reason as a
//                       post: the report resolves to the comment's authoring
//                       entity.
//
// "Author" is compared on ENTITY id, never the account id. That's what makes a
// page's own post manageable while you're acting as that page, and what stops
// your personal account from managing it when you're not. The server enforces
// the same rules; these gates only avoid offering a button that would 403.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/report_sheet.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

/// The acting entity - follows entity switching, unlike the account id.
String _actingEntityId() => appStore.state.userAuth.user.entityId;

/// True when the acting entity authored [post].
bool isOwnPost(PostPreview post) {
  final me = _actingEntityId();
  return me.isNotEmpty && post.author.entityId == me;
}

/// True when the acting entity authored the comment.
bool isOwnComment(PostPreviewAuthor commentAuthor) {
  final me = _actingEntityId();
  return me.isNotEmpty && commentAuthor.entityId == me;
}

enum _PostOption { save, unsave, archive, unarchive, delete, report }

class PostOptionsButton extends StatefulWidget {
  final PostPreview post;

  /// Reports the post back after save/archive so the owner updates in place.
  final ValueChanged<PostPreview>? onChanged;

  /// Fired after a successful delete - the feed drops the row, the post screen
  /// pops. Without a handler the menu still deletes, it just can't tell anyone.
  final VoidCallback? onDeleted;

  const PostOptionsButton({
    super.key,
    required this.post,
    this.onChanged,
    this.onDeleted,
  });

  @override
  State<PostOptionsButton> createState() => _PostOptionsButtonState();
}

class _PostOptionsButtonState extends State<PostOptionsButton> {
  bool _busy = false;

  Future<void> _setSaved(bool saved) async {
    setState(() => _busy = true);
    // Optimistic, like every other toggle here: the menu has already closed,
    // so waiting on the round-trip would just look like nothing happened.
    widget.onChanged?.call(widget.post.copyWith(isSaved: saved));
    final ok = await NewsfeedApi()
        .setPostSavedRequest(postId: widget.post.postId, saved: saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      widget.onChanged?.call(widget.post.copyWith(isSaved: !saved));
      _toast("Couldn't ${saved ? 'save' : 'unsave'} that post.");
    }
  }

  Future<void> _setArchived(bool archived) async {
    setState(() => _busy = true);
    widget.onChanged?.call(widget.post.copyWith(isArchived: archived));
    final ok = await NewsfeedApi()
        .setPostArchivedRequest(postId: widget.post.postId, archived: archived);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      widget.onChanged?.call(widget.post.copyWith(isArchived: !archived));
      _toast("Couldn't ${archived ? 'archive' : 'unarchive'} that post.");
    }
  }

  Future<void> _delete() async {
    // Confirmed, unlike save/archive: deleting a post can't be undone from
    // anywhere in the app.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cl(ctx).surface,
        title: Text('Delete this post?',
            style:
                TextStyle(color: cl(ctx).text, fontSize: CLType.screenTitle)),
        content: Text(
          "This can't be undone. The post and its comments will be removed.",
          style: TextStyle(color: cl(ctx).text2, fontSize: CLType.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: cl(ctx).pink)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await NewsfeedApi().deletePostRequest(widget.post.postId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onDeleted?.call();
    } else {
      _toast("Couldn't delete that post. Try again.");
    }
  }

  /// Report the post. Sends the POST id, not the author's entity id - the
  /// server resolves the authoring entity itself, which is what keeps a report
  /// on a page's post landing on the page rather than on whoever runs it.
  ///
  /// Nothing is optimistic here and nothing changes locally: a report is a
  /// message to moderation, not a state change on the post. The sheet raises
  /// its own confirmation toast.
  Future<void> _report() async {
    await showReportSheet(
      context,
      targetType: ReportTargetType.post,
      targetId: widget.post.postId,
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final post = widget.post;
    final mine = isOwnPost(post);

    // Report keeps the menu non-empty for a visitor looking at an archived
    // post, so the old "nothing to offer" bail-out no longer applies - an
    // archived post is still reportable.

    return PopupMenuButton<_PostOption>(
      enabled: !_busy,
      tooltip: "Post options",
      padding: EdgeInsets.zero,
      color: p.surface,
      icon: Icon(Icons.more_horiz, size: 20, color: p.text2),
      // Tighter than the 48x48 default, which would set the header's height
      // rather than the 38px avatar - still a comfortable target.
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      splashRadius: 20,
      onSelected: (option) {
        switch (option) {
          case _PostOption.save:
            _setSaved(true);
          case _PostOption.unsave:
            _setSaved(false);
          case _PostOption.archive:
            _setArchived(true);
          case _PostOption.unarchive:
            _setArchived(false);
          case _PostOption.delete:
            _delete();
          case _PostOption.report:
            _report();
        }
      },
      itemBuilder: (context) => [
        // Save is for everyone, but an archived post isn't a thing you can
        // bookmark - it isn't in anyone's feed to come back to.
        if (!post.isArchived)
          _item(
            p,
            value: post.isSaved ? _PostOption.unsave : _PostOption.save,
            icon: post.isSaved ? Icons.bookmark_remove : Icons.bookmark_outline,
            label: post.isSaved ? "Unsave" : "Save",
          ),
        if (mine)
          _item(
            p,
            value:
                post.isArchived ? _PostOption.unarchive : _PostOption.archive,
            icon: post.isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            label: post.isArchived ? "Unarchive" : "Archive",
          ),
        if (mine)
          _item(
            p,
            value: _PostOption.delete,
            icon: Icons.delete_outline,
            label: "Delete",
            danger: true,
          ),
        if (!mine)
          _item(
            p,
            value: _PostOption.report,
            icon: Icons.report,
            label: "Report",
            // Red, like Delete: reporting is a moderation escalation, not a
            // neutral action, and the two menus must agree on that.
            danger: true,
          ),
      ],
    );
  }

  PopupMenuItem<_PostOption> _item(
    CLPalette p, {
    required _PostOption value,
    required IconData icon,
    required String label,
    bool danger = false,
  }) {
    final color = danger ? p.pink : p.text;
    return PopupMenuItem<_PostOption>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: CLType.bodySm, color: color)),
        ],
      ),
    );
  }
}

enum _CommentOption { delete, report }

/// The ⋯ on a comment. Rendered on EVERY comment now: Delete for its author,
/// Report for everyone else - see the file header.
///
/// Deleting stays presentational, unlike [PostOptionsButton]: that request
/// lives in PostComments, because deleting a comment is optimistic against a
/// LIST the thread owns (and a top-level delete takes its replies with it),
/// which this widget can't see. Same split webapp uses - CommentOptions
/// renders, the parent's DeleteCommentProcess acts.
///
/// Reporting is handled here, because it changes nothing in that list - it is
/// a message to moderation, not a state change on the comment.
class CommentOptionsButton extends StatelessWidget {
  /// Null when the viewer can't delete this comment, which is also when Report
  /// takes its place.
  final VoidCallback? onDelete;

  /// The comment's own id - what a report is filed against.
  final String commentId;

  /// Authored by the acting entity.
  final bool isOwn;

  /// A delete already in flight for this comment.
  final bool busy;

  const CommentOptionsButton({
    super.key,
    required this.commentId,
    required this.isOwn,
    this.onDelete,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final canDelete = isOwn && onDelete != null;

    // Nothing to offer: your own comment that the thread gave no delete
    // handler for. Render no button rather than an empty menu.
    if (isOwn && !canDelete) return const SizedBox.shrink();

    return PopupMenuButton<_CommentOption>(
      enabled: !busy,
      tooltip: "Comment options",
      padding: EdgeInsets.zero,
      color: p.surface,
      // Smaller than the post's - it sits on a comment's meta row.
      icon: Icon(Icons.more_horiz, size: 16, color: p.text3),
      // Tight: the default IconButton box would push the meta row taller than
      // the timestamp beside it.
      constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
      iconSize: 16,
      splashRadius: 14,
      onSelected: (option) {
        switch (option) {
          case _CommentOption.delete:
            onDelete?.call();
          case _CommentOption.report:
            showReportSheet(
              context,
              targetType: ReportTargetType.comment,
              targetId: commentId,
            );
        }
      },
      itemBuilder: (context) => [
        if (canDelete)
          PopupMenuItem<_CommentOption>(
            value: _CommentOption.delete,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: p.pink),
                const SizedBox(width: 10),
                Text("Delete",
                    style: TextStyle(fontSize: CLType.bodySm, color: p.pink)),
              ],
            ),
          ),
        if (!isOwn)
          PopupMenuItem<_CommentOption>(
            value: _CommentOption.report,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.report, size: 18, color: p.pink),
                const SizedBox(width: 10),
                Text("Report",
                    style: TextStyle(fontSize: CLType.bodySm, color: p.pink)),
              ],
            ),
          ),
      ],
    );
  }
}
