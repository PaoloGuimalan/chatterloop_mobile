import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:chatterloop_app/views/moments/reaction_burst.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A thought as a bubble above an avatar (rail, profile).
class ThoughtBubble extends StatelessWidget {
  final String text;
  final String? mood;
  final String? meta;
  final bool small;
  final bool muted;
  final double maxWidth;

  const ThoughtBubble({
    super.key,
    required this.text,
    this.mood,
    this.meta,
    this.small = false,
    this.muted = false,
    this.maxWidth = 170,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final m = thoughtMoodOf(mood);
    Widget dot(double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: p.surface,
            shape: BoxShape.circle,
            border: Border.all(color: p.border),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: EdgeInsets.symmetric(
              horizontal: small ? 8 : 12, vertical: small ? 5 : 8),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(small ? 14 : 16),
            border: Border.all(color: p.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                small ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: small ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: small ? CLType.meta : CLType.bodySm,
                  fontWeight: small ? FontWeight.w500 : FontWeight.w600,
                  color: muted ? p.text3 : p.text,
                  height: 1.25,
                ),
              ),
              if (!small && (m != null || meta != null)) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m != null) ...[
                      Icon(m.icon, size: 12, color: p.text3),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      [m?.label, meta].whereType<String>().join(" · "),
                      style: TextStyle(fontSize: CLType.meta, color: p.text3),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 1),
          child: dot(7),
        ),
        Padding(padding: const EdgeInsets.only(left: 10), child: dot(4)),
      ],
    );
  }
}

/// The Thoughts rail at the top of Messages (design 2e): your thought first
/// (edit / add), then your circle's, newest first.
class ThoughtsRailView extends StatefulWidget {
  const ThoughtsRailView({super.key});

  @override
  State<ThoughtsRailView> createState() => ThoughtsRailViewState();
}

/// Public so the Messages screen can hold a key to it and fold the rail into
/// its pull-to-refresh - see [refresh].
class ThoughtsRailViewState extends State<ThoughtsRailView> {
  ThoughtsRail? _rail;

  /// Reloads the rail, for a pull-to-refresh to wait on. The rail otherwise
  /// only reloads when your own thought changes (EphemeralEvents.thoughts),
  /// so the latest from everyone else waits for this.
  Future<void> refresh() => _load();

  @override
  void initState() {
    super.initState();
    _load();
    EphemeralEvents.thoughts.addListener(_load);
  }

  @override
  void dispose() {
    EphemeralEvents.thoughts.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final rail = await MomentsApi().getThoughtsRailRequest();
    if (mounted) setState(() => _rail = rail);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final rail = _rail;
    if (rail == null) return const _ThoughtsRailSkeleton();

    // Everyone you are connected to - people and pages - after the
    // thoughts: online first, then the server's rank within each group.
    final presence = appStore.state.presence;
    final withThought = {
      for (final t in rail.results) t.author?.entityId ?? t.entityId
    };
    final connections =
        rail.suggestions.where((a) => !withThought.contains(a.entityId));
    final people = [
      ...connections.where((a) => presence[a.entityId]?.online == true),
      ...connections.where((a) => presence[a.entityId]?.online != true),
    ];
    final user = appStore.state.userAuth.user;

    Widget item({
      required String? bubble,
      bool muted = false,
      required Widget avatar,
      required String label,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 78,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: _railBubbleRoom),
                  avatar,
                  const SizedBox(height: 4),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: CLType.meta, color: p.text2)),
                ],
              ),
              // Pinned to the top and painted over the avatar, so a thought
              // never makes the rail taller - a longer one reaches further
              // down instead.
              if (bubble != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    // 72 inside a 78 slot: 6px between neighbouring bubbles,
                    // so two thoughts side by side never run into each other.
                    child: ThoughtBubble(
                        text: bubble, small: true, muted: muted, maxWidth: 72),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // A fixed room above every avatar, the same whatever the thoughts say:
    // it used to be a band sized by the tallest bubble, which grew with the
    // longest thought and sat empty over everyone without one.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          item(
            bubble: rail.mine?.text ?? "Share a thought",
            muted: rail.mine == null,
            avatar: Stack(
              clipBehavior: Clip.none,
              children: [
                CLAvatar(
                    id: user.entityId,
                    name: user.activeEntity?.name ?? user.personalDisplayName,
                    src: user.activeEntity?.profile ?? user.profile,
                    size: 52),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: p.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                    ),
                    child: Icon(
                        rail.mine == null
                            ? Icons.add_rounded
                            : Icons.edit_rounded,
                        size: 12,
                        color: p.text2),
                  ),
                ),
              ],
            ),
            label: "Your thought",
            onTap: () => showThoughtComposerSheet(context, existing: rail.mine),
          ),
          for (final thought in rail.results)
            item(
              bubble: thought.text,
              avatar: CLAvatar(
                id: thought.author?.entityId ?? thought.entityId,
                entityId: thought.author?.entityId ?? thought.entityId,
                name: thought.author?.displayName,
                src: thought.author?.profile,
                size: 52,
              ),
              label: (thought.author?.displayName ?? "").split(" ").first,
              onTap: () => showThoughtDetailSheet(context, thought: thought),
            ),
          for (final person in people)
            item(
              bubble: null,
              avatar: CLAvatar(
                id: person.entityId,
                entityId: person.entityId,
                name: person.displayName,
                src: person.profile,
                size: 52,
              ),
              label: person.displayName.split(" ").first,
              onTap: () => _openChat(context, person.entityId),
            ),
        ],
      ),
    );
  }
}

Future<void> _sheet(BuildContext context, Widget child) {
  final p = cl(context);
  return showModalBottomSheet<void>(
    context: context,
    // Over the WHOLE screen, like the post composer - from a tab (Messages)
    // the default nested navigator drew it inside that tab, under the bar.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CLRadii.lg))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
              clSheetBottomGap(sheetContext, minimum: 16, extra: 8)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: child,
      ),
    ),
  );
}

Widget _grabber(CLPalette p) => Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
            color: p.border2,
            borderRadius: BorderRadius.circular(CLRadii.pill)),
      ),
    );

/// Someone else's thought (Moments polish 1c): the bubble over its author,
/// then react, or reply into your chat.
Future<void> showThoughtDetailSheet(BuildContext context,
        {required Thought thought}) =>
    _sheet(context, _ThoughtDetail(thought: thought));

class _ThoughtDetail extends StatefulWidget {
  final Thought thought;

  const _ThoughtDetail({required this.thought});

  @override
  State<_ThoughtDetail> createState() => _ThoughtDetailState();
}

class _ThoughtDetailState extends State<_ThoughtDetail> {
  final _reply = TextEditingController();
  List<Emoji> _palette = const [];
  late String? _mine = widget.thought.myReaction;
  bool _sending = false;

  /// Reactions made here, counted to play the burst again.
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    MomentsApi().markSeenRequest(EphemeralKind.thought, widget.thought.postId);
    ReactionPalette.load().then((emojis) {
      if (mounted) setState(() => _palette = emojis);
    });
    // The send button lights up once there is something to send.
    _reply.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  String get _first =>
      (widget.thought.author?.displayName ?? "them").split(" ").first;

  String? get _mineGlyph {
    final id = _mine;
    if (id == null) return null;
    for (final emoji in _palette) {
      if (emoji.emojiId == id) return emoji.content;
    }
    return ReactionPalette.glyphFor(id);
  }

  /// One reaction per thought: the first tap sends it; tapping it again only
  /// plays the burst again; the others are locked once one is chosen.
  Future<void> _react(Emoji emoji) async {
    final before = _mine;
    if (before != null && before != emoji.emojiId) return;
    setState(() {
      _mine = emoji.emojiId;
      _burst++;
    });
    if (before != null) return;
    final ok = await NewsfeedApi().setPostReactionRequest(
        postId: widget.thought.postId,
        emojiId: emoji.emojiId,
        method: ReactionMethod.add);
    if (!ok && mounted) setState(() => _mine = before);
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await MomentsApi().sendReplyRequest(
      authorEntityId:
          widget.thought.author?.entityId ?? widget.thought.entityId,
      kind: EphemeralKind.thought,
      postId: widget.thought.postId,
      content: text,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
        content: Text("Reply sent to $_first"),
        duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final thought = widget.thought;
    final author = thought.author;
    final mood = thoughtMoodOf(thought.mood);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = _mineGlyph;
    final ready = _reply.text.trim().isNotEmpty && !_sending;

    Widget dot(double size, double shift, double gap) => Transform.translate(
          offset: Offset(shift, 0),
          child: Container(
            width: size,
            height: size,
            margin: EdgeInsets.only(top: gap),
            decoration: BoxDecoration(
              color: p.surface,
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grabber(p),
        // The thought as the rail shows it - a bubble over its author - so
        // opening one reads as the same thing, larger.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(CLRadii.lg),
          ),
          child: Column(
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 270),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.border),
                  boxShadow: [
                    BoxShadow(
                        color: dark
                            ? const Color(0x59000000)
                            : const Color(0x14000000),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(thought.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: CLType.screenTitle,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                            height: 1.35)),
                    if (mood != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                        decoration: BoxDecoration(
                          color: mood.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(CLRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(mood.icon, size: 13, color: mood.color),
                            const SizedBox(width: 4),
                            Text(mood.label,
                                style: TextStyle(
                                    fontSize: CLType.meta,
                                    fontWeight: FontWeight.w700,
                                    color: mood.color)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              dot(9, -12, 3),
              dot(5, -18, 2),
              const SizedBox(height: 4),
              CLAvatar(
                id: author?.entityId ?? thought.entityId,
                entityId: author?.entityId ?? thought.entityId,
                name: author?.displayName,
                src: author?.profile,
                size: 64,
              ),
              const SizedBox(height: 10),
              Text(author?.displayName ?? "",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: CLType.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
              const SizedBox(height: 2),
              Text(
                  "${ephemeralTimeAgo(thought.datePosted)} · ${ephemeralTimeLeft(thought.expiresAt)}",
                  style: TextStyle(fontSize: CLType.meta, color: p.text3)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_palette.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, emoji) in _palette.take(6).indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                _reaction(p, emoji),
              ],
            ],
          ),
        const SizedBox(height: 14),
        // The field, with send inside it.
        Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(16, 0, 5, 0),
          decoration: BoxDecoration(
            color: p.input,
            borderRadius: BorderRadius.circular(CLRadii.pill),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  enabled: !_sending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: p.text, fontSize: CLType.title),
                  decoration: InputDecoration.collapsed(
                    hintText: "Reply to $_first…",
                    hintStyle:
                        TextStyle(color: p.text3, fontSize: CLType.title),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: "Send reply",
                child: GestureDetector(
                  onTap: ready ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? p.brand : p.surface3,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.send_rounded,
                            size: 18, color: ready ? Colors.white : p.text3),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                mine != null
                    ? Icons.check_circle_rounded
                    : Icons.lock_outline_rounded,
                size: 14,
                color: mine != null ? p.brand : p.text3),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                  mine != null
                      ? "You reacted $mine · $_first will see it"
                      : "Replies go to your chat with $_first.",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: CLType.caption,
                      fontWeight:
                          mine != null ? FontWeight.w600 : FontWeight.w400,
                      color: mine != null ? p.brand : p.text3)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reaction(CLPalette p, Emoji emoji) {
    final chosen = _mine == emoji.emojiId;
    final locked = _mine != null && !chosen;
    return Semantics(
      button: true,
      label: "React ${emoji.content}",
      excludeSemantics: true,
      child: GestureDetector(
        onTap: locked ? null : () => _react(emoji),
        child: AnimatedOpacity(
          opacity: locked ? 0.35 : 1,
          duration: const Duration(milliseconds: 250),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chosen ? p.brandSoft : p.surface2,
              border: Border.all(color: chosen ? p.brand : Colors.transparent),
            ),
            child: chosen
                ? ReactionBurst(
                    emoji: emoji.content,
                    size: 20,
                    ringColor: p.brand,
                    burst: _burst)
                : Text(emoji.content,
                    style: const TextStyle(fontSize: 20, height: 1)),
          ),
        ),
      ),
    );
  }
}

/// Share or edit your thought (design 2g). Editing keeps its timer and
/// views, and offers Delete.
Future<void> showThoughtComposerSheet(BuildContext context,
        {Thought? existing}) =>
    _sheet(context, _ThoughtComposer(existing: existing));

class _ThoughtComposer extends StatefulWidget {
  final Thought? existing;

  const _ThoughtComposer({this.existing});

  @override
  State<_ThoughtComposer> createState() => _ThoughtComposerState();
}

class _ThoughtComposerState extends State<_ThoughtComposer> {
  late final _text = TextEditingController(text: widget.existing?.text ?? "");
  late String? _mood = widget.existing?.mood;
  late String _audience = widget.existing?.privacyStatus == "connections"
      ? "connections"
      : widget.existing != null
          ? "public"
          : (appStore.state.userAuth.user.isPrivate == true
              ? "connections"
              : "public");
  int? _views;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    final existing = widget.existing;
    if (existing != null) {
      MomentsApi().getOwnThoughtRequest(existing.postId).then((t) {
        if (mounted && t != null) setState(() => _views = t.views ?? 0);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _count => ephemeralCharCount(_text.text.trim());

  void _done(String message) {
    EphemeralEvents.thoughts.value++;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _save() async {
    if (_busy || _count == 0 || _count > thoughtMaxLength) return;
    setState(() => _busy = true);
    final existing = widget.existing;
    final error = existing == null
        ? await MomentsApi().createThoughtRequest(
            text: _text.text.trim(), mood: _mood, privacy: _audience)
        : await MomentsApi().updateThoughtRequest(existing.postId,
            text: _text.text.trim(), mood: _mood, privacy: _audience);
    if (!mounted) return;
    if (error != null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _done(existing == null
        ? "Your thought is up for 24 hours"
        : "Thought updated");
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _busy) return;
    setState(() => _busy = true);
    final ok = await NewsfeedApi().deletePostRequest(existing.postId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete your thought.")));
      return;
    }
    _done("Thought deleted");
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final user = appStore.state.userAuth.user;
    final existing = widget.existing;
    final label = TextStyle(
        fontSize: CLType.meta, fontWeight: FontWeight.w700, color: p.text3);
    final tooLong = _count > thoughtMaxLength;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grabber(p),
        Text(existing == null ? "Share a thought" : "Your thought",
            style: TextStyle(
                fontSize: CLType.sectionTitle,
                fontWeight: FontWeight.w800,
                color: p.text)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(CLRadii.md),
          ),
          child: Column(
            children: [
              ThoughtBubble(
                text: _text.text.trim().isEmpty
                    ? "What's on your mind?"
                    : _text.text.trim(),
                mood: _mood,
                muted: _text.text.trim().isEmpty,
                maxWidth: 240,
              ),
              CLAvatar(
                  id: user.entityId,
                  name: user.activeEntity?.name ?? user.personalDisplayName,
                  src: user.activeEntity?.profile ?? user.profile,
                  size: 64),
              if (existing != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.brandSoft,
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                  ),
                  child: Text(
                    [
                      ephemeralTimeLeft(existing.expiresAt),
                      if (_views != null) "seen by $_views",
                    ].join(" · "),
                    style: TextStyle(
                        fontSize: CLType.meta,
                        fontWeight: FontWeight.w700,
                        color: p.brand),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          enabled: !_busy,
          autofocus: existing == null,
          style: TextStyle(color: p.text, fontSize: CLType.title),
          decoration: InputDecoration(
            hintText: "Share a thought…",
            hintStyle: TextStyle(color: p.text3),
            suffixText: "$_count/$thoughtMaxLength",
            suffixStyle: TextStyle(color: tooLong ? p.pink : p.text3),
            filled: true,
            fillColor: p.input,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CLRadii.md),
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CLRadii.md),
              borderSide: BorderSide(color: tooLong ? p.pink : p.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final emoji in thoughtEmojis)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (ephemeralCharCount(_text.text) >= thoughtMaxLength) {
                      return;
                    }
                    _text.text = "${_text.text}$emoji";
                    _text.selection =
                        TextSelection.collapsed(offset: _text.text.length);
                  },
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(CLRadii.xs),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text("MOOD", style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mood in thoughtMoods)
              CLChip(
                label: mood.label,
                icon: mood.icon,
                active: _mood == mood.key,
                onTap: () =>
                    setState(() => _mood = _mood == mood.key ? null : mood.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
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
                  onTap: () => setState(() => _audience = a.key),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (existing != null) ...[
          CLBtn(
            label: "Delete thought",
            iconL: Icons.delete_outline_rounded,
            variant: CLBtnVariant.soft,
            block: true,
            onPressed: _busy ? null : _delete,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: p.text3),
            const SizedBox(width: 6),
            Expanded(
              child: Text("Disappears after 24 hours. Not shown in the feed.",
                  style: TextStyle(fontSize: CLType.caption, color: p.text2)),
            ),
            const SizedBox(width: 8),
            CLBtn(
              label: existing == null ? "Share" : "Update",
              onPressed: _busy || _count == 0 || tooLong ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _openChat(BuildContext context, String entityId) async {
  final conversationId =
      await ConversationsApi().createInitialConversationRequest(entityId);
  if (conversationId == null || conversationId.isEmpty || !context.mounted) {
    return;
  }
  context.push('/conversation/$conversationId');
}

/// The room every rail item keeps above its avatar, with the thought pinned
/// to the top of it. Sized so a two-line thought ("Share a thought") ends
/// just above the avatar's middle; a longer one grows DOWN over the avatar
/// rather than making the rail taller.
const double _railBubbleRoom = 28;

/// The rail while it loads: bubble, avatar, name per person - shaped like the
/// loaded rail, a thought pinned over each avatar's top.
class _ThoughtsRailSkeleton extends StatelessWidget {
  const _ThoughtsRailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 5; i++)
            const SizedBox(
              width: 78,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: _railBubbleRoom),
                      CLSkeleton(
                          width: 52,
                          height: 52,
                          borderRadius: BorderRadius.all(Radius.circular(26))),
                      SizedBox(height: 6),
                      CLSkeleton(width: 44, height: 10),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: CLSkeleton(
                          width: 60,
                          height: 28,
                          borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
