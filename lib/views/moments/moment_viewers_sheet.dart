import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:flutter/material.dart';

/// deleted and archived both take the moment out of what is playing.
enum MomentSheetOutcome { changed, deleted, archived, unarchived }

/// Your own moment's sheet (Moments polish 1d): who saw it and what they did,
/// its audience and replies setting, and Archive / Delete.
/// [archived]: played from the archive - it has expired, so audience,
/// replies and Archive are gone; who saw it (and Delete) stay.
///
/// A FIXED height - about 80% of the screen from the moment it opens. The
/// totals, settings and actions are pinned; only the list of viewers
/// scrolls, and while it loads (or a filter is switched) skeleton rows hold
/// the same space - so the sheet never opens tall and then drops to fit what
/// arrived.
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

  // Apart from the list: switching Views / Reactions / Replies reloads the
  // list, but these are the same for every filter and must not blank while
  // it loads.
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
    final filter = _filter;
    final viewers = await MomentsApi().getViewersRequest(
        EphemeralKind.moment, widget.moment.post.postId,
        filter: filter);
    // A later filter was picked while this one loaded.
    if (!mounted || filter != _filter) return;
    setState(() {
      _viewers = viewers;
      _totals = viewers;
    });
  }

  void _setFilter(String filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _viewers = null;
    });
    _load();
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
    final totals = _totals;
    final moment = widget.moment;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, clSheetBottomGap(context, minimum: 16, extra: 4)),
        child: Column(
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
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text("Viewers",
                      style: TextStyle(
                          fontSize: CLType.screenTitle,
                          fontWeight: FontWeight.w800,
                          color: p.text)),
                ),
                Text(
                    widget.archived
                        ? "Archived"
                        : ephemeralTimeLeft(moment.expiresAt),
                    style: TextStyle(fontSize: CLType.meta, color: p.text3)),
              ],
            ),
            const SizedBox(height: 12),
            // The totals ARE the filters.
            Row(
              children: [
                for (final (i, tile) in const [
                  ("all", Icons.visibility_outlined, "Views"),
                  ("reacted", Icons.favorite_border_rounded, "Reactions"),
                  ("replied", Icons.chat_bubble_outline_rounded, "Replies"),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _TotalTile(
                      icon: tile.$2,
                      label: tile.$3,
                      count: totals == null
                          ? null
                          : switch (tile.$1) {
                              "reacted" => totals.reactions,
                              "replied" => totals.replies,
                              _ => totals.views,
                            },
                      selected: _filter == tile.$1,
                      onTap: () => _setFilter(tile.$1),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _list(p)),
            if (!widget.archived) ...[
              const SizedBox(height: 12),
              _settings(p),
            ],
            const SizedBox(height: 12),
            _actions(p),
          ],
        ),
      ),
    );
  }

  Widget _list(CLPalette p) {
    final viewers = _viewers;
    if (viewers == null) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final width in const [120.0, 90.0, 140.0, 100.0, 130.0])
            _SkeletonRow(nameWidth: width),
        ],
      );
    }
    if (viewers.results.isEmpty) {
      return Center(
        child: Text(
          switch (_filter) {
            "reacted" => "No reactions yet.",
            "replied" => "No replies yet.",
            _ => "No one has seen this yet.",
          },
          style: TextStyle(fontSize: CLType.caption, color: p.text3),
        ),
      );
    }
    return ListView(
      children: [
        for (final viewer in viewers.results) _ViewerRow(viewer: viewer),
      ],
    );
  }

  /// Who can see it, and whether it takes replies - one pinned card.
  Widget _settings(CLPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text("Who can see this",
                      style: TextStyle(fontSize: CLType.body, color: p.text)),
                ),
                _AudienceSwitch(
                  value: _audience,
                  onChanged: _busy ? null : (a) => _update(audience: a),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: p.border,
          ),
          Semantics(
            toggled: _allowReplies,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _update(allowReplies: !_allowReplies),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text("Allow replies and reactions",
                          style:
                              TextStyle(fontSize: CLType.body, color: p.text)),
                    ),
                    _Toggle(on: _allowReplies),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(CLPalette p) {
    return Row(
      children: [
        Tooltip(
          message: "Delete",
          child: Semantics(
            button: true,
            label: "Delete",
            child: GestureDetector(
              onTap: _busy ? null : _delete,
              child: Container(
                width: 44,
                height: 40,
                decoration: BoxDecoration(
                  color: p.pinkSoft,
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                ),
                child:
                    Icon(Icons.delete_outline_rounded, size: 20, color: p.pink),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!widget.archived)
          Expanded(
            child: _SoftAction(
              icon: Icons.inventory_2_outlined,
              label: "Archive",
              onTap: _busy ? null : _archive,
            ),
          )
        else if (widget.moment.canUnarchive)
          Expanded(
            child: _SoftAction(
              icon: Icons.unarchive_outlined,
              label: "Unarchive",
              onTap: _busy ? null : _unarchive,
            ),
          ),
        if (!widget.archived || widget.moment.canUnarchive)
          const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.of(context)
                  .pop(_changed ? MomentSheetOutcome.changed : null),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.brand,
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x4D1C7DEF),
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: const Text("Done",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: CLType.title,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the three totals - also the filter for the list below.
class _TotalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _TotalTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final fg = selected ? p.brand : p.text;
    return Semantics(
      button: true,
      selected: selected,
      label: "$label ${count ?? ""}",
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? p.brandSoft : p.surface2,
            borderRadius: BorderRadius.circular(CLRadii.md),
            border: Border.all(
                color: selected ? p.brand : Colors.transparent, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 5),
                  Text(count?.toString() ?? "–",
                      style: TextStyle(
                          fontSize: CLType.screenTitle,
                          fontWeight: FontWeight.w800,
                          color: fg)),
                ],
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: CLType.meta,
                      fontWeight: FontWeight.w600,
                      color: selected ? p.brand : p.text3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public / Contacts, as a two-way switch.
class _AudienceSwitch extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const _AudienceSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surface3,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in ephemeralAudiences)
            Semantics(
              button: true,
              selected: value == a.key,
              child: GestureDetector(
                onTap: onChanged == null || value == a.key
                    ? null
                    : () => onChanged!(a.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: value == a.key
                        ? (light ? p.surface : p.border2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                    boxShadow: value == a.key
                        ? const [
                            BoxShadow(
                                color: Color(0x1F000000),
                                blurRadius: 3,
                                offset: Offset(0, 1)),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.icon,
                          size: 15, color: value == a.key ? p.text : p.text2),
                      const SizedBox(width: 4),
                      Text(a.label,
                          style: TextStyle(
                              fontSize: CLType.label,
                              fontWeight: FontWeight.w600,
                              color: value == a.key ? p.text : p.text2)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The replies switch - brand when on.
class _Toggle extends StatelessWidget {
  final bool on;

  const _Toggle({required this.on});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 40,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: on ? p.brand : p.border2,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))
            ],
          ),
        ),
      ),
    );
  }
}

/// Archive / Unarchive - a soft brand button.
class _SoftAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SoftAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: p.brandSoft,
              borderRadius: BorderRadius.circular(CLRadii.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: p.brand),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: CLType.title,
                        fontWeight: FontWeight.w600,
                        color: p.brand)),
              ],
            ),
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
    final sub = [
      if (viewer.reactionEmoji != null) "Reacted",
      if (viewer.replied) "Replied",
      ephemeralTimeAgo(viewer.lastActivityAt ?? viewer.viewedAt),
    ].where((s) => s.isNotEmpty).join(" · ");
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.surface3)),
      ),
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
                Text(sub,
                    style: TextStyle(fontSize: CLType.meta, color: p.text3)),
              ],
            ),
          ),
          if (viewer.replied)
            Container(
              width: 30,
              height: 30,
              decoration:
                  BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
              child: Icon(Icons.reply_rounded, size: 16, color: p.brand),
            ),
          if (viewer.replied && viewer.reactionEmoji != null)
            const SizedBox(width: 6),
          if (viewer.reactionEmoji != null)
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: p.surface2, shape: BoxShape.circle),
              child: Text(viewer.reactionEmoji!,
                  style: const TextStyle(fontSize: 17, height: 1)),
            ),
        ],
      ),
    );
  }
}

/// A viewer row while the list loads - the same height as a real one.
class _SkeletonRow extends StatelessWidget {
  final double nameWidth;

  const _SkeletonRow({required this.nameWidth});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.surface3)),
      ),
      child: Row(
        children: [
          const CLSkeleton(
              width: 38,
              height: 38,
              borderRadius: BorderRadius.all(Radius.circular(19))),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CLSkeleton(
                  width: nameWidth,
                  height: 12,
                  borderRadius: const BorderRadius.all(Radius.circular(6))),
              const SizedBox(height: 6),
              const CLSkeleton(
                  width: 60,
                  height: 10,
                  borderRadius: BorderRadius.all(Radius.circular(6))),
            ],
          ),
        ],
      ),
    );
  }
}
