// The three Explore card kinds - Flutter counterparts of webapp's
// search/partials PersonCard, RealmCard and ContentCard, at the mobile sizes
// from the mockup (150px person cards, 176px realm cards with a 64px banner in
// the rail; full-width variants in the "See all" lists).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:flutter/material.dart';

// Rail card widths. Taken down from the mockup's 150/176, which were drawn in
// a 428px device frame - on a 360dp phone those left barely more than two cards
// visible, and they got looser still once the type scale shrank the text inside
// them. There are deliberately no HEIGHT constants: CLRailSection measures its
// tallest child, so a card is exactly as tall as its contents.
const double kPersonCardWidth = 132;
const double kRealmCardWidth = 152;

/// Icon and label per realm kind. Only page/server/group can reach the client
/// - channel/conference/voice realms are filtered out server side - but the
/// fallbacks are here anyway rather than crashing on an unexpected type.
IconData realmTypeIcon(String realmType) => switch (realmType) {
      "page" => Icons.flag,
      "server" => Icons.dns,
      "group" => Icons.groups,
      _ => Icons.public,
    };

String realmTypeLabel(String realmType) => switch (realmType) {
      "page" => "Page",
      "server" => "Server",
      "group" => "Group",
      _ => realmType.isEmpty ? "Realm" : realmType,
    };

/// A page's reach is its followers; everything else counts members.
String realmReachLabel(SearchRealmResult realm) {
  if (realm.realmType == "page") {
    final count = realm.followersCount;
    return "${clCompactCount(count)} follower${count == 1 ? '' : 's'}";
  }
  final count = realm.membersCount;
  return "${clCompactCount(count)} member${count == 1 ? '' : 's'}";
}

/// Centered avatar (+ online dot), name, mutual count, Follow/Following.
class SearchPersonCard extends StatelessWidget {
  final SearchPersonResult person;
  final bool online;
  final bool busy;
  final ValueChanged<SearchPersonResult> onToggleFollow;
  final ValueChanged<SearchPersonResult> onOpen;

  const SearchPersonCard({
    super.key,
    required this.person,
    required this.online,
    required this.busy,
    required this.onToggleFollow,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return SizedBox(
      width: kPersonCardWidth,
      child: CLCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => onOpen(person),
              borderRadius: BorderRadius.circular(CLRadii.pill),
              child: CLAvatar(
                id: person.entityId,
                name: person.displayName,
                src: person.profile,
                size: 42,
                online: online,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => onOpen(person),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: CLType.bodySm,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ),
                  if (person.isVerified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified, size: 14, color: p.brand),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "${person.mutualCount} mutual",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: CLType.caption, color: p.text3),
            ),
            const SizedBox(height: 10),
            CLMiniBtn(
              label: person.isFollowed ? "Following" : "Follow",
              block: true,
              variant:
                  person.isFollowed ? CLBtnVariant.soft : CLBtnVariant.primary,
              onPressed: busy ? null : () => onToggleFollow(person),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient banner (hashed off the entity id, so a realm always gets the same
/// colours) with the realm photo overlaid when it has one, name, "Type ·
/// reach", and ONE action per kind: page -> Follow toggle, server -> Open,
/// group -> Join, or Open chat once you're a member.
class SearchRealmCard extends StatelessWidget {
  final SearchRealmResult realm;
  final bool followBusy;
  final bool joinBusy;
  final ValueChanged<SearchRealmResult> onToggleFollow;
  final ValueChanged<SearchRealmResult> onJoinGroup;
  final ValueChanged<SearchRealmResult> onOpen;

  /// Rail cards are pinned to [kRealmCardWidth] with the action under the
  /// meta line; the "See all" list uses a full-width card with a taller
  /// banner and the action inline to the right, per the mockup.
  final bool wide;

  const SearchRealmCard({
    super.key,
    required this.realm,
    required this.followBusy,
    required this.joinBusy,
    required this.onToggleFollow,
    required this.onJoinGroup,
    required this.onOpen,
    this.wide = false,
  });

  Widget _action() {
    if (realm.realmType == "page") {
      return CLMiniBtn(
        label: realm.isFollower ? "Following" : "Follow",
        block: !wide,
        variant: realm.isFollower ? CLBtnVariant.soft : CLBtnVariant.primary,
        onPressed: followBusy ? null : () => onToggleFollow(realm),
      );
    }
    if (realm.realmType == "server") {
      return CLMiniBtn(
        label: "Open",
        block: !wide,
        variant: CLBtnVariant.soft,
        onPressed: () => onOpen(realm),
      );
    }
    if (realm.isMember) {
      return CLMiniBtn(
        label: "Open chat",
        icon: Icons.forum,
        block: !wide,
        variant: CLBtnVariant.soft,
        onPressed: () => onOpen(realm),
      );
    }
    return CLMiniBtn(
      label: "Join",
      block: !wide,
      onPressed: joinBusy ? null : () => onJoinGroup(realm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final gradient = clEntityGradient(realm.entityId);
    final bannerHeight = wide ? 64.0 : 56.0;

    final banner = InkWell(
      onTap: () => onOpen(realm),
      child: Container(
        width: double.infinity,
        height: bannerHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
        ),
        child: realm.profile != null
            ? CLAvatar(
                id: realm.entityId,
                name: realm.displayName,
                src: realm.profile,
                size: wide ? 44 : 38,
                cornerRadius: CLRadii.md,
              )
            : Icon(realmTypeIcon(realm.realmType),
                size: wide ? 28 : 24, color: Colors.white),
      ),
    );

    final title = InkWell(
      onTap: () => onOpen(realm),
      child: Row(
        children: [
          Flexible(
            child: Text(
              realm.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: wide ? 13.5 : 12.5,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
          ),
          if (realm.isVerified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 14, color: p.brand),
          ],
        ],
      ),
    );

    final meta = Text(
      "${realmTypeLabel(realm.realmType)} · ${realmReachLabel(realm)}",
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: wide ? 12 : 11.5, color: p.text3),
    );

    final card = Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          banner,
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            title,
                            const SizedBox(height: 2),
                            meta,
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _action(),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      title,
                      const SizedBox(height: 2),
                      meta,
                      const SizedBox(height: 8),
                      _action(),
                    ],
                  ),
          ),
        ],
      ),
    );

    return wide ? card : SizedBox(width: kRealmCardWidth, child: card);
  }
}

/// Author line, clamped caption, like/comment counters. Tapping opens the real
/// post through the preview screen - this card is deliberately lightweight.
class SearchContentCard extends StatelessWidget {
  final SearchPostResult post;
  final ValueChanged<SearchPostResult> onOpen;

  /// The rail/preview variant runs a step smaller than the "See all" list's.
  final bool compact;

  const SearchContentCard({
    super.key,
    required this.post,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return InkWell(
      onTap: () => onOpen(post),
      borderRadius: BorderRadius.circular(CLRadii.md),
      child: CLCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CLAvatar(
                  id: post.author.entityId,
                  name: post.author.displayName,
                  src: post.author.profile,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    post.author.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                if (post.author.isVerified) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.verified, size: 14, color: p.brand),
                ],
                const Spacer(),
                if (post.datePosted != null)
                  Text(
                    timeSinceShort(post.datePosted!),
                    style: TextStyle(
                        fontSize: compact ? 11.5 : 12, color: p.text3),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              post.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12.5 : 14,
                height: 1.45,
                color: p.text2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Muted like the comment counter - a filled heart here would
                // read as "you reacted to this", which is not what a search
                // result means.
                Icon(Icons.favorite_border,
                    size: compact ? 13 : 14, color: p.text3),
                const SizedBox(width: 4),
                Text("${post.likesCount}",
                    style: TextStyle(
                        fontSize: compact ? 11.5 : 12.5, color: p.text3)),
                const SizedBox(width: 16),
                Icon(Icons.mode_comment_outlined,
                    size: compact ? 13 : 14, color: p.text3),
                const SizedBox(width: 4),
                Text("${post.commentsCount}",
                    style: TextStyle(
                        fontSize: compact ? 11.5 : 12.5, color: p.text3)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -------- Skeletons ----------------------------------------------------------

class SearchPersonCardSkeleton extends StatelessWidget {
  const SearchPersonCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kPersonCardWidth,
      child: CLCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CLSkeleton(
                width: 42,
                height: 42,
                borderRadius: BorderRadius.all(Radius.circular(21))),
            const SizedBox(height: 10),
            const CLSkeleton(width: 84, height: 11),
            const SizedBox(height: 8),
            const CLSkeleton(width: 56, height: 10),
            const SizedBox(height: 10),
            CLSkeleton(
                width: double.infinity,
                height: 28,
                borderRadius: BorderRadius.circular(CLRadii.sm)),
          ],
        ),
      ),
    );
  }
}

class SearchRealmCardSkeleton extends StatelessWidget {
  final bool wide;

  const SearchRealmCardSkeleton({super.key, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final card = Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CLSkeleton(
              width: double.infinity,
              height: wide ? 64 : 56,
              borderRadius: BorderRadius.zero),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const CLSkeleton(width: 100, height: 12),
                const SizedBox(height: 8),
                const CLSkeleton(width: 70, height: 10),
                const SizedBox(height: 10),
                CLSkeleton(
                    width: double.infinity,
                    height: 28,
                    borderRadius: BorderRadius.circular(CLRadii.sm)),
              ],
            ),
          ),
        ],
      ),
    );
    return wide ? card : SizedBox(width: kRealmCardWidth, child: card);
  }
}

class SearchContentCardSkeleton extends StatelessWidget {
  const SearchContentCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const CLCard(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CLSkeleton(
                  width: 28,
                  height: 28,
                  borderRadius: BorderRadius.all(Radius.circular(14))),
              SizedBox(width: 8),
              CLSkeleton(width: 110, height: 11),
            ],
          ),
          SizedBox(height: 12),
          CLSkeleton(width: double.infinity, height: 10),
          SizedBox(height: 7),
          CLSkeleton(width: double.infinity, height: 10),
          SizedBox(height: 12),
          CLSkeleton(width: 90, height: 10),
        ],
      ),
    );
  }
}
