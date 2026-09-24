import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:flutter/material.dart';

/// deleted and archived both take the moment out of what is playing.
enum MomentSheetOutcome { changed, deleted, archived, unarchived }

/// Your own moment's sheet (design 2c): who saw it and what they did
/// (All / Reacted / Replied), its audience and replies setting, and Delete.
/// [archived]: played from the archive - it has expired, so audience,
/// replies and Archive are gone; who saw it (and Delete) stay.
Future<MomentSheetOutcome?> showMomentViewersSheet(BuildContext context,
    {required Moment moment, bool archived = false}) {
  final p = cl(context);
  return showModalBottomSheet<MomentSheetOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
    builder: (_) => _MomentViewersSheet(moment: moment, archived: archived),
  );
}

class _MomentViewersSheet extends StatefulWidget {
  final Moment moment;
  final bool archived;

  const _MomentViewersSheet({required this.moment, this.archived = false});

  @override
  State<_MomentViewersSheet> createState() => _MomentViewersSheetState();
}

class _MomentViewersSheetState extends State<_MomentViewersSheet> {
  String _filter = "all";
  EphemeralViewers? _viewers;

  // Apart from the list: switching All / Reacted / Replied reloads the list,
  // but these are the same for every filter and must not blank while it loads.
  EphemeralViewers? _totals;
  late String _audience = widget.moment.post.privacyStatus == "connections"
      ? "connections"
      : "public";
  late bool _allowReplies = widget.moment.allowReplies;
  bool _changed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final viewers = await MomentsApi().getViewersRequest(
        EphemeralKind.moment, widget.moment.post.postId,
        filter: _filter);
    if (mounted) {
      setState(() {
        _viewers = viewers;
        _totals = viewers;
      });
    }
  }

  Future<void> _update({String? audience, bool? allowReplies}) async {
    final beforeAudience = _audience;
    final beforeReplies = _allowReplies;
    setState(() {
      if (audience != null) _audience = audience;
      if (allowReplies != null) _allowReplies = allowReplies;
    });
    final ok = await MomentsApi().updateMomentRequest(widget.moment.post.postId,
        privacyStatus: audience, allowReplies: allowReplies);
    if (!mounted) return;
    if (ok) {
      _changed = true;
    } else {
      setState(() {
        _audience = beforeAudience;
        _allowReplies = beforeReplies;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update your moment.")));
    }
  }

  /// Ends it now: it leaves the board and moves to your archive.
  Future<void> _archive() async {
    setState(() => _busy = true);
    final ok = await MomentsApi()
        .updateMomentRequest(widget.moment.post.postId, archive: true);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(MomentSheetOutcome.archived);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't archive your moment.")));
    }
  }

  /// Back on the board while its 24h last.
  Future<void> _unarchive() async {
    setState(() => _busy = true);
    final ok = await MomentsApi()
        .updateMomentRequest(widget.moment.post.postId, archive: false);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(MomentSheetOutcome.unarchived);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unarchive your moment.")));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete this moment?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await NewsfeedApi().deletePostRequest(widget.moment.post.postId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(MomentSheetOutcome.deleted);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete your moment.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final viewers = _viewers;
    final label = TextStyle(
        fontSize: CLType.meta, fontWeight: FontWeight.w700, color: p.text3);

    return Padding(
      padding: EdgeInsets.only(
          bottom: clSheetBottomGap(context, minimum: 16, extra: 8)),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.border2,
                      borderRadius: BorderRadius.circular(CLRadii.pill)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text("Viewers",
                        style: TextStyle(
                            fontSize: CLType.sectionTitle,
                            fontWeight: FontWeight.w800,
                            color: p.text)),
                  ),
                  if (_totals != null)
                    Text(
                        "${_totals!.views} views · ${_totals!.reactions} reactions · ${_totals!.replies} replies",
                        style:
                            TextStyle(fontSize: CLType.meta, color: p.text3)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final f in const [
                    ("all", "All"),
                    ("reacted", "Reacted"),
                    ("replied", "Replied"),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CLChip(
                        label: f.$2,
                        active: _filter == f.$1,
                        onTap: () {
                          setState(() {
                            _filter = f.$1;
                            _viewers = null;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: viewers == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()))
                    : viewers.results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _filter == "all"
                                  ? "No one has seen this yet."
                                  : "No one here yet.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: CLType.caption, color: p.text3),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final viewer in viewers.results)
                                _ViewerRow(viewer: viewer),
                            ],
                          ),
              ),
              const SizedBox(height: 10),
              if (!widget.archived) ...[
                Text("WHO CAN SEE THIS", style: label),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final a in ephemeralAudiences)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: CLChip(
                          label: a.label,
                          icon: a.icon,
                          active: _audience == a.key,
                          onTap: _busy || _audience == a.key
                              ? null
                              : () => _update(audience: a.key),
                        ),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowReplies,
                  onChanged: _busy ? null : (v) => _update(allowReplies: v),
                  title: Text("Allow replies and reactions",
                      style: TextStyle(fontSize: CLType.body, color: p.text)),
                ),
              ],
              Row(
                children: [
                  if (widget.archived && widget.moment.canUnarchive) ...[
                    Expanded(
                      child: CLBtn(
                        label: "Unarchive",
                        iconL: Icons.unarchive_outlined,
                        onPressed: _busy ? null : _unarchive,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (!widget.archived) ...[
                    Expanded(
                      child: CLBtn(
                        label: "Archive",
                        iconL: Icons.inventory_2_outlined,
                        variant: CLBtnVariant.soft,
                        onPressed: _busy ? null : _archive,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: CLBtn(
                      label: "Delete",
                      iconL: Icons.delete_outline_rounded,
                      variant: CLBtnVariant.soft,
                      onPressed: _busy ? null : _delete,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CLBtn(
                      label: "Done",
                      onPressed: () => Navigator.of(context)
                          .pop(_changed ? MomentSheetOutcome.changed : null),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  final EphemeralViewer viewer;

  const _ViewerRow({required this.viewer});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CLAvatar(
            id: viewer.entity.entityId,
            name: viewer.entity.displayName,
            src: viewer.entity.profile,
            entityId: viewer.entity.entityId,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(viewer.entity.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: CLType.title,
                        fontWeight: FontWeight.w600,
                        color: p.text)),
                Text(ephemeralTimeAgo(viewer.lastActivityAt ?? viewer.viewedAt),
                    style: TextStyle(fontSize: CLType.meta, color: p.text3)),
              ],
            ),
          ),
          if (viewer.replied)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.reply_rounded, size: 18, color: p.brand),
            ),
          if (viewer.reactionEmoji != null)
            Text(viewer.reactionEmoji!, style: const TextStyle(fontSize: 20)),
        ],
      ),
    );
  }
}
