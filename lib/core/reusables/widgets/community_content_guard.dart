import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';

/// Cached previews must establish current access before displaying content.
class CommunityContentGuard extends StatefulWidget {
  final String postId;
  final Community? community;
  final Widget child;

  const CommunityContentGuard(
      {super.key,
      required this.postId,
      required this.community,
      required this.child});

  @override
  State<CommunityContentGuard> createState() => _CommunityContentGuardState();
}

class _CommunityContentGuardState extends State<CommunityContentGuard> {
  late bool _allowed = widget.community == null;
  late String _actor = appStore.state.userAuth.user.entityId;
  StreamSubscription? _identity;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    communityChanges.addListener(_refresh);
    _identity = appStore.onChange.listen((_) {
      final actor = appStore.state.userAuth.user.entityId;
      if (actor == _actor) return;
      _actor = actor;
      _refresh();
    });
    _refresh();
  }

  void _refresh() {
    final generation = ++_generation;
    if (widget.community == null) {
      if (!_allowed) setState(() => _allowed = true);
      return;
    }
    setState(() => _allowed = false);
    FeedApi().getPostPreviewRequest(widget.postId).then((post) {
      if (!mounted || generation != _generation) return;
      setState(() => _allowed = post != null &&
          (post.community == null ||
              !post.community!.isPrivate ||
              post.community!.isMember));
    });
  }

  @override
  void didUpdateWidget(CommunityContentGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId ||
        oldWidget.community?.entityId != widget.community?.entityId ||
        oldWidget.community?.isPrivate != widget.community?.isPrivate ||
        oldWidget.community?.isMember != widget.community?.isMember) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    _identity?.cancel();
    communityChanges.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _allowed ? widget.child : const SizedBox.shrink();
}
