// Topics as CONTENT, not a widget (design 2a/2b).
//
// The earlier direction (1b) made topics a numbered chart in a card, and that
// card was ADDED ABOVE surfaces that already had an empty state - so Explore
// and the Newsfeed each showed two half-filled things at once. Turn 2 fixes
// both the same way: let topics BE the empty state rather than sit on top of
// one. Practically, for this file, that means the rows lost their card and
// their rank numbers and became plain list rows - a "#" tile, the tag, its
// category pill, and who is in it - so they read as suggestions belonging to
// the surface around them.
//
// The tag itself is drawn WITHOUT a leading "#": the tile immediately left of
// it is the hash mark, and carrying both put it on the row twice.
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
/// card sizes to all of them together - past four it stops being an empty state
/// with somewhere to go and becomes a list with a notice on top.
const int kPopularTopicFeedPreview = 4;

/// Row metrics, shared by the row and its skeleton so the two cannot drift -
/// a loader of a different height makes the list resize when data lands.
const double kTopicRowPaddingV = 9;
const double kTopicTileSize = 36;
const double kTopicNameHeight = 17;
const double kTopicNameGap = 2;
const double kTopicPillHeight = 20;

/// Matches the web's .cl-topic-pill max-width, so a long category ellipsises
/// rather than shoving the avatars off the row.
const double kTopicPillMaxWidth = 160;
const double kTopicFaceSize = 24;

/// How far each avatar laps the one before it.
const double kTopicFaceOverlap = 9;

/// The category pill's colours, picked by hashing the CATEGORY name so a
/// category keeps its colour across sessions AND between the two clients - the
/// same eight variants and the same hash the web uses, so "Technology" is the
/// same colour in the app as in the browser.
///
/// Mirrors .cl-topic-pill--N in webapp/src/styles/styles.css, dark variants
/// included: a light tint that reads correctly on a white card glows on a dark
/// one, so dark mode uses a translucent wash of the same hue instead.
const List<(Color, Color)> _pillLight = [
  (Color(0xFFE7F0FE), Color(0xFF1B5FC1)),
  (Color(0xFFE3F7ED), Color(0xFF12805A)),
  (Color(0xFFFDF0D9), Color(0xFFA06400)),
  (Color(0xFFFFE9EC), Color(0xFFC2334A)),
  (Color(0xFFF0EAFF), Color(0xFF6B3FD4)),
  (Color(0xFFE0F5F8), Color(0xFF0B7183)),
  (Color(0xFFFFE9F3), Color(0xFFBF3579)),
  (Color(0xFFECEEF2), Color(0xFF4A5462)),
];

const List<(Color, Color)> _pillDark = [
  (Color(0x293C8BFF), Color(0xFF9EC5FF)),
  (Color(0x2920BD7C), Color(0xFF74E0AE)),
  (Color(0x2EE69500), Color(0xFFF5C46A)),
  (Color(0x29FF5B6B), Color(0xFFFF9AA6)),
  (Color(0x2E8B5CF6), Color(0xFFC4A8FF)),
  (Color(0x2E0EA5B7), Color(0xFF6FD8E8)),
  (Color(0x29F0518C), Color(0xFFFF9CC6)),
  (Color(0x14FFFFFF), Color(0xFFB7C0CC)),
];

/// Stable hash - the same function the web's pillClassFor uses, so the two
/// clients land on the same variant for the same category.
int _hash(String value) {
  var h = 0;
  for (var i = 0; i < value.length; i++) {
    h = (h * 31 + value.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return h;
}

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

  /// Section label above the rows. "Popular Topics" everywhere - the same words
  /// the ranking is called internally, so what a surface shows and what the
  /// endpoint is named cannot drift apart.
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
    this.title = "Popular Topics",
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
                    _CategoryPill(category: topic.category),
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

/// The category, as a colour-coded pill.
///
/// The pill HUGS its label, like the web's inline-flex. Two things make that
/// work in Flutter and both are easy to lose: a Container with an `alignment`
/// expands to its bounded constraints instead of sizing to its child, so the
/// vertical centring is done by an inner Align with widthFactor: 1; and the
/// outer Align keeps the hugged pill at the start of the column rather than
/// centred in the leftover space.
class _CategoryPill extends StatelessWidget {
  final String category;

  const _CategoryPill({required this.category});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) =
        (dark ? _pillDark : _pillLight)[_hash(category) % _pillLight.length];

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kTopicPillMaxWidth),
        child: Container(
          height: kTopicPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: CLType.meta,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tag, with the matched run marked when there is a query.
///
/// No leading "#": the tile to the left of this IS the hash mark, and drawing
/// both put it on the row twice.
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
      return Text(slug,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: slug.substring(0, start)),
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
                CLSkeleton(
                  width: 84,
                  height: kTopicPillHeight,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
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
                  topic.slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: kTopicNameGap),
                // The same pill the rows carry, and the same hashed colour -
                // this card is what a row becomes when you open it, so a
                // category that changed appearance between the two would read
                // as a different category.
                _CategoryPill(category: topic.category),
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
