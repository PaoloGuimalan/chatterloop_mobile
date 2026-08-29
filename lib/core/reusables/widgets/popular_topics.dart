// Topics as CONTENT, not a widget (design 2a/2b).
//
// The earlier direction (1b) made topics a numbered chart in a card, and that
// card was ADDED ABOVE surfaces that already had an empty state - so Explore
// and the Newsfeed each showed two half-filled things at once. Turn 2 fixes
// both the same way: let topics BE the empty state rather than sit on top of
// one. Practically, for this file, that means the rows lost their card, their
// rank numbers and their category pills, and became plain list rows - a "#"
// tile, the tag, its category, and who is in it - so they read as suggestions
// belonging to the surface around them.
//
// Rows carry topic name, category and participant avatars ONLY. No post
// counts: a count is a number the reader cannot act on.
//
// There is deliberately no follow/following affordance. Topics are a discovery
// surface, not something with a subscription behind it.
//
// Three surfaces render these rows, and they differ only in where the data
// comes from:
//
//   Explore idle       CLPopularTopics  - fetches the trending list itself
//   Newsfeed empty     CLPopularTopics  - same, inside the empty-state card
//   Explore results    CLTopicList      - rows handed in from the search

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/interests_api.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';

/// The full trending list, and what the popular endpoint caps at anyway.
/// Explore's idle state shows this; "See all" opens the paginated directory
/// behind it, which is not capped.
const int kPopularTopicMax = 8;

/// What the newsfeed's empty state shows. Four rows, because that empty state
/// also carries a heading, a subtitle and an "Explore more" button, and the
/// card has to fit them all on the shortest phone without scrolling.
const int kPopularTopicFeedPreview = 4;

/// Row metrics, shared by the row and its skeleton so the two cannot drift -
/// a loader of a different height makes the list resize when data lands.
const double kTopicRowPaddingV = 9;
const double kTopicTileSize = 36;
const double kTopicNameHeight = 17;
const double kTopicNameGap = 2;
const double kTopicCategoryHeight = 15;
const double kTopicFaceSize = 24;

/// How far each avatar laps the one before it.
const double kTopicFaceOverlap = 9;

/// The trending list, fetched.
///
/// Renders nothing at all - not an empty card - once it is known there is
/// nothing to show. A brand-new platform legitimately has no popular topics
/// yet, and a surface should not lead with an empty box. That is also why the
/// callers below can place this unconditionally.
class CLPopularTopics extends StatefulWidget {
  final void Function(PopularTopic topic) onTopicTap;

  /// The list's action. Explore labels it "See all" (it opens the same list,
  /// unbounded and searchable); the newsfeed passes null, since its empty state
  /// carries an "Explore more" button of its own below the rows.
  final VoidCallback? onSeeAll;

  /// Section label above the rows. Both current surfaces call it "Trending
  /// tags" - which is what it is - rather than "Popular topics", the internal
  /// name of the ranking.
  final String title;

  /// How many rows to show.
  final int limit;

  /// Hairlines between rows. On for the newsfeed, where the rows sit inside a
  /// card and need separating from each other; off in Explore, where they sit
  /// on the page as loose suggestions.
  final bool dividers;

  /// See [CLTopicList.faceRingColor].
  final Color? faceRingColor;

  const CLPopularTopics({
    super.key,
    required this.onTopicTap,
    this.onSeeAll,
    this.title = "Trending tags",
    this.limit = kPopularTopicMax,
    this.dividers = false,
    this.faceRingColor,
  });

  @override
  State<CLPopularTopics> createState() => _CLPopularTopicsState();
}

class _CLPopularTopicsState extends State<CLPopularTopics> {
  final _api = InterestsApi();

  List<PopularTopic> _topics = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CLPopularTopics oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching between the preview and the full list asks for more rows.
    if (oldWidget.limit != widget.limit) _load();
  }

  Future<void> _load() async {
    final topics = await _api.popularTopics(limit: widget.limit);
    // The request outlives a fast tab switch easily, and setState on a
    // disposed State throws.
    if (!mounted) return;
    setState(() {
      _topics = topics;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && _topics.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CLOverlineHeader(
          title: widget.title,
          actionLabel: widget.onSeeAll == null ? null : "See all",
          onAction: widget.onSeeAll,
        ),
        CLTopicList(
          topics: _topics,
          loading: !_loaded,
          skeletonRows: widget.limit,
          dividers: widget.dividers,
          faceRingColor: widget.faceRingColor,
          onTopicTap: widget.onTopicTap,
        ),
      ],
    );
  }
}

/// Rows for topics somebody else already has - search results, or the fetched
/// list above. Shrink-wrapped, so it drops straight into a Column or a
/// ListView's children rather than needing a height.
class CLTopicList extends StatelessWidget {
  final List<PopularTopic> topics;
  final void Function(PopularTopic topic) onTopicTap;

  /// Draws [skeletonRows] placeholders instead of [topics].
  final bool loading;
  final int skeletonRows;
  final bool dividers;

  /// The typed query, when these rows are search results: the part of each tag
  /// that matched is marked, so a list of near-identical names shows WHY each
  /// one is in it. Null on the idle list, which matched nothing.
  final String? highlight;

  /// What the lapping avatar rings are drawn in. It has to match whatever the
  /// rows sit ON - the card in the newsfeed's empty state, the page itself in
  /// Explore - or the rings read as grey outlines instead of separators.
  /// Defaults to the theme's surface, which is the card case.
  final Color? faceRingColor;

  const CLTopicList({
    super.key,
    required this.topics,
    required this.onTopicTap,
    this.loading = false,
    this.skeletonRows = 3,
    this.dividers = false,
    this.highlight,
    this.faceRingColor,
  });

  @override
  Widget build(BuildContext context) {
    final count = loading ? skeletonRows : topics.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0 && dividers) const _TopicDivider(),
          if (loading)
            const CLTopicRowSkeleton()
          else
            CLTopicRow(
              topic: topics[i],
              highlight: highlight,
              faceRingColor: faceRingColor,
              onTap: () => onTopicTap(topics[i]),
            ),
        ],
      ],
    );
  }
}

class _TopicDivider extends StatelessWidget {
  const _TopicDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: cl(context).border);
  }
}

/// One topic. Exposed (rather than private) so its layout can be measured in a
/// widget test - row sizing is the kind of thing that only breaks visually.
class CLTopicRow extends StatelessWidget {
  final PopularTopic topic;
  final VoidCallback onTap;

  /// See [CLTopicList.highlight].
  final String? highlight;

  /// See [CLTopicList.faceRingColor].
  final Color? faceRingColor;

  const CLTopicRow({
    super.key,
    required this.topic,
    required this.onTap,
    this.highlight,
    this.faceRingColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: kTopicRowPaddingV,
            horizontal: 4,
          ),
          child: Row(
            children: [
              Container(
                width: kTopicTileSize,
                height: kTopicTileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.brandSoft,
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                ),
                child: Text(
                  '#',
                  style: TextStyle(
                    color: p.brand,
                    fontSize: CLType.screenTitle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TopicName(slug: topic.slug, highlight: highlight),
                    const SizedBox(height: kTopicNameGap),
                    Text(
                      topic.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text3,
                        fontSize: CLType.caption,
                        // Pinned so the row's height is deterministic rather
                        // than a property of whatever font the device
                        // resolves - the skeleton reserves exactly this.
                        height: kTopicCategoryHeight / CLType.caption,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _FaceStack(faces: topic.faces, ringColor: faceRingColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// "#sunsetseries", with the matched run marked when there is a query.
///
/// Matched against the SLUG, which is what is drawn: the query is normalised
/// the same way a hashtag is (a leading "#" and any spaces removed, lowercased)
/// so typing "north edsa" marks "northedsa" rather than failing to match its
/// own result.
class _TopicName extends StatelessWidget {
  final String slug;
  final String? highlight;

  const _TopicName({required this.slug, this.highlight});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final style = TextStyle(
      color: p.text,
      fontSize: CLType.title,
      fontWeight: FontWeight.w600,
      height: kTopicNameHeight / CLType.title,
    );

    final needle = (highlight ?? '')
        .trim()
        .replaceAll('#', '')
        .replaceAll(' ', '')
        .toLowerCase();
    final start = needle.isEmpty ? -1 : slug.toLowerCase().indexOf(needle);

    if (start < 0) {
      return Text('#$slug',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '#${slug.substring(0, start)}'),
          TextSpan(
            text: slug.substring(start, start + needle.length),
            style: TextStyle(
              // A wash rather than a colour change: the marked run has to stay
              // as readable as the rest of the name, and recolouring the text
              // itself reads as a link on a row that is already tappable.
              backgroundColor: dark ? p.goldSoft : const Color(0xFFFFF0C2),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: slug.substring(start + needle.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The overlapping participant avatars. Drawn right-to-left so the first
/// participant ends up on top.
class _FaceStack extends StatelessWidget {
  final List<PopularTopicFace> faces;
  final double size;

  /// The colour the lapping ring is drawn in - it has to match whatever the
  /// row sits ON, not the theme's surface, or the rings read as grey outlines
  /// against a card of a different shade.
  final Color? ringColor;

  const _FaceStack({
    required this.faces,
    this.size = kTopicFaceSize,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return const SizedBox.shrink();
    final p = cl(context);
    final step = size - kTopicFaceOverlap;

    return SizedBox(
      width: size + (faces.length - 1) * step,
      height: size,
      child: Stack(
        children: [
          for (var i = faces.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // The ring is what separates one avatar from the one it laps.
                  border: Border.all(color: ringColor ?? p.surface, width: 2),
                ),
                child: CLAvatar(
                  id: faces[i].entityId,
                  name: faces[i].name,
                  src: faces[i].profile,
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shaped like CLTopicRow off the SAME constants, so the list cannot resize
/// when the data lands.
class CLTopicRowSkeleton extends StatelessWidget {
  const CLTopicRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: kTopicRowPaddingV,
        horizontal: 4,
      ),
      child: Row(
        children: [
          const CLSkeleton(
            width: kTopicTileSize,
            height: kTopicTileSize,
            borderRadius: BorderRadius.all(Radius.circular(CLRadii.sm)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                CLSkeleton(width: 118, height: kTopicNameHeight),
                SizedBox(height: kTopicNameGap),
                CLSkeleton(width: 84, height: kTopicCategoryHeight),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: kTopicFaceSize + 2 * (kTopicFaceSize - kTopicFaceOverlap),
            height: kTopicFaceSize,
            child: Stack(
              children: [
                for (var i = 2; i >= 0; i--)
                  Positioned(
                    left: i * (kTopicFaceSize - kTopicFaceOverlap),
                    child: const CLSkeleton(
                      width: kTopicFaceSize,
                      height: kTopicFaceSize,
                      borderRadius:
                          BorderRadius.all(Radius.circular(kTopicFaceSize / 2)),
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

/// The topic's identity card, shown at the top of its detail feed.
///
/// Same three facts as a list row - name, category, participants - at a larger
/// size, with a gradient "#" tile standing in for the avatar a person or page
/// would have. No follow control: see the file header.
class CLTopicHeaderCard extends StatelessWidget {
  final PopularTopic topic;

  const CLTopicHeaderCard({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CLRadii.md),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C7DEF), Color(0xFF5AA9FF)],
              ),
            ),
            child: const Text(
              '#',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#${topic.slug}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: kTopicNameGap),
                Text(
                  topic.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text3, fontSize: CLType.caption),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _FaceStack(faces: topic.faces, size: 26),
        ],
      ),
    );
  }
}
