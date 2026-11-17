import 'package:chatterloop_app/views/realm/realm_text_dialog.dart';
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
//     Remove tag        whoever is TAGGED, on someone else's post - untags
//                       them, which also takes the post off their profile.
//     Edit tags         AUTHOR only, once the post has tags: a sheet listing
//                       them, each removable.
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
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/report_sheet.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_edit.dart';
import 'package:chatterloop_app/core/utils/post_updates.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';

/// The acting entity - follows entity switching, unlike the account id.
String _actingEntityId() => appStore.state.userAuth.user.entityId;

/// True when the acting entity authored [post].
bool isOwnPost(PostPreview post) {
  final me = _actingEntityId();
  return post.isOwnedBy(me);
}

/// True when the acting entity authored the comment.
bool isOwnComment(PostPreviewAuthor commentAuthor, {bool? isOwner}) {
  final me = _actingEntityId();
  return isOwner ??
      (!commentAuthor.isAnonymous &&
          me.isNotEmpty &&
          commentAuthor.entityId == me);
}

/// True when the acting entity is tagged on [post] - a page's tag while
/// acting as the page, like everything else here.
bool isTaggedInPost(PostPreview post) {
  final me = _actingEntityId();
  return me.isNotEmpty && post.tagged.any((tag) => tag.entityId == me);
}

enum _PostOption {
  edit,
  audience,
  save,
  unsave,
  removeTag,
  editTags,
  archive,
  unarchive,
  delete,
  report,
  communityArchive,
  takeDown
}

class PostOptionsButton extends StatefulWidget {
  final PostPreview post;
  final CommunityApi? communityApi;

  /// Reports the post back after save/archive so the owner updates in place.
  final ValueChanged<PostPreview>? onChanged;

  /// Fired after a successful delete - the feed drops the row, the post screen
  /// pops. Without a handler the menu still deletes, it just can't tell anyone.
  final VoidCallback? onDeleted;

  const PostOptionsButton({
    super.key,
    required this.post,
    this.communityApi,
    this.onChanged,
    this.onDeleted,
  });

  @override
  State<PostOptionsButton> createState() => _PostOptionsButtonState();
}

class _PostOptionsButtonState extends State<PostOptionsButton> {
  bool _busy = false;

  Future<void> _edit({bool audience = false}) async {
    final updated = audience
        ? await showPostAudienceSheet(context, widget.post)
        : await openPostEditor(context, widget.post);
    if (mounted && updated != null) {
      widget.onChanged?.call(PostUpdates.instance.resolve(widget.post));
    }
  }

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
      // Already reported by the request (reportedAction).
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
      // Already reported by the request (reportedAction).
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
      // Already reported by the request (reportedAction).
    }
  }

  /// Untags the acting entity. Optimistic like save/archive; the server's
  /// answer then becomes the list, and a failure puts the old one back.
  Future<void> _removeMyTag() async {
    final before = widget.post.tagged;
    final me = _actingEntityId();
    setState(() => _busy = true);
    widget.onChanged?.call(widget.post
        .copyWith(tagged: before.where((tag) => tag.entityId != me).toList()));
    final remaining = await NewsfeedApi()
        .removePostTagRequest(postId: widget.post.postId, entityId: me);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged?.call(widget.post.copyWith(tagged: remaining ?? before));
  }

  /// The author's sheet of who the post is tagged with.
  Future<void> _editTags() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: cl(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _EditTagsSheet(
        postId: widget.post.postId,
        destinationEntityId: widget.post.community?.entityId,
        tagged: widget.post.tagged
            .where((tag) =>
                !tag.isCommunity &&
                tag.entityId != widget.post.community?.entityId)
            .toList(),
        // widget.post read at call time: the post underneath has already
        // been redrawn by the previous removal.
        onChanged: (remaining) {
          if (!mounted) return;
          widget.onChanged?.call(widget.post.copyWith(tagged: remaining));
        },
      ),
    );
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

  Future<void> _openMenu() async {
    if (_busy || widget.post.readOnly) return;
    final post = widget.post;
    final actor = _actingEntityId();
    final token = await ApiClient.instance.readToken();
    if (!mounted || actor != _actingEntityId()) return;
    Community? community;
    if (post.community != null) {
      setState(() => _busy = true);
      try {
        community =
            await (widget.communityApi ?? CommunityApi(authToken: token))
                .detail(post.community!.realmId);
      } catch (error) {
        if (mounted && actor == _actingEntityId()) {
          CLAlerts.requestError(error,
              fallback: 'Could not load post actions.');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted ||
        actor != _actingEntityId() ||
        token != await ApiClient.instance.readToken()) {
      return;
    }
    if (!mounted) return;
    final p = cl(context);
    final mine = isOwnPost(post);
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero),
            ancestor: overlay));
    final option = await showMenu<_PostOption>(
        context: context,
        color: p.surface,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        items: _menuItems(p, post, mine, community));
    if (!mounted ||
        option == null ||
        actor != _actingEntityId() ||
        token != await ApiClient.instance.readToken()) {
      return;
    }
    await _runOption(option, post, token);
  }

  List<PopupMenuEntry<_PostOption>> _menuItems(
          CLPalette p, PostPreview post, bool mine, Community? community) =>
      [
        if (mine) ...[
          _item(p,
              value: _PostOption.edit,
              icon: Icons.edit_outlined,
              label: 'Edit post'),
          if (post.community == null)
            _item(p,
                value: _PostOption.audience,
                icon: Icons.people_outline,
                label: 'Change audience'),
          const PopupMenuDivider(height: 12),
        ],
        // Save is for everyone, but an archived post isn't a thing you can
        // bookmark - it isn't in anyone's feed to come back to.
        if (!post.isArchived)
          _item(
            p,
            value: post.isSaved ? _PostOption.unsave : _PostOption.save,
            icon: post.isSaved ? Icons.bookmark_remove : Icons.bookmark_outline,
            label: post.isSaved ? "Unsave" : "Save",
          ),
        if (!mine && isTaggedInPost(post))
          _item(
            p,
            value: _PostOption.removeTag,
            icon: Icons.label_off_outlined,
            label: "Remove tag",
          ),
        if (mine &&
            post.tagged.any((tag) =>
                !tag.isCommunity && tag.entityId != post.community?.entityId))
          _item(
            p,
            value: _PostOption.editTags,
            icon: Icons.people_outline,
            label: "Edit tags",
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

        if (!mine &&
            post.community != null &&
            post.author.entityId == post.community!.entityId &&
            community?.capabilities.allows('can_archive_community_posts') ==
                true)
          _item(p,
              value: _PostOption.communityArchive,
              icon: Icons.archive_outlined,
              label: post.isArchived ? 'Unarchive' : 'Archive'),
        if (!mine &&
            post.community != null &&
            post.author.entityId != post.community!.entityId &&
            post.approval == 1 &&
            (post.updatedAt ?? post.datePosted) != null &&
            community?.capabilities.allows('can_take_down_posts') == true)
          _item(p,
              value: _PostOption.takeDown,
              icon: Icons.remove_circle_outline,
              label: 'Take down post',
              danger: true),
      ];

  Future<void> _runOption(
      _PostOption option, PostPreview post, String? token) async {
    switch (option) {
      case _PostOption.edit:
        _edit();
      case _PostOption.audience:
        _edit(audience: true);
      case _PostOption.save:
        _setSaved(true);
      case _PostOption.unsave:
        _setSaved(false);
      case _PostOption.removeTag:
        _removeMyTag();
      case _PostOption.editTags:
        _editTags();
      case _PostOption.archive:
        _setArchived(true);
      case _PostOption.unarchive:
        _setArchived(false);
      case _PostOption.delete:
        _delete();
      case _PostOption.report:
        _report();

      case _PostOption.communityArchive:
        await _communityAction(post, token, archive: true);
      case _PostOption.takeDown:
        await _communityAction(post, token);
    }
  }

  Future<void> _communityAction(PostPreview post, String? token,
      {bool archive = false}) async {
    final actor = _actingEntityId();
    final comment = archive
        ? ''
        : await showDialog<String>(
            context: context,
            builder: (_) => const RealmTextDialog(
                title: 'Take down this post?',
                label: 'Reason for the author',
                confirmLabel: 'Take down'));
    if (!mounted || comment == null) return;
    if (archive) {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Archive this community post?'),
                  content: const Text('The post will be hidden from feeds.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm'))
                  ]));
      if (accepted != true) return;
    }
    if (!mounted ||
        actor != _actingEntityId() ||
        token != await ApiClient.instance.readToken()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final api = widget.communityApi ?? CommunityApi(authToken: token);
      if (archive) {
        await api.archivePost(post.community!.realmId, post.postId,
            archived: !post.isArchived);
      } else {
        await api.reviewPost(post.community!.realmId, post.postId,
            action: 'takedown',
            expectedApproval: post.approval,
            expectedVersion:
                (post.updatedAt ?? post.datePosted)!.toIso8601String(),
            reason: comment);
      }
      if (!mounted ||
          actor != _actingEntityId() ||
          token != await ApiClient.instance.readToken()) {
        return;
      }
      PostUpdates.instance.apply({
        'post_id': post.postId,
        if (archive) 'is_archived': !post.isArchived,
        if (!archive) 'approval': 2
      });
      widget.onChanged?.call(archive
          ? post.copyWith(isArchived: !post.isArchived)
          : post.copyWith(approval: 2));
    } catch (error) {
      if (mounted && actor == _actingEntityId()) {
        CLAlerts.requestError(error,
            fallback:
                'The post may have changed. Refresh before trying again.');
        communityChanges.value++;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.post.readOnly) return const SizedBox.shrink();
    final p = cl(context);
    if (widget.post.community == null) {
      return PopupMenuButton<_PostOption>(
          enabled: !_busy,
          tooltip: 'Post options',
          padding: EdgeInsets.zero,
          color: p.surface,
          icon: Icon(Icons.more_horiz, size: 20, color: p.text2),
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          splashRadius: 20,
          onSelected: (option) => _runOption(option, widget.post, null),
          itemBuilder: (_) =>
              _menuItems(p, widget.post, isOwnPost(widget.post), null));
    }
    return IconButton(
        tooltip: 'Post options',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        splashRadius: 20,
        icon: Icon(Icons.more_horiz, size: 20, color: p.text2),
        onPressed: _busy ? null : _openMenu);
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

/// The author's list of who a post is tagged with, each one removable.
///
/// Every removal is its own request and answers with the tags that remain, so
/// the post's "is with ..." line follows along underneath - and the sheet
/// closes itself once nobody is left to list.
class _EditTagsSheet extends StatefulWidget {
  final String postId;
  final String? destinationEntityId;
  final List<PostPreviewAuthor> tagged;
  final ValueChanged<List<PostPreviewAuthor>> onChanged;

  const _EditTagsSheet({
    required this.postId,
    this.destinationEntityId,
    required this.tagged,
    required this.onChanged,
  });

  @override
  State<_EditTagsSheet> createState() => _EditTagsSheetState();
}

class _EditTagsSheetState extends State<_EditTagsSheet> {
  late List<PostPreviewAuthor> _tagged = widget.tagged;

  /// The tag being removed. One at a time: each answer is the whole remaining
  /// list, and two in flight could land in either order.
  String? _removingId;

  Future<void> _remove(PostPreviewAuthor entity) async {
    setState(() => _removingId = entity.entityId);
    final remaining = await NewsfeedApi()
        .removePostTagRequest(postId: widget.postId, entityId: entity.entityId);
    if (!mounted) return;
    setState(() => _removingId = null);
    if (remaining == null) return; // Already reported by the request.
    widget.onChanged(remaining);
    if (remaining.every((tag) =>
        tag.isCommunity || tag.entityId == widget.destinationEntityId)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _tagged = remaining
        .where((tag) =>
            !tag.isCommunity && tag.entityId != widget.destinationEntityId)
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, clSheetBottomGap(context, minimum: 20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.people_outline, color: p.text, size: 20),
            const SizedBox(width: 8),
            Text("Tagged entities",
                style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: p.text)),
          ]),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final entity in _tagged)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      CLAvatar(
                        id: entity.handle,
                        name: entity.displayName,
                        src: entity.profile,
                        kind: entity.type,
                        entityId: entity.entityId,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entity.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: CLType.title,
                              fontWeight: FontWeight.w600,
                              color: p.text),
                        ),
                      ),
                      CLBtn(
                        label: _removingId == entity.entityId
                            ? "Removing…"
                            : "Remove",
                        variant: CLBtnVariant.soft,
                        size: CLBtnSize.sm,
                        onPressed:
                            _removingId == null ? () => _remove(entity) : null,
                      ),
                    ]),
                  ),
              ],
            ),
          ),
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
