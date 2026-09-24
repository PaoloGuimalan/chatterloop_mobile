import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/moments/moment_shared_post_card.dart';
import 'package:chatterloop_app/views/moments/moment_viewers_sheet.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

/// How long a photo (or a shared post) stays up before the next one.
const _photoDuration = Duration(seconds: 6);

/// One entity's live moments, full screen (design 2b; your own: 2c).
/// Tap the right side for the next, the left for the previous, hold to pause.
/// Someone else's: react and reply (into your DM with them). Yours: who saw
/// it, and its settings.
class MomentViewerScreen extends StatefulWidget {
  final String entityId;
  final String? startPostId;

  /// Plays YOUR expired moments (profile > Archived > Moments), newest
  /// first, from [startPostId]: no hopping to other people, no expiry skip,
  /// and the viewers sheet stays so who saw it is still yours to see.
  final bool archive;

  const MomentViewerScreen(
      {super.key,
      required this.entityId,
      this.startPostId,
      this.archive = false});

  @override
  State<MomentViewerScreen> createState() => _MomentViewerScreenState();
}

class _MomentViewerScreenState extends State<MomentViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: _photoDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _next();
        });

  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  List<Moment>? _moments;
  int _index = 0;
  VideoPlayerController? _video;

  /// The source [_video] was acquired for, to hand back on the way out.
  String? _videoSource;

  /// Controllers come from the app's shared video cache, not a fresh one per
  /// moment: disposing one decoder and starting the next straight away is
  /// what left the new one uninitialised on Android (a video that never
  /// played) - the same trap the post videos avoid this way.
  void _releaseVideo() {
    final source = _videoSource;
    _videoSource = null;
    _video?.pause();
    _video = null;
    if (source != null) {
      SharedVideoControllers.release(source, isLocalFile: false);
    }
  }

  PostPreview? _shared;

  /// The shared post could not be loaded (deleted, or not yours to see).
  bool _sharedGone = false;
  List<Emoji> _palette = const [];
  final Map<String, String?> _myReactions = {};
  bool _sending = false;
  bool _held = false;

  /// Archive mode - from the route, or switched on when a link to one of
  /// YOUR moments finds it already expired (a notification opened late).
  late bool _archive = widget.archive;
  bool _muted = false;

  /// The board's author order, for moving on to the next (or back to the
  /// previous) person's moments like any stories viewer.
  List<MomentTrayEntry> _order = const [];

  /// Your own moment's view count, for the "Viewers" button.
  int? _viewCount;

  bool get _isSelf => widget.entityId == appStore.state.userAuth.user.entityId;

  Moment? get _current {
    final moments = _moments;
    if (moments == null || moments.isEmpty) return null;
    return moments[_index.clamp(0, moments.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _replyFocus.addListener(_syncPause);
    _load();
    if (!_archive) {
      MomentsApi().getTrayRequest().then((tray) {
        if (mounted) _order = tray.results;
      });
    }
    ReactionPalette.load().then((emojis) {
      if (mounted) setState(() => _palette = emojis);
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _releaseVideo();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  /// The archive, paged until the opened moment is in hand (it may be past
  /// the first page if "Load more" was used).
  Future<List<Moment>> _loadArchive() async {
    final moments = <Moment>[];
    for (var page = 1; page <= 10; page++) {
      final result = await MomentsApi().getArchiveRequest(page: page);
      moments.addAll(result.items);
      if (!result.hasMore ||
          moments.any((m) => m.post.postId == widget.startPostId)) {
        break;
      }
    }
    return moments;
  }

  Future<void> _load() async {
    var moments = _archive
        ? await _loadArchive()
        : await MomentsApi().getEntityMomentsRequest(widget.entityId);
    if (!_archive &&
        _isSelf &&
        widget.startPostId != null &&
        !moments.any((m) => m.post.postId == widget.startPostId)) {
      final archived = await _loadArchive();
      if (archived.any((m) => m.post.postId == widget.startPostId)) {
        _archive = true;
        moments = archived;
      }
    }
    if (!mounted) return;
    var start = moments.indexWhere((m) => m.post.postId == widget.startPostId);
    if (start < 0) start = moments.indexWhere((m) => !m.seen);
    setState(() {
      _moments = moments;
      _index = start < 0 ? 0 : start;
      for (final m in moments) {
        _myReactions[m.post.postId] = m.post.entityReaction;
      }
    });
    if (moments.isNotEmpty) _show();
  }

  /// Starts the current moment: media, timer, and "seen".
  Future<void> _show() async {
    final moment = _current;
    if (moment == null) return;
    _progress
      ..stop()
      ..reset();
    _releaseVideo();
    _shared = null;
    _sharedGone = false;

    if (!_isSelf && !moment.seen) {
      MomentsApi().markSeenRequest(EphemeralKind.moment, moment.post.postId);
    }
    _viewCount = null;
    if (_isSelf) {
      MomentsApi()
          .getViewersRequest(EphemeralKind.moment, moment.post.postId)
          .then((viewers) {
        if (mounted && _current == moment) {
          setState(() => _viewCount = viewers.views);
        }
      });
    }

    if (moment.isShared) {
      final id = moment.sharedPostId;
      if (id != null) {
        FeedApi().getPostPreviewRequest(id).then((post) {
          if (!mounted || _current != moment) return;
          setState(() {
            _shared = post;
            _sharedGone = post == null;
          });
        });
      }
      _progress.duration = _photoDuration;
    } else if (moment.media?.isVideo == true) {
      final source = moment.media!.reference;
      final entry = SharedVideoControllers.acquire(source, isLocalFile: false);
      final controller = entry.controller;
      _video = controller;
      _videoSource = source;
      try {
        await entry.ready;
      } catch (_) {}
      if (!mounted || _video != controller) return;
      await controller.seekTo(Duration.zero);
      final length = controller.value.duration;
      _progress.duration = length > Duration.zero ? length : _photoDuration;
      await controller.setVolume(_muted ? 0 : 1);
      controller.play();
    } else {
      _progress.duration = _photoDuration;
    }
    if (!mounted) return;
    setState(() {});
    _syncPause();
  }

  void _syncPause() {
    final paused = _held || _replyFocus.hasFocus;
    if (paused) {
      _progress.stop();
      _video?.pause();
    } else if (_current != null && !_progress.isCompleted) {
      _progress.forward();
      _video?.play();
    }
  }

  void _next() {
    final moments = _moments ?? const [];
    if (_index + 1 >= moments.length) {
      _goToAuthor(1);
      return;
    }
    setState(() => _index++);
    _show();
  }

  void _previous() {
    if (_index == 0) {
      if (!_goToAuthor(-1, closeAtEnd: false)) {
        _progress.forward(from: 0);
        _video?.seekTo(Duration.zero);
      }
      return;
    }
    setState(() => _index--);
    _show();
  }

  /// The next / previous author on the board, replacing this screen so back
  /// still returns to where the viewer was opened from. Past the last one,
  /// the viewer closes. False when there was nowhere to go.
  bool _goToAuthor(int offset, {bool closeAtEnd = true}) {
    if (_archive) {
      // Past the last archived moment: back to the archive grid.
      if (closeAtEnd && offset > 0) _close();
      return false;
    }
    final at = _order.indexWhere((e) => e.author.entityId == widget.entityId);
    final target = at < 0 ? -1 : at + offset;
    if (target < 0 || target >= _order.length) {
      if (closeAtEnd) _close();
      return false;
    }
    final entry = _order[target];
    context.pushReplacement(Uri(
      path: '/moments/${entry.author.entityId}',
      queryParameters: {'post': entry.startPostId},
    ).toString());
    return true;
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _video?.setVolume(_muted ? 0 : 1);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/newsfeed');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _react(Emoji emoji) async {
    final moment = _current;
    if (moment == null) return;
    final id = moment.post.postId;
    final before = _myReactions[id];
    final method =
        reactionMethodFor(currentEmojiId: before, tappedEmojiId: emoji.emojiId);
    setState(() => _myReactions[id] =
        method == ReactionMethod.remove ? null : emoji.emojiId);
    final ok = await NewsfeedApi().setPostReactionRequest(
        postId: id, emojiId: emoji.emojiId, method: method);
    if (!ok && mounted) {
      setState(() => _myReactions[id] = before);
      _toast("Couldn't save that reaction.");
    }
  }

  Future<void> _sendReply() async {
    final moment = _current;
    final text = _reply.text.trim();
    if (moment == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await MomentsApi().sendReplyRequest(
      authorEntityId: widget.entityId,
      kind: EphemeralKind.moment,
      postId: moment.post.postId,
      content: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      _toast(error);
      return;
    }
    _reply.clear();
    _replyFocus.unfocus();
    _toast("Reply sent to ${moment.post.author.displayName.split(" ").first}");
  }

  /// Back on the board until its natural end - and out of the archive being
  /// played.
  Future<void> _unarchiveCurrent() async {
    final moment = _current;
    if (moment == null) return;
    final ok = await MomentsApi()
        .updateMomentRequest(moment.post.postId, archive: false);
    if (!mounted) return;
    if (!ok) {
      _toast("Couldn't unarchive that moment.");
      return;
    }
    _toast("Moment is back on your board");
    EphemeralEvents.moments.value++;
    final moments = [...?_moments]..removeAt(_index);
    if (moments.isEmpty) {
      _close();
      return;
    }
    setState(() {
      _moments = moments;
      _index = _index.clamp(0, moments.length - 1);
    });
    _show();
  }

  Future<void> _openViewers() async {
    final moment = _current;
    if (moment == null) return;
    _held = true;
    _syncPause();
    final outcome = await showMomentViewersSheet(context,
        moment: moment, archived: _archive);
    if (!mounted) return;
    _held = false;
    if (outcome == MomentSheetOutcome.unarchived && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Moment is back on your board"),
          duration: Duration(seconds: 2)));
    }
    if (outcome == MomentSheetOutcome.deleted ||
        outcome == MomentSheetOutcome.archived ||
        outcome == MomentSheetOutcome.unarchived) {
      EphemeralEvents.moments.value++;
      final moments = [...?_moments]..removeAt(_index);
      if (moments.isEmpty) {
        _close();
        return;
      }
      setState(() {
        _moments = moments;
        _index = _index.clamp(0, moments.length - 1);
      });
      _show();
      return;
    }
    if (outcome == MomentSheetOutcome.changed) _load();
    _syncPause();
  }

  @override
  Widget build(BuildContext context) {
    final moment = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _moments == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : moment == null
                ? _gone()
                : Column(
                    children: [
                      Expanded(child: _stage(moment)),
                      _bottom(moment),
                    ],
                  ),
      ),
    );
  }

  Widget _gone() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_outlined, color: Colors.white70, size: 40),
          const SizedBox(height: 10),
          const Text("This moment is no longer available",
              style: TextStyle(color: Colors.white, fontSize: CLType.body)),
          const SizedBox(height: 14),
          CLBtn(label: "Close", variant: CLBtnVariant.soft, onPressed: _close),
        ],
      ),
    );
  }

  Widget _stage(Moment moment) {
    final author = moment.post.author;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        details.globalPosition.dx < width / 3 ? _previous() : _next();
      },
      onLongPressStart: (_) {
        _held = true;
        _syncPause();
      },
      onLongPressEnd: (_) {
        _held = false;
        _syncPause();
      },
      // Swipe down to dismiss; swipe sideways to change person.
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 400) _close();
      },
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -300) _goToAuthor(1);
        if (v > 300) _goToAuthor(-1, closeAtEnd: false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: _media(moment)),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 8,
            child: Column(
              children: [
                _bars(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CLAvatar(
                      id: author.entityId,
                      name: author.displayName,
                      src: author.profile,
                      size: 34,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isSelf ? "Your moment" : author.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: CLType.body,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              [
                                if (_isSelf)
                                  moment.post.privacyStatus == "connections"
                                      ? "Contacts"
                                      : "Public",
                                if (moment.isShared) "shared a post",
                                ephemeralTimeAgo(moment.post.datePosted),
                                _archive
                                    ? _archivedOn(moment)
                                    : ephemeralTimeLeft(moment.expiresAt),
                              ].where((s) => s.isNotEmpty).join(" · "),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: CLType.meta)),
                        ],
                      ),
                    ),
                    if (moment.media?.isVideo == true && !moment.isShared)
                      IconButton(
                        onPressed: _toggleMute,
                        tooltip: _muted ? "Unmute" : "Mute",
                        icon: Icon(
                            _muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white),
                      ),
                    IconButton(
                      onPressed: _close,
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (moment.post.caption.trim().isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Text(
                moment.post.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: CLType.title,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bars() {
    final count = _moments?.length ?? 0;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i == count - 1 ? 0 : 3),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: i < _index
                      ? 1
                      : i == _index
                          ? _progress.value
                          : 0,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _media(Moment moment) {
    if (moment.isShared) return _sharedCard(moment);
    final media = moment.media;
    if (media == null) return const SizedBox.shrink();
    if (media.isVideo) {
      final video = _video;
      if (video == null || !video.value.isInitialized) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return AspectRatio(
          aspectRatio: video.value.aspectRatio, child: VideoPlayer(video));
    }
    return CLNetworkImage(src: media.reference, fit: BoxFit.contain);
  }

  /// A shared-post moment: the post as a card - its video playing, and the
  /// original nested when the post is itself a share (MomentSharedPostCard).
  /// Scaled down, never overflowing, when a tall card meets a short screen.
  Widget _sharedCard(Moment moment) {
    final p = cl(context);
    final post = _shared;
    Widget child;
    if (post != null) {
      child = MomentSharedPostCard(
        post: post,
        mediaHeight: 220,
        onOpen: () => context.push('/post/${post.postId}'),
      );
    } else if (_sharedGone) {
      child = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: p.surface, borderRadius: BorderRadius.circular(CLRadii.md)),
        child: Text("This post is no longer available.",
            style: TextStyle(fontSize: CLType.body, color: p.text2)),
      );
    } else {
      child = const SizedBox(
          height: 140,
          child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(width: constraints.maxWidth - 48, child: child),
      ),
    );
  }

  Widget _bottom(Moment moment) {
    if (_isSelf) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _openViewers,
              icon: const Icon(Icons.visibility_outlined, color: Colors.white),
              label: Text(
                  _viewCount == null
                      ? "Viewers"
                      : "$_viewCount ${_viewCount == 1 ? "viewer" : "viewers"}",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: CLType.body,
                      fontWeight: FontWeight.w600)),
            ),
            if (_archive && moment.canUnarchive)
              TextButton.icon(
                onPressed: _unarchiveCurrent,
                icon: const Icon(Icons.unarchive_outlined, color: Colors.white),
                label: const Text("Unarchive",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: CLType.body,
                        fontWeight: FontWeight.w700)),
              ),
            const Spacer(),
            IconButton(
              onPressed: _openViewers,
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
            ),
          ],
        ),
      );
    }

    final mine = _myReactions[moment.post.postId];
    final first = moment.post.author.displayName.split(" ").first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (moment.allowReplies && _palette.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final emoji in _palette.take(6))
                    GestureDetector(
                      onTap: () => _react(emoji),
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: mine == emoji.emojiId
                              ? Colors.white30
                              : Colors.white10,
                          border: Border.all(
                              color: mine == emoji.emojiId
                                  ? Colors.white
                                  : Colors.white24),
                        ),
                        child: Text(emoji.content,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
          if (moment.allowReplies)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    focusNode: _replyFocus,
                    enabled: !_sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendReply(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: CLType.body),
                    decoration: InputDecoration(
                      hintText: "Reply to $first…",
                      hintStyle: const TextStyle(color: Colors.white60),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.pill),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.pill),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _sendReply,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text("Replies are off for this moment",
                  style: TextStyle(
                      color: Colors.white60, fontSize: CLType.caption)),
            ),
        ],
      ),
    );
  }
}

const _monthNames = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

/// "Archived · Sep 24" - an archived moment's header, in place of time left.
String _archivedOn(Moment moment) {
  // Archived by hand with time left: say how long it could still come back.
  if (moment.canUnarchive) {
    return "Archived · ${ephemeralTimeLeft(moment.naturalEnd)}";
  }
  final date = moment.post.datePosted?.toLocal();
  return date == null
      ? "Archived"
      : "Archived · ${_monthNames[date.month - 1]} ${date.day}";
}
