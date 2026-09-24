import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:chatterloop_app/views/moments/thoughts.dart';
import 'package:flutter/material.dart';

/// A profile avatar with its Moment ring (design 2h): tapping it opens the
/// entity's live moments. No live moment = the avatar as it was.
class ProfileMomentAvatar extends StatefulWidget {
  final String entityId;
  final double size;
  final Widget child;

  const ProfileMomentAvatar(
      {super.key,
      required this.entityId,
      required this.size,
      required this.child});

  @override
  State<ProfileMomentAvatar> createState() => _ProfileMomentAvatarState();
}

class _ProfileMomentAvatarState extends State<ProfileMomentAvatar> {
  MomentRing? _ring;

  @override
  void initState() {
    super.initState();
    _load();
    EphemeralEvents.moments.addListener(_load);
  }

  @override
  void didUpdateWidget(ProfileMomentAvatar old) {
    super.didUpdateWidget(old);
    if (old.entityId != widget.entityId) _load();
  }

  @override
  void dispose() {
    EphemeralEvents.moments.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final rings = await MomentsApi().getRingsRequest([widget.entityId]);
    if (mounted) setState(() => _ring = rings[widget.entityId]);
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ring;
    if (ring == null) return widget.child;
    return GestureDetector(
      onTap: () =>
          openMoments(context, widget.entityId, postId: ring.startPostId),
      child: MomentRingFrame(
          unseen: ring.hasUnseen, size: widget.size, child: widget.child),
    );
  }
}

/// The entity's live thought, as a bubble beside their profile avatar. Yours
/// opens the editor; anyone else's, react / reply.
class ProfileThoughtBubble extends StatefulWidget {
  final String entityId;

  const ProfileThoughtBubble({super.key, required this.entityId});

  @override
  State<ProfileThoughtBubble> createState() => _ProfileThoughtBubbleState();
}

class _ProfileThoughtBubbleState extends State<ProfileThoughtBubble> {
  Thought? _thought;

  @override
  void initState() {
    super.initState();
    _load();
    EphemeralEvents.thoughts.addListener(_load);
  }

  @override
  void didUpdateWidget(ProfileThoughtBubble old) {
    super.didUpdateWidget(old);
    if (old.entityId != widget.entityId) _load();
  }

  @override
  void dispose() {
    EphemeralEvents.thoughts.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final thoughts = await MomentsApi().getThoughtsRequest([widget.entityId]);
    if (mounted) setState(() => _thought = thoughts[widget.entityId]);
  }

  @override
  Widget build(BuildContext context) {
    final thought = _thought;
    if (thought == null) return const SizedBox.shrink();
    final isSelf = widget.entityId == appStore.state.userAuth.user.entityId;
    return GestureDetector(
      // Opaque: the WHOLE bubble (padding, tail) is the target, not just
      // the painted text inside it.
      behavior: HitTestBehavior.opaque,
      onTap: () => isSelf
          ? showThoughtComposerSheet(context, existing: thought)
          : showThoughtDetailSheet(context, thought: thought),
      child: ThoughtBubble(
        text: thought.text,
        mood: thought.mood,
        meta: ephemeralTimeLeft(thought.expiresAt),
        maxWidth: 160,
      ),
    );
  }
}
