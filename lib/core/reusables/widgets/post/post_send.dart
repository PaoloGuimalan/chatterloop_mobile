// A post's Share action, and its "Send in message" half.
//
// Share offers two ways to share, like webapp's SharePostButton:
//
//   Share to feed    - the existing repost (post_share.dart): a new post of
//                      your own whose single reference is this post.
//   Send in message  - this post to up to 10 destinations - anyone (a chat is
//                      opened if you have none), your group chats, your
//                      server channels - each as a message whose reply card is
//                      the post (/u/sendPost).
//
// Both are shares - each bumps the post's share count and ranking once.

import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/models/messages_models/send_post_targets_model.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/material.dart';

enum ShareChoice { toFeed, inMessage, toMoment }

/// The two-option Share sheet. Null when dismissed.
Future<ShareChoice?> showShareOptionsSheet(BuildContext context) {
  final p = cl(context);
  return showModalBottomSheet<ShareChoice>(
    context: context,
    useRootNavigator: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: clSheetBottomGap(sheetContext, minimum: 12, extra: 4)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: p.border2,
              borderRadius: BorderRadius.circular(CLRadii.pill),
            ),
          ),
          const SizedBox(height: 8),
          _ShareOption(
            icon: Icons.repeat_rounded,
            label: "Share to feed",
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.toFeed),
          ),
          _ShareOption(
            icon: Icons.send_rounded,
            label: "Send in message",
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.inMessage),
          ),
          _ShareOption(
            icon: Icons.timelapse_rounded,
            label: "Add to Moment",
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.toMoment),
          ),
        ],
      ),
    ),
  );
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShareOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return ListTile(
      leading: Icon(icon, color: p.text),
      title: Text(
        label,
        style: TextStyle(
            fontSize: CLType.title, color: p.text, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}

/// Opens "Send in message". Resolves true once the post reached at least one
/// conversation.
Future<bool> showSendPostSheet(BuildContext context,
    {required PostPreview post}) async {
  final p = cl(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg)),
    ),
    builder: (sheetContext) => Padding(
      // Lifts the sheet above the keyboard once the search or note is focused.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _SendPostSheet(post: post),
    ),
  );
  return sent == true;
}

class _SendPostSheet extends StatefulWidget {
  final PostPreview post;

  const _SendPostSheet({required this.post});

  @override
  State<_SendPostSheet> createState() => _SendPostSheetState();
}

class _SendPostSheetState extends State<_SendPostSheet> {
  static const _max = ConversationsApi.sendPostMaxConversations;

  // Searching waits for a pause in typing rather than firing on every key.
  static const _searchDelay = Duration(milliseconds: 250);

  final TextEditingController _query = TextEditingController();
  final TextEditingController _note = TextEditingController();

  SendPostTargets? _targets;
  bool _loading = true;
  bool _sending = false;
  Timer? _debounce;
  int _requestSerial = 0;

  /// What was picked, in the order picked - kept here (not just the ids) so a
  /// choice stays listed at the top after the search moves past it.
  final List<SendPostOption> _selected = [];

  @override
  void initState() {
    super.initState();
    _load("");
    _query.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(_searchDelay, () => _load(_query.text.trim()));
    });
  }

  Future<void> _load(String query) async {
    final serial = ++_requestSerial;
    setState(() => _loading = true);
    final result = await ConversationsApi().getSendPostTargetsRequest(query);
    // A slower, older search must not overwrite a newer one.
    if (!mounted || serial != _requestSerial) return;
    setState(() {
      _targets = result ?? SendPostTargets.empty;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _isSelected(SendPostOption option) =>
      _selected.any((s) => s.target == option.target);

  void _toggle(SendPostOption option) {
    setState(() {
      if (_isSelected(option)) {
        _selected.removeWhere((s) => s.target == option.target);
      } else if (_selected.length < _max) {
        _selected.add(option);
      }
    });
  }

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    setState(() => _sending = true);

    final result = await ConversationsApi().sendPostRequest(
      postId: widget.post.postId,
      targets: _selected.map((s) => s.target).toList(),
      note: _note.text.trim(),
    );
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (result == null || result.sent == 0) {
      setState(() => _sending = false);
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't send that post. Try again."),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    messenger.showSnackBar(SnackBar(
      content: Text(result.failed > 0
          ? "Sent to ${result.sent}, but ${result.failed} couldn't be reached"
          : result.sent == 1
              ? "Post sent"
              : "Post sent to ${result.sent} chats"),
      duration: const Duration(seconds: 2),
    ));
    Navigator.of(context).pop(true);
  }

  List<Widget> _section(String label, List<SendPostOption> options,
      {required bool atLimit}) {
    final fresh = options.where((o) => !_isSelected(o)).toList();
    if (fresh.isEmpty) return const [];
    return [
      SendPostSectionLabel(label),
      for (final option in fresh)
        SendPostOptionRow(
          option: option,
          selected: false,
          enabled: !_sending && !atLimit,
          onTap: () => _toggle(option),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final atLimit = _selected.length >= _max;
    final targets = _targets;
    final searching = _query.text.trim().isNotEmpty;

    final rows = <Widget>[
      if (_selected.isNotEmpty) ...[
        const SendPostSectionLabel("Selected"),
        for (final option in _selected)
          SendPostOptionRow(
            option: option,
            selected: true,
            enabled: !_sending,
            onTap: () => _toggle(option),
          ),
      ],
      if (targets != null) ...[
        ..._section(
            searching ? "People & pages" : "Direct messages", targets.direct,
            atLimit: atLimit),
        ..._section("Group chats", targets.groups, atLimit: atLimit),
        ..._section("Servers", targets.channels, atLimit: atLimit),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(
          bottom: clSheetBottomGap(context, minimum: 16, extra: 8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
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
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Send in message",
                style: TextStyle(
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                style: TextStyle(color: p.text, fontSize: CLType.title),
                decoration: _inputDecoration(p,
                    hint: "Search people, pages, groups and servers",
                    prefix: Icon(Icons.search, color: p.text3)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_selected.length} of $_max selected",
                      style: TextStyle(fontSize: CLType.meta, color: p.text3),
                    ),
                  ),
                  if (atLimit)
                    Text(
                      "$_max max",
                      style: TextStyle(fontSize: CLType.meta, color: p.text3),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: _loading && targets == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : rows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              searching
                                  ? "No one matches that search."
                                  : "Search for someone to send this to.",
                              style: TextStyle(
                                  fontSize: CLType.caption, color: p.text3),
                            ),
                          )
                        : ListView(shrinkWrap: true, children: rows),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                enabled: !_sending,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: p.text, fontSize: CLType.title),
                decoration:
                    _inputDecoration(p, hint: "Add a message (optional)"),
              ),
              const SizedBox(height: 12),
              CLBtn(
                label: _sending
                    ? "Sending…"
                    : _selected.length > 1
                        ? "Send to ${_selected.length}"
                        : "Send",
                iconL: Icons.send_rounded,
                block: true,
                size: CLBtnSize.lg,
                onPressed: _sending || _selected.isEmpty ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(CLPalette p,
    {required String hint, Widget? prefix}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(CLRadii.md),
    borderSide: BorderSide(color: p.border),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.text3),
    prefixIcon: prefix,
    isDense: true,
    filled: true,
    fillColor: p.input,
    border: border,
    enabledBorder: border,
  );
}

/// A section heading in the picker: "Direct messages", "Group chats", ...
class SendPostSectionLabel extends StatelessWidget {
  final String label;

  const SendPostSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: CLType.meta,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: p.text3,
        ),
      ),
    );
  }
}

/// One destination in the "Send in message" picker - a person, page, group or
/// server channel. Public so the layout can be pinned in a test without the
/// network.
class SendPostOptionRow extends StatelessWidget {
  final SendPostOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const SendPostOptionRow({
    super.key,
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final isPerson = option.target.kind == SendPostTarget.kindEntity;

    final Widget avatar = option.kind == "channel"
        ? Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.goldSoft,
              borderRadius: BorderRadius.circular(CLRadii.sm),
            ),
            child: Icon(Icons.dns_rounded, color: p.goldText, size: 20),
          )
        : CLAvatar(
            id: option.target.id,
            name: option.title,
            src: option.profile,
            // Presence for a person or page only - a group has no entity to
            // be online.
            entityId: isPerson ? option.target.id : null,
            kind: option.kind,
            size: 38,
            cornerRadius: isPerson ? null : CLRadii.sm,
          );

    return Opacity(
      opacity: enabled || selected ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: CLType.title,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    Text(
                      option.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: CLType.meta, color: p.text3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? p.brand : p.border2,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
