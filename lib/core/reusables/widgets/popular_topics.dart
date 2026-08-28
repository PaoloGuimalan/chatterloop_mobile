// Popular Topics - the "ranked list" direction (1b).
//
// One card, vertical numbered rows, so it reads as a CHART rather than a rail:
// no horizontal scrubbing, and the ordering is the information. Rendered in two
// places from the same widget - Explore's idle state and a Newsfeed section -
// with a topic detail feed behind each row.
//
// Cards carry topic name, category and participant avatars ONLY. No post
// counts: a count is a number the reader cannot act on, and the rank already
// says everything the count would.
//
// There is deliberately no follow/following affordance. Topics are a discovery
// surface here, not something with a subscription behind it.

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/interests_api.dart';
import 'package:chatterloop_app/models/user_models/popular_topic_model.dart';
import 'package:flutter/material.dart';

/// The full chart, and what the endpoint caps at anyway. Explore shows this -
/// the same eight the web rail shows.
const int kPopularTopicMax = 8;

/// The feed's teaser. Three rows, because the newsfeed is somewhere you are
/// already reading something else: the section is a pointer to Explore, not a
/// destination, and eight rows between the composer and the first post pushes
/// the feed itself off the screen.
const int kPopularTopicFeedPreview = 3;

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

/// Row metrics, shared by the row and its skeleton so the two cannot drift -
/// a loader of a different height makes the card resize when data lands.
const double kTopicRowPaddingV = 12;
const double kTopicRowPaddingH = 14;
const double kTopicRankWidth = 20;
const double kTopicNameHeight = 17;
const double kTopicNameGap = 2;
const double kTopicPillHeight = 20;

/// Matches the web's .cl-topic-pill max-width, so a long category ellipsises
/// rather than shoving the avatars off the row.
const double kTopicPillMaxWidth = 160;
const double kTopicFaceSize = 24;

/// How far each avatar laps the one before it.
const double kTopicFaceOverlap = 9;

class CLPopularTopics extends StatefulWidget {
  final void Function(PopularTopic topic) onTopicTap;

  /// The section's action, labelled "Explore" because that is where it goes -
  /// "See all" would be a promise of more of the same list, when the newsfeed's
  /// three rows actually hand off to a different screen.
  ///
  /// Omitted when null: Explore already shows the full chart, so there is
  /// nothing for it to link to there.
  final VoidCallback? onExplore;

  /// How many rows to show. Explore shows the lot; the newsfeed teases three.
  final int limit;

  const CLPopularTopics({
    super.key,
    required this.onTopicTap,
    this.onExplore,
    this.limit = kPopularTopicMax,
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
    final p = cl(context);

    // Renders nothing at all once it is known there is nothing to show, rather
    // than an empty card. A brand-new platform legitimately has no popular
    // topics yet, and a surface should not lead with an empty box.
    if (_loaded && _topics.isEmpty) return const SizedBox.shrink();

    final rows = _loaded
        ? List.generate(_topics.length, (i) => (i, _topics[i]))
        : const <(int, PopularTopic)>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same header component the People and Realms sections use, so this
        // reads as one more section rather than a bolted-on panel.
        CLSectionHeader(
          title: "Popular topics",
          actionLabel: widget.onExplore == null ? null : "Explore",
          onAction: widget.onExplore,
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(CLRadii.md),
          ),
          // So the row dividers stop at the rounded corners.
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_loaded)
                for (var i = 0; i < widget.limit; i++) ...[
                  if (i > 0) const _TopicDivider(),
                  const CLPopularTopicsRowSkeleton(),
                ]
              else
                for (final (index, topic) in rows) ...[
                  if (index > 0) const _TopicDivider(),
                  CLPopularTopicsRow(
                    topic: topic,
                    rank: index + 1,
                    onTap: () => widget.onTopicTap(topic),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Inset by the row's own horizontal padding, so it reads as separating rows
/// rather than cutting the card in half.
class _TopicDivider extends StatelessWidget {
  const _TopicDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kTopicRowPaddingH),
      child: Container(height: 1, color: cl(context).border),
    );
  }
}

/// Exposed (rather than private) so its layout can be measured in a widget
/// test - row sizing is the kind of thing that only breaks visually.
class CLPopularTopicsRow extends StatelessWidget {
  final PopularTopic topic;

  /// 1-based position in the chart. The leader is brand-coloured and the rest
  /// are muted, so the top of the list is readable at a glance.
  final int rank;
  final VoidCallback onTap;

  const CLPopularTopicsRow({
    super.key,
    required this.topic,
    required this.rank,
    required this.onTap,
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
            horizontal: kTopicRowPaddingH,
          ),
          child: Row(
            children: [
              SizedBox(
                width: kTopicRankWidth,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: CLType.sectionTitle,
                    fontWeight: FontWeight.w800,
                    color: rank == 1 ? p.brand : p.text3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        // Pinned so the row's height is deterministic rather
                        // than a property of whatever font the device
                        // resolves - the skeleton reserves exactly this.
                        height: kTopicNameHeight / 13.5,
                      ),
                    ),
                    const SizedBox(height: kTopicNameGap),
                    _CategoryPill(category: topic.category),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _FaceStack(faces: topic.faces),
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The overlapping participant avatars. Drawn right-to-left so the first
/// participant ends up on top.
class _FaceStack extends StatelessWidget {
  final List<PopularTopicFace> faces;
  final double size;

  const _FaceStack({required this.faces, this.size = kTopicFaceSize});

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
                  border: Border.all(color: p.surface, width: 2),
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

/// Shaped like CLPopularTopicsRow off the SAME constants, so the card cannot
/// resize when the data lands.
class CLPopularTopicsRowSkeleton extends StatelessWidget {
  const CLPopularTopicsRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: kTopicRowPaddingV,
        horizontal: kTopicRowPaddingH,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: kTopicRankWidth,
            child: Center(child: CLSkeleton(width: 10, height: 15)),
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
/// size, with a "#" tile standing in for the avatar a person or page would
/// have. No follow control: see the file header.
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
