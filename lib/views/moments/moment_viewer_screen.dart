import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/feed_api.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/gallery_saver.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/moments/moment_shared_post_card.dart';
import 'package:chatterloop_app/views/moments/moment_viewers_sheet.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:chatterloop_app/views/moments/reaction_burst.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

/// How long a photo (or a shared post) stays up before the next one.
const _photoDuration = Duration(seconds: 6);

/// How long the reactions tray stays out after you react, so you see it land.
const _trayLinger = Duration(milliseconds: 1400);

// The see-through whites the controls are drawn in, over the media.
const _white75 = Color(0xBFFFFFFF);
const _white62 = Color(0x9EFFFFFF);
const _glassFill = Color(0x1AFFFFFF);
const _glassEdge = Color(0x47FFFFFF);
const _textShadow = [
  Shadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 1))
];

/// One entity's live moments, full screen (Moments polish 1a; your own: 1b).
/// Tap the right side for the next, the left for the previous, hold to pause.
/// Someone else's: react and reply (into your DM with them). Yours: who saw
/// it, and its settings - swipe up, or the viewers pill.
///
/// The media runs under the whole screen, status bar included, with soft
/// shades top and bottom for the controls to sit on - rather than above a
/// black band of controls.
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

  /// The NEXT moment's video, loading while this one plays - so moving on
  /// starts it at once, like any stories viewer.
  String? _preloadSource;

  void _preloadNext() {
    final moments = _moments ?? const <Moment>[];
    final next = _index + 1 < moments.length ? moments[_index + 1] : null;
    final source = next != null && !next.isShared && next.media?.isVideo == true
        ? next.media!.reference
        : null;
    if (source == _preloadSource) return;
    final old = _preloadSource;
    _preloadSource = source;
    // Take the new one before letting the old go: when the old one is the
    // video now showing, it must never drop to zero viewers in between.
    if (source != null) {
      SharedVideoControllers.acquire(source, isLocalFile: false);
    }
    if (old != null) SharedVideoControllers.release(old, isLocalFile: false);
  }

  void _releasePreload() {
    final source = _preloadSource;
    _preloadSource = null;
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

  /// The reactions tray (someone else's moment) is out.
  bool _trayOpen = false;
  Timer? _trayTimer;

  /// Reactions made here, counted to play the burst again.
  int _burst = 0;

  /// Archive mode - from the route, or switched on when a link to one of
  /// YOUR moments finds it already expired (a notification opened late).
  late bool _archive = widget.archive;
  bool _muted = false;

  /// The board's author order, for moving on to the next (or back to the
  /// previous) person's moments like any stories viewer.
  List<MomentTrayEntry> _order = const [];

  /// Your own moment's viewers - the count, the reactions and replies, and
  /// the first faces, for the viewers pill.
  EphemeralViewers? _viewers;

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
    // The send button lights up once there is something to send.
    _reply.addListener(() => setState(() {}));
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
    _trayTimer?.cancel();
    _progress.dispose();
    _releaseVideo();
    _releasePreload();
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

  /// Counts [_show] calls, so a video that finishes loading after the viewer
  /// has moved on knows it is no longer wanted.
  int _showCount = 0;

  /// Starts the current moment: media, timer, and "seen".
  Future<void> _show() async {
    final moment = _current;
    if (moment == null) return;
    final shown = ++_showCount;
    _progress
      ..stop()
      ..reset();
    _releaseVideo();
    _shared = null;
    _sharedGone = false;
    _trayTimer?.cancel();
    _trayOpen = false;

    if (!_isSelf && !moment.seen) {
      MomentsApi().markSeenRequest(EphemeralKind.moment, moment.post.postId);
    }
    _viewers = null;
    if (_isSelf) {
      MomentsApi()
          .getViewersRequest(EphemeralKind.moment, moment.post.postId)
          .then((viewers) {
        if (mounted && _current == moment) {
          setState(() => _viewers = viewers);
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
      _preloadNext();
    } else if (moment.media?.isVideo == true) {
      final source = moment.media!.reference;
      final entry = SharedVideoControllers.acquire(source, isLocalFile: false);
      _videoSource = source;
      // Already loading (or loaded) when it was the preloaded next one.
      _preloadNext();
      try {
        await entry.ready;
      } catch (_) {}
      // Moved on while it loaded.
      if (!mounted || shown != _showCount) return;
      // Read only now: a first attempt that failed is replaced by a fresh
      // controller before `ready` settles.
      final controller = entry.controller;
      _video = controller;
      await controller.seekTo(Duration.zero);
      final length = controller.value.duration;
      _progress.duration = length > Duration.zero ? length : _photoDuration;
      await controller.setVolume(_muted ? 0 : 1);
      controller.play();
    } else {
      _progress.duration = _photoDuration;
      _preloadNext();
    }
    if (!mounted) return;
    setState(() {});
    _syncPause();
  }

  /// Held, typing a reply, or choosing a reaction: the moment waits.
  void _syncPause() {
    final paused = _held || _replyFocus.hasFocus || _trayOpen;
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

  void _toggleTray() {
    _trayTimer?.cancel();
    setState(() => _trayOpen = !_trayOpen);
    _syncPause();
  }

  /// One reaction per moment: the first tap sends it; tapping it again only
  /// plays the burst again; the others are locked once one is chosen.
  Future<void> _react(Emoji emoji) async {
    final moment = _current;
    if (moment == null) return;
    final id = moment.post.postId;
    final before = _myReactions[id];
    if (before != null && before != emoji.emojiId) return;
    setState(() {
      _myReactions[id] = emoji.emojiId;
      _burst++;
    });
    // Tucked away once you have seen it land.
    _trayTimer?.cancel();
    _trayTimer = Timer(_trayLinger, () {
      if (!mounted) return;
      setState(() => _trayOpen = false);
      _syncPause();
    });
    if (before != null) return;
    final ok = await NewsfeedApi().setPostReactionRequest(
        postId: id, emojiId: emoji.emojiId, method: ReactionMethod.add);
    if (!ok && mounted) {
      setState(() => _myReactions[id] = before);
      _toast("Couldn't save that reaction.");
    }
  }

  String? _glyphFor(String? emojiId) {
    if (emojiId == null) return null;
    for (final emoji in _palette) {
      if (emoji.emojiId == emojiId) return emoji.content;
    }
    return ReactionPalette.glyphFor(emojiId);
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
    final mq = MediaQuery.of(context);
    // Over the keyboard while typing a reply; otherwise clear of the home
    // indicator. The media itself does not move - the screen is not resized.
    final keyboard = mq.viewInsets.bottom;
    final bottom = keyboard > 0 ? keyboard + 10 : mq.padding.bottom + 16;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: _moments == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : moment == null
              ? SafeArea(child: _gone())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: _stage(moment)),
                    // Soft shades for the controls to read on, whatever the
                    // picture is - not bands.
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 170,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x8C000000), Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _isSelf ? 260 : 340,
                      child: const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xC7000000), Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      top: mq.padding.top + 6,
                      child: _header(moment),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: bottom,
                      child:
                          _isSelf ? _selfPanel(moment) : _othersPanel(moment),
                    ),
                  ],
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

  /// The media, and the gestures that move through it.
  Widget _stage(Moment moment) {
    final mq = MediaQuery.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        // A tap on the picture while typing just puts the keyboard away.
        if (_replyFocus.hasFocus) {
          _replyFocus.unfocus();
          return;
        }
        final width = mq.size.width;
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
      // Down to dismiss; up (yours) for who saw it; sideways to change person.
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 400) _close();
        if (v < -400 && _isSelf) _openViewers();
      },
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -300) _goToAuthor(1);
        if (v > 300) _goToAuthor(-1, closeAtEnd: false);
      },
      child: moment.isShared
          // A shared post is a card, kept clear of the controls above and
          // below it.
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                  0, mq.padding.top + 72, 0, mq.padding.bottom + 150),
              child: Center(child: _sharedCard(moment)),
            )
          : _media(moment),
    );
  }

  Widget _header(Moment moment) {
    final author = moment.post.author;
    return Column(
      children: [
        _bars(),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xEBFFFFFF), width: 2),
              ),
              alignment: Alignment.center,
              child: CLAvatar(
                id: author.entityId,
                name: author.displayName,
                src: author.profile,
                size: 30,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: _isSelf ? _selfTitle(moment) : _othersTitle(moment)),
            if (moment.media?.isVideo == true && !moment.isShared) ...[
              _GlassCircle(
                icon:
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                tooltip: _muted ? "Unmute" : "Mute",
                onTap: _toggleMute,
              ),
              const SizedBox(width: 8),
            ],
            _GlassCircle(
                icon: Icons.close_rounded, tooltip: "Close", onTap: _close),
          ],
        ),
      ],
    );
  }

  Widget _othersTitle(Moment moment) {
    final author = moment.post.author;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(author.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.title,
                      fontWeight: FontWeight.w700,
                      shadows: _textShadow)),
            ),
            const SizedBox(width: 6),
            Text(ephemeralTimeAgo(moment.post.datePosted),
                style: const TextStyle(
                    color: _white75,
                    fontSize: CLType.caption,
                    shadows: _textShadow)),
          ],
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Icon(moment.isShared ? Icons.repeat_rounded : Icons.timer_outlined,
                size: 12, color: _white75),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                  [
                    if (moment.isShared) "Shared a post",
                    ephemeralTimeLeft(moment.expiresAt),
                  ].where((s) => s.isNotEmpty).join(" · "),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _white75,
                      fontSize: CLType.meta,
                      shadows: _textShadow)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _selfTitle(Moment moment) {
    final contacts = moment.post.privacyStatus == "connections";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Flexible(
              child: Text("Your moment",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: CLType.title,
                      fontWeight: FontWeight.w700,
                      shadows: _textShadow)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
                borderRadius: BorderRadius.circular(CLRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(contacts ? Icons.group_rounded : Icons.public_rounded,
                      size: 12, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(contacts ? "Contacts" : "Public",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.meta,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
            [
              if (moment.isShared) "Shared a post",
              ephemeralTimeAgo(moment.post.datePosted),
              _archive
                  ? _archivedOn(moment)
                  : ephemeralTimeLeft(moment.expiresAt),
            ].where((s) => s.isNotEmpty).join(" · "),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _white75, fontSize: CLType.meta, shadows: _textShadow)),
      ],
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
                height: 2.5,
                margin: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
                decoration: BoxDecoration(
                    color: const Color(0x4DFFFFFF),
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
    final media = moment.media;
    if (media == null) return const SizedBox.shrink();
    if (media.isVideo) {
      final video = _video;
      if (video == null || !video.value.isInitialized) {
        return const Center(
            child: CircularProgressIndicator(color: Colors.white));
      }
      final aspect = video.value.aspectRatio;
      return SizedBox.expand(
        child: FittedBox(
          fit: momentMediaFit(aspect, MediaQuery.of(context).size),
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
              width: aspect * 1000, height: 1000, child: VideoPlayer(video)),
        ),
      );
    }
    return _MomentPhoto(src: media.reference);
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

  Widget _caption(Moment moment) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          moment.post.caption,
          style: const TextStyle(
            color: Colors.white,
            fontSize: CLType.sectionTitle,
            fontWeight: FontWeight.w600,
            height: 1.35,
            shadows: [
              Shadow(
                  color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 1))
            ],
          ),
        ),
      );

  /// Someone else's moment: the caption, then react (a tray behind one
  /// button) and reply (sent from inside the field).
  Widget _othersPanel(Moment moment) {
    final mine = _glyphFor(_myReactions[moment.post.postId]);
    final first = moment.post.author.displayName.split(" ").first;
    final hasCaption = moment.post.caption.trim().isNotEmpty;

    if (!moment.allowReplies) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasCaption) ...[_caption(moment), const SizedBox(height: 12)],
          const _StatusLine(
              icon: Icons.lock_outline_rounded,
              text: "Replies are off for this moment"),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCaption) ...[_caption(moment), const SizedBox(height: 12)],
        if (_trayOpen && _palette.isNotEmpty) ...[
          Center(child: _tray(moment)),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            _trayToggle(mine),
            const SizedBox(width: 8),
            Expanded(child: _replyField(first)),
          ],
        ),
        const SizedBox(height: 12),
        mine != null
            ? _StatusLine(
                icon: Icons.check_circle_rounded,
                text: "You reacted $mine · $first will see it",
                strong: true)
            : _StatusLine(
                icon: Icons.lock_outline_rounded,
                text: "Replies go to your chat with $first."),
      ],
    );
  }

  Widget _tray(Moment moment) {
    final mine = _myReactions[moment.post.postId];
    final emojis = _palette.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x38000000),
        borderRadius: BorderRadius.circular(CLRadii.pill),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < emojis.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: _trayEmoji(emojis[i], mine),
            ),
        ],
      ),
    );
  }

  Widget _trayEmoji(Emoji emoji, String? mine) {
    final chosen = mine == emoji.emojiId;
    final locked = mine != null && !chosen;
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
              color: chosen ? const Color(0x47FFFFFF) : Colors.transparent,
            ),
            child: chosen
                ? ReactionBurst(
                    emoji: emoji.content,
                    size: 24,
                    ringColor: Colors.white,
                    burst: _burst)
                : Text(emoji.content,
                    style: const TextStyle(fontSize: 24, height: 1)),
          ),
        ),
      ),
    );
  }

  /// Opens the tray; shows your reaction once you have made one.
  Widget _trayToggle(String? mine) {
    return Semantics(
      button: true,
      label: "Reactions",
      child: GestureDetector(
        onTap: _palette.isEmpty ? null : _toggleTray,
        child: _Glass(
          width: 46,
          height: 46,
          radius: 23,
          color: _trayOpen ? const Color(0x42FFFFFF) : _glassFill,
          border: _trayOpen ? const Color(0x80FFFFFF) : _glassEdge,
          child: Center(
            child: mine != null
                ? ReactionBurst(
                    emoji: mine,
                    size: 22,
                    ringColor: Colors.white,
                    burst: _burst,
                    popOnly: true)
                : const Icon(Icons.add_reaction_outlined,
                    size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _replyField(String first) {
    final ready = _reply.text.trim().isNotEmpty && !_sending;
    return _Glass(
      height: 46,
      radius: 23,
      color: _glassFill,
      border: _glassEdge,
      padding: const EdgeInsets.fromLTRB(16, 0, 5, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _reply,
              focusNode: _replyFocus,
              enabled: !_sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              cursorColor: Colors.white,
              style:
                  const TextStyle(color: Colors.white, fontSize: CLType.title),
              decoration: InputDecoration.collapsed(
                hintText: "Reply to $first…",
                hintStyle: const TextStyle(
                    color: Color(0xB8FFFFFF), fontSize: CLType.title),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: "Send reply",
            child: GestureDetector(
              onTap: ready ? _sendReply : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? CLColors.brand : const Color(0x24FFFFFF),
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.send_rounded,
                        size: 18,
                        color: ready ? Colors.white : const Color(0x8CFFFFFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Your moment: the caption, Unarchive when it can come back, then who saw
  /// it - a pill with their faces and totals - and the settings.
  Widget _selfPanel(Moment moment) {
    final viewers = _viewers;
    final views = viewers?.views ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (moment.post.caption.trim().isNotEmpty) ...[
          _caption(moment),
          const SizedBox(height: 12),
        ],
        if (_archive && moment.canUnarchive) ...[
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: _unarchiveCurrent,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(CLRadii.pill),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.unarchive_outlined,
                        size: 18, color: CLColors.textLight),
                    SizedBox(width: 6),
                    Text("Unarchive",
                        style: TextStyle(
                            color: CLColors.textLight,
                            fontSize: CLType.body,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Swipe up - or tap - for who saw it.
        GestureDetector(
          onTap: _openViewers,
          behavior: HitTestBehavior.opaque,
          child: const Icon(Icons.keyboard_arrow_up_rounded,
              size: 22, color: Color(0x99FFFFFF)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: "Viewers",
                child: GestureDetector(
                  onTap: _openViewers,
                  child: _Glass(
                    height: 52,
                    radius: 26,
                    color: const Color(0x1FFFFFFF),
                    border: const Color(0x33FFFFFF),
                    padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
                    // Placeholders in the pill's own shape until the viewers
                    // are in - it used to read "No viewers yet" for the
                    // moment that took, then change its mind.
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: viewers == null
                          ? const _ViewersPillSkeleton()
                          : Row(
                              key: const ValueKey('viewers'),
                              children: [
                                _faces(viewers.results),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          views == 0
                                              ? "No viewers yet"
                                              : "$views ${views == 1 ? "viewer" : "viewers"}",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: CLType.body,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          _Stat(
                                              icon:
                                                  Icons.favorite_border_rounded,
                                              count: viewers.reactions),
                                          const SizedBox(width: 8),
                                          _Stat(
                                              icon: Icons
                                                  .chat_bubble_outline_rounded,
                                              count: viewers.replies),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (moment.saveable != null) ...[
              _saveButton(moment),
              const SizedBox(width: 8),
            ],
            _GlassCircle(
              icon: Icons.more_horiz_rounded,
              tooltip: "Moment settings",
              size: 52,
              iconSize: 22,
              color: const Color(0x1FFFFFFF),
              border: const Color(0x33FFFFFF),
              onTap: _openViewers,
            ),
          ],
        ),
      ],
    );
  }

  /// Save to the phone's gallery - a ring of progress while it downloads.
  Widget _saveButton(Moment moment) {
    const fill = Color(0x1FFFFFFF);
    const edge = Color(0x33FFFFFF);
    final url = moment.saveable!.url;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: MediaDownloader.instance.progress,
      builder: (context, _, __) {
        final progress = MediaDownloader.instance.progressOf(url);
        if (progress == null) {
          return _GlassCircle(
            icon: Icons.download_rounded,
            tooltip: "Save to device",
            size: 52,
            iconSize: 22,
            color: fill,
            border: edge,
            onTap: () => _save(moment),
          );
        }
        return Semantics(
          label: "Saving to device",
          child: _Glass(
            width: 52,
            height: 52,
            radius: 26,
            color: fill,
            border: edge,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  // 0 until the size is known: spin instead.
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2.5,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Saves your moment to the gallery. In the background: it carries on,
  /// and says when it's done, if you move on or close the viewer.
  void _save(Moment moment) {
    final save = moment.saveable;
    if (save == null) return;
    final type = GallerySaver.typeOf(save.url,
        isVideo: save.isVideo, mediaType: save.mediaType);
    MediaDownloader.instance.download(
      save.url,
      mimeType: type.mimeType,
      fileName: GallerySaver.fileNameFor(
          moment.post.datePosted ?? DateTime.now(), type.extension),
      toGallery: true,
    );
  }

  /// The first few who saw it, overlapping.
  Widget _faces(List<EphemeralViewer> viewers) {
    final faces = viewers.take(3).toList();
    if (faces.isEmpty) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
            color: Color(0x2EFFFFFF), shape: BoxShape.circle),
        child: const Icon(Icons.visibility_outlined,
            size: 16, color: Colors.white),
      );
    }
    return SizedBox(
      width: 28 + (faces.length - 1) * 18.0,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < faces.length; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Color(0xFF1D1F24), shape: BoxShape.circle),
                child: CLAvatar(
                  id: faces[i].entity.entityId,
                  name: faces[i].entity.displayName,
                  src: faces[i].entity.profile,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A moment's photo or video fills the screen when it is near the screen's
/// shape - one made in the app is 9:16, so on a phone that trims a sliver -
/// and is shown whole on black when it is not: a landscape photo made to
/// fill a portrait screen would lose most of itself.
BoxFit momentMediaFit(double aspectRatio, Size screen) {
  if (aspectRatio <= 0 || screen.width <= 0 || screen.height <= 0) {
    return BoxFit.contain;
  }
  final off = aspectRatio / (screen.width / screen.height);
  return (off - 1).abs() <= 0.25 ? BoxFit.cover : BoxFit.contain;
}

/// A moment's photo, fitted by [momentMediaFit] once its shape is known.
class _MomentPhoto extends StatefulWidget {
  final String src;

  const _MomentPhoto({required this.src});

  @override
  State<_MomentPhoto> createState() => _MomentPhotoState();
}

class _MomentPhotoState extends State<_MomentPhoto> {
  ImageProvider? _provider;
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: (_, __) {});
  double? _aspect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _MomentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    final mq = MediaQuery.of(context);
    // Decoded at the screen's size, like every other full-width image here;
    // the same provider feeds the Image below, so it decodes once.
    final provider = ResizeImage(NetworkImage(widget.src),
        width: (mq.size.width * mq.devicePixelRatio).ceil(),
        policy: ResizeImagePolicy.fit);
    _provider = provider;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    final aspect = info.image.width / info.image.height;
    if (mounted && aspect != _aspect) setState(() => _aspect = aspect);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final aspect = _aspect;
    if (provider == null) return const SizedBox.shrink();
    return Image(
      image: provider,
      width: double.infinity,
      height: double.infinity,
      fit: aspect == null
          ? BoxFit.contain
          : momentMediaFit(aspect, MediaQuery.of(context).size),
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.image_not_supported_outlined,
              size: 32, color: Colors.white54)),
    );
  }
}

/// A see-through shape over the media, frosted so it reads on a bright
/// picture and a dark one alike.
class _Glass extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final Color color;
  final Color? border;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const _Glass({
    this.width,
    required this.height,
    required this.radius,
    required this.color,
    this.border,
    this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
            border: border == null ? null : Border.all(color: border!),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A round control over the media: close, mute, more.
class _GlassCircle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final Color color;
  final Color? border;

  const _GlassCircle({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
    this.color = const Color(0x47000000),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: _Glass(
            width: size,
            height: size,
            radius: size / 2,
            color: color,
            border: border,
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// A small line under the reply field: where replies go, or that you
/// reacted.
class _StatusLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;

  const _StatusLine(
      {required this.icon, required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final color = strong ? Colors.white : _white62;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: CLType.meta,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w400)),
        ),
      ],
    );
  }
}

/// The viewers pill while its viewers load: three faces and two lines, in
/// the same places as the real ones, breathing - white on the frosted glass
/// rather than the app's grey skeleton, which would read as a hole in it.
class _ViewersPillSkeleton extends StatefulWidget {
  const _ViewersPillSkeleton();

  @override
  State<_ViewersPillSkeleton> createState() => _ViewersPillSkeletonState();
}

class _ViewersPillSkeletonState extends State<_ViewersPillSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: "Loading viewers",
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final fill = Color.lerp(
              const Color(0x1AFFFFFF),
              const Color(0x3DFFFFFF),
              Curves.easeInOut.transform(_pulse.value))!;
          Widget bar(double width, double height) => Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              );
          return Row(
            children: [
              SizedBox(
                width: 28 + 2 * 18.0,
                height: 28,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * 18.0,
                        child: Container(
                          width: 28,
                          height: 28,
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                              color: Color(0xFF1D1F24), shape: BoxShape.circle),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: fill, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(84, 12),
                  const SizedBox(height: 6),
                  bar(56, 9),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A count with its icon, in the viewers pill.
class _Stat extends StatelessWidget {
  final IconData icon;
  final int count;

  const _Stat({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xB8FFFFFF)),
        const SizedBox(width: 3),
        Text("$count",
            style: const TextStyle(
                color: Color(0xB8FFFFFF), fontSize: CLType.meta, height: 1)),
      ],
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
