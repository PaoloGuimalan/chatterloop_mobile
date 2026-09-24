import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:chatterloop_app/views/moments/moments_strip.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_feed_switcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Archived > Moments on your own profile: your expired moments as a grid of
/// story-shaped tiles, newest first. Only you ever see it (the endpoint is
/// the acting entity's own archive). A tile plays it in the Moments viewer
/// (/moments/archive), like a live one.
///
/// Not a scroll view of its own - it sits inside the profile's scroll, so it
/// pages with a "Load more" rather than on scroll.
class MomentArchiveGrid extends StatefulWidget {
  const MomentArchiveGrid({super.key});

  @override
  State<MomentArchiveGrid> createState() => _MomentArchiveGridState();
}

class _MomentArchiveGridState extends State<MomentArchiveGrid> {
  final List<Moment> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Deleted from the viewer: start over so it drops out of the grid.
    EphemeralEvents.moments.addListener(_reload);
  }

  @override
  void dispose() {
    EphemeralEvents.moments.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    _items.clear();
    _page = 1;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await MomentsApi().getArchiveRequest(page: _page);
    if (!mounted) return;
    setState(() {
      final seen = _items.map((m) => m.post.postId).toSet();
      _items.addAll(result.items.where((m) => seen.add(m.post.postId)));
      _hasMore = result.hasMore;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    if (_loading && _items.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
        child: GridView.count(
          // No inherited MediaQuery padding: inside the profile scroll it
          // added the status-bar height above the grid.
          padding: EdgeInsets.zero,
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 9 / 16,
          children: [
            for (var i = 0; i < 6; i++)
              const CLSkeleton(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.all(Radius.circular(CLRadii.md))),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
        child: Column(
          children: [
            Icon(Icons.timelapse_rounded, size: 34, color: p.text3),
            const SizedBox(height: 8),
            Text("No past Moments",
                style: TextStyle(
                    fontSize: CLType.body,
                    fontWeight: FontWeight.w700,
                    color: p.text2)),
            const SizedBox(height: 4),
            Text(
              "Moments land here after their 24 hours are up. Only you can see them.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: CLType.caption, color: p.text3),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
      child: Column(
        children: [
          GridView.count(
            // No inherited MediaQuery padding: inside the profile scroll it
            // added the status-bar height above the grid.
            padding: EdgeInsets.zero,
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 9 / 16,
            children: [for (final moment in _items) _Tile(moment: moment)],
          ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CLBtn(
                label: _loading ? "Loading…" : "Load more",
                variant: CLBtnVariant.soft,
                size: CLBtnSize.sm,
                onPressed: _loading
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Moment moment;

  const _Tile({required this.moment});

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final thumb = moment.thumbnail;
    final date = moment.post.datePosted?.toLocal();
    return GestureDetector(
      onTap: () => context.push(Uri(
        path: '/moments/archive',
        queryParameters: {'post': moment.post.postId},
      ).toString()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CLRadii.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF14233B), Color(0xFF3B6FE0)],
                ),
              ),
            ),
            if (thumb != null) CLNetworkImage(src: thumb, fit: BoxFit.cover),
            if (thumb == null && moment.videoSrc != null)
              MomentVideoFrame(src: moment.videoSrc!),
            if (thumb == null && moment.videoSrc != null)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.play_circle_outline_rounded,
                    size: 16, color: Colors.white),
              ),
            if (thumb == null && moment.videoSrc == null)
              Center(
                child: Icon(
                  moment.isVideo
                      ? Icons.play_circle_outline_rounded
                      : moment.isShared
                          ? Icons.repeat_rounded
                          : Icons.photo_outlined,
                  color: Colors.white70,
                  size: 28,
                ),
              ),
            // Archived by hand with time left: it can still go back.
            if (moment.canUnarchive)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cl(context).brand,
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                  ),
                  child: Text(ephemeralTimeLeft(moment.naturalEnd),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.meta,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            if (date != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(CLRadii.pill),
                  ),
                  child: Text("${_months[date.month - 1]} ${date.day}",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.meta,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The profile's Archived tab: archived feed posts, or expired Moments.
class ProfileArchiveTabs extends StatefulWidget {
  /// The archived-posts feed (keyed by the profile so its paging still works).
  final Widget feed;

  const ProfileArchiveTabs({super.key, required this.feed});

  @override
  State<ProfileArchiveTabs> createState() => _ProfileArchiveTabsState();
}

class _ProfileArchiveTabsState extends State<ProfileArchiveTabs> {
  bool _moments = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The profile's own switcher, repeated - same track, height and
        // rounding as Posts / Saved / Archived above it.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              CLSpacing.contentGutter, 0, CLSpacing.contentGutter, 10),
          child: ProfileSegmentSwitcher(
            segments: const [
              (label: "Feed", icon: Icons.article_outlined),
              (label: "Moments", icon: Icons.timelapse_rounded),
            ],
            active: _moments ? 1 : 0,
            onChanged: (i) => setState(() => _moments = i == 1),
          ),
        ),
        _moments ? const MomentArchiveGrid() : widget.feed,
      ],
    );
  }
}
