import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/moments_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/models/post_models/ephemeral_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bumped whenever a moment / thought is created, edited or deleted, so every
/// surface showing them (the board, rails, profile rings) reloads - webapp's
/// MOMENTS_CHANGED_EVENT / THOUGHTS_CHANGED_EVENT.
class EphemeralEvents {
  EphemeralEvents._();

  static final moments = ValueNotifier<int>(0);
  static final thoughts = ValueNotifier<int>(0);
}

/// Opens [entityId]'s moments, starting at [postId] when given.
void openMoments(BuildContext context, String entityId, {String? postId}) {
  context.push(Uri(
    path: '/moments/$entityId',
    queryParameters: postId == null || postId.isEmpty ? null : {'post': postId},
  ).toString());
}

/// A Moment ring around any avatar: brand when there is something unseen,
/// muted once it has all been watched.
class MomentRingFrame extends StatelessWidget {
  final bool unseen;
  final double size;
  final Widget child;

  const MomentRingFrame(
      {super.key,
      required this.unseen,
      required this.size,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      width: size + 6,
      height: size + 6,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unseen ? LinearGradient(colors: [p.brand, p.pink]) : null,
        color: unseen ? null : p.border2,
      ),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface),
        child: child,
      ),
    );
  }
}

const _sharedGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF14233B), Color(0xFF3B6FE0)],
);
const _placeholderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1C7DEF), Color(0xFF5AA9FF)],
);

/// Under 4h left, a tile's bar turns pink - "about to go".
const _expiringFraction = 4 / 24;

/// The Moments board at the top of the newsfeed - webapp's MomentsBoard on a
/// phone, without its card: "Moments", the "N new" badge and "See all"; then a
/// large tile for the newest author with something unseen, "Add Moment", and
/// everyone else (you first, as "You"), each with a remaining-time bar.
class MomentsStrip extends StatefulWidget {
  const MomentsStrip({super.key});

  @override
  State<MomentsStrip> createState() => _MomentsStripState();
}

class _MomentsStripState extends State<MomentsStrip> {
  MomentTray? _tray;

  @override
  void initState() {
    super.initState();
    _load();
    EphemeralEvents.moments.addListener(_load);
  }

  @override
  void dispose() {
    EphemeralEvents.moments.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final tray = await MomentsApi().getTrayRequest();
    if (mounted) setState(() => _tray = tray);
  }

  void _create() => context.push('/moments/new');

  void _open(MomentTrayEntry entry) =>
      openMoments(context, entry.author.entityId, postId: entry.startPostId);

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final tray = _tray;
    final entries = tray?.results ?? const <MomentTrayEntry>[];

    // The large tile: the newest author with something unseen.
    MomentTrayEntry? featured;
    for (final entry in entries.where((e) => e.hasUnseen)) {
      if (featured == null ||
          (entry.latestAt ?? DateTime(0))
              .isAfter(featured.latestAt ?? DateTime(0))) {
        featured = entry;
      }
    }
    final rest = entries.where((e) => e != featured).toList();

    // No card around it - it sits straight on the feed, as it first did -
    // but the "Moments" heading always shows, and the newest unseen author
    // still gets the wide tile.
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Moments",
                  style: TextStyle(
                      fontSize: CLType.sectionTitle,
                      fontWeight: FontWeight.w800,
                      color: p.text)),
              const SizedBox(width: 8),
              if ((tray?.newCount ?? 0) > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: p.brandSoft,
                      borderRadius: BorderRadius.circular(CLRadii.pill)),
                  child: Text("${tray!.newCount} new",
                      style: TextStyle(
                          fontSize: CLType.meta,
                          fontWeight: FontWeight.w700,
                          color: p.brand)),
                ),
              const Spacer(),
              if (entries.isNotEmpty)
                GestureDetector(
                  onTap: () => _open(featured ?? entries.first),
                  child: Text(
                    "See all · ${tray!.total > 0 ? tray.total : entries.length}",
                    style: TextStyle(
                        fontSize: CLType.label,
                        fontWeight: FontWeight.w700,
                        color: p.brand),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: tray == null
                ? const _BoardSkeleton()
                : entries.isEmpty
                    // Nothing to watch: Add Moment, and a card filling the
                    // rest of the row rather than a line of small text
                    // floating in the space the tiles would take.
                    ? Row(
                        children: [
                          _AddTile(onTap: _create),
                          const Expanded(child: _EmptyBoard()),
                        ],
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (featured != null)
                            _FeaturedTile(
                                entry: featured, onTap: () => _open(featured!)),
                          _AddTile(onTap: _create),
                          for (final entry in rest)
                            _MomentTile(
                                entry: entry, onTap: () => _open(entry)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// What a tile draws under its text: the photo, the video's first frame, or
/// a gradient (a text-only share, or nothing to show).
class _TileBackground extends StatelessWidget {
  final MomentPreview? latest;

  const _TileBackground({required this.latest});

  @override
  Widget build(BuildContext context) {
    final preview = latest;
    final thumb = preview?.thumbnail;
    final isVideo = preview?.isVideo == true;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: preview?.isShared == true
                ? _sharedGradient
                : _placeholderGradient,
          ),
        ),
        if (thumb != null && !isVideo)
          CLNetworkImage(src: thumb, fit: BoxFit.cover),
        if (thumb != null && isVideo) MomentVideoFrame(src: thumb),
      ],
    );
  }
}

class _RemainingBar extends StatelessWidget {
  final DateTime? expiresAt;

  const _RemainingBar({required this.expiresAt});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final fraction = ephemeralRemainingFraction(expiresAt);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 3,
      child: ColoredBox(
        color: Colors.white30,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: ColoredBox(
                color: fraction < _expiringFraction ? p.pink : Colors.white),
          ),
        ),
      ),
    );
  }
}

IconData? _typeIcon(MomentPreview? latest) {
  if (latest == null) return null;
  if (latest.isShared) return Icons.repeat_rounded;
  if (latest.isVideo) return Icons.play_circle_outline_rounded;
  return null;
}

/// The newest unseen author, large: avatar and name on top, caption below.
class _FeaturedTile extends StatelessWidget {
  final MomentTrayEntry entry;
  final VoidCallback onTap;

  const _FeaturedTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final latest = entry.latest;
    final icon = _typeIcon(latest);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 212,
        margin: const EdgeInsets.only(right: 8),
        clipBehavior: Clip.antiAlias,
        decoration:
            BoxDecoration(borderRadius: BorderRadius.circular(CLRadii.md)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TileBackground(latest: latest),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x8C000000), Color(0x1A000000)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              right: 10,
              child: Row(
                children: [
                  // White ring on a ROUND box around the avatar.
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: CLAvatar(
                      id: entry.author.entityId,
                      name: entry.author.displayName,
                      src: entry.author.profile,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.author.displayName.split(" ").first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: CLType.caption,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (icon != null) Icon(icon, size: 15, color: Colors.white),
                ],
              ),
            ),
            if ((latest?.caption ?? "").trim().isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 18,
                child: Text(
                  latest!.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.body,
                      fontWeight: FontWeight.w700,
                      height: 1.3),
                ),
              ),
            _RemainingBar(expiresAt: latest?.expiresAt),
          ],
        ),
      ),
    );
  }
}

/// Everyone else: a small story tile - dot when unseen, faded once watched.
class _MomentTile extends StatelessWidget {
  final MomentTrayEntry entry;
  final VoidCallback onTap;

  const _MomentTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final latest = entry.latest;
    final icon = _typeIcon(latest);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: entry.hasUnseen || entry.isSelf ? 1 : 0.7,
        child: Container(
          width: 100,
          margin: const EdgeInsets.only(right: 8),
          clipBehavior: Clip.antiAlias,
          decoration:
              BoxDecoration(borderRadius: BorderRadius.circular(CLRadii.md)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TileBackground(latest: latest),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1],
                    colors: [Color(0x00000000), Color(0x99000000)],
                  ),
                ),
              ),
              if (icon != null)
                Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(icon, size: 14, color: Colors.white)),
              if (entry.hasUnseen)
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 10,
                child: Text(
                  entry.isSelf
                      ? "You"
                      : entry.author.displayName.split(" ").first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: CLType.caption,
                      fontWeight: FontWeight.w700),
                ),
              ),
              _RemainingBar(expiresAt: latest?.expiresAt),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tiles' own ground: white in light, so they stand off the feed's grey
/// rather than blending into it; the raised surface in dark.
Color _tileSurface(BuildContext context) {
  final p = cl(context);
  return Theme.of(context).brightness == Brightness.light
      ? p.surface
      : p.surface2;
}

/// A lift under a tile in light mode - on white-on-grey it is the edge.
List<BoxShadow>? _tileShadow(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const [
            BoxShadow(
                color: Color(0x14141E37), blurRadius: 3, offset: Offset(0, 1)),
          ]
        : null;

/// "Add Moment": a dashed tile, like web's.
class _AddTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 8),
        child: CustomPaint(
          painter: _DashedBorder(color: p.border2, radius: CLRadii.md),
          child: Container(
            decoration: BoxDecoration(
              color: _tileSurface(context),
              borderRadius: BorderRadius.circular(CLRadii.md),
              boxShadow: _tileShadow(context),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration:
                      BoxDecoration(color: p.brand, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(height: 6),
                Text("Add Moment",
                    style: TextStyle(
                        fontSize: CLType.caption,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// No Moments to watch: a card the height of the tiles, filling the row.
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _tileSurface(context),
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
        boxShadow: _tileShadow(context),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome_outlined, size: 20, color: p.brand),
          ),
          const SizedBox(height: 8),
          Text("No moments to view",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: CLType.title,
                  fontWeight: FontWeight.w700,
                  color: p.text)),
          const SizedBox(height: 2),
          Text("Moments from your circle show up here for 24 hours.",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: CLType.caption, color: p.text3)),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // Inset by half the stroke: drawn ON the edge, half of every dash fell
    // outside the tile and was clipped away by the list.
    final inset = paint.strokeWidth / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(inset),
          Radius.circular(radius - inset)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// The board while the tray loads: tiles the size of the real ones.
class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: CLSkeleton(
              width: 212,
              height: 150,
              borderRadius: BorderRadius.all(Radius.circular(CLRadii.md))),
        ),
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: CLSkeleton(
                width: 100,
                height: 150,
                borderRadius: BorderRadius.all(Radius.circular(CLRadii.md))),
          ),
      ],
    );
  }
}

/// A video's first frame as a still - Moment tiles (board, archive), where
/// a video used to be only a play icon.
///
/// An extracted bitmap ([VideoFirstFrame]), NOT a player: this first held a
/// live player per tile just to show one frame, so an archive of video
/// moments pinned a decoder per tile before anything even played - and the
/// video you then opened was the one that failed.
class MomentVideoFrame extends StatelessWidget {
  final String src;

  const MomentVideoFrame({super.key, required this.src});

  @override
  Widget build(BuildContext context) =>
      VideoFirstFrame(source: src, showPlayBadge: false);
}
