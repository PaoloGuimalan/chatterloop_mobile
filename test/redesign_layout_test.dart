// Layout regression tests for the redesigned Explore / Contacts /
// Notifications widgets.
//
// These screens need a live login to reach in the running app, so this is the
// verification that they lay out at all: every new card, row, tile and rail is
// pumped at a narrow phone width (360px) with long worst-case strings, and any
// RenderFlex overflow fails the test.
//
// Widget tests render in the test font, where EVERY glyph is a full em square -
// so text here is far wider than the real Inter face at the same size. That
// makes this a useful stress test rather than a false alarm: a row that fits
// under those widths also fits real text at a large accessibility scale. It is
// what caught CLMiniBtn's label not being Flexible.

import 'package:chatterloop_app/core/design/rails.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/entity_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/group_tile.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _longName = "Bartholomew Maximilian Villaverde-Santos";

SearchPersonResult _person({bool followed = false}) => SearchPersonResult(
      entityId: "e1",
      displayName: _longName,
      handle: "bartholomewmaximilian",
      isVerified: true,
      mutualCount: 214,
      isFollowed: followed,
      hasConnection: false,
      connectionAccomplished: false,
      isActionByEntity: false,
    );

SearchRealmResult _realm(String type, {bool member = false}) =>
    SearchRealmResult(
      entityId: "e-$type",
      displayName: "$_longName $type",
      handle: "handle-$type",
      isVerified: true,
      realmType: type,
      membersCount: 1234567,
      followersCount: 4120,
      isFollower: false,
      isMember: member,
      id: "r-$type",
    );

SearchPostResult _post() => SearchPostResult(
      postId: "p1",
      caption:
          "Sunrise run before the rain came in. Pinned the whole route home, "
          "36 km/h downhill is plenty thanks, and the new roast is too sour.",
      contentType: "text",
      fileType: "none",
      datePosted: DateTime.now().subtract(const Duration(hours: 3)),
      likesCount: 24,
      commentsCount: 6,
      author: const SearchPostAuthor(
        entityId: "a1",
        type: "user",
        displayName: _longName,
        handle: "bart",
        isVerified: true,
      ),
    );

NetworkEntityResult _networkItem() => NetworkEntityResult(
      entityId: "u1",
      type: "user",
      displayName: _longName,
      handle: "bartholomewmaximilian",
      isVerified: true,
      id: "id1",
      connectionId: "c1",
      mutualCount: 214,
      isFollowedBack: false,
    );

GroupShortcut _group() => const GroupShortcut(
      targetId: "g1",
      realmId: "g1",
      id: "1",
      displayName: "Sunday Long Run Crew (Metro Manila)",
      handle: "sundaylongrun",
      isVerified: false,
    );

NotificationV2 _notification({bool actionable = false, bool read = false}) =>
    NotificationV2(
      notificationID: "n1",
      referenceID: "ref1",
      // null (not false) for a non-actionable type, matching what the server
      // sends for anything with no reference to resolve.
      referenceStatus: actionable ? false : null,
      fromUserID: "u1",
      fromUser: const NotificationSenderV2(
        entityId: "u1",
        type: "user",
        displayName: _longName,
        handle: "bart",
        isVerified: true,
      ),
      headline: "New contact request",
      details:
          "@bart sent you a contact request and wants to connect with you.",
      date: "07/26/2026",
      time: "9:12 AM",
      type: actionable ? "contact_request" : "post_reaction",
      isRead: read,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    ),
  ));
  // A second frame so the rails' post-frame chevron sync lands - the arrows
  // only exist after it, and they change the section header's layout.
  await tester.pump();
}

void main() {
  testWidgets('Explore rails and cards lay out at 360px', (tester) async {
    await _pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CLChipsRail(children: [
            for (final label in ["All", "People", "Realms", "Posts"])
              CLChip(label: label, icon: Icons.apps),
          ]),
          const SizedBox(height: 20),
          CLRailSection(
            title: "People",
            actionLabel: "See all",
            onAction: () {},
            height: kPersonCardHeight,
            children: [
              SearchPersonCard(
                person: _person(),
                online: true,
                busy: false,
                onToggleFollow: (_) {},
                onOpen: (_) {},
              ),
              SearchPersonCard(
                person: _person(followed: true),
                online: false,
                busy: false,
                onToggleFollow: (_) {},
                onOpen: (_) {},
              ),
              const SearchPersonCardSkeleton(),
            ],
          ),
          const SizedBox(height: 20),
          CLRailSection(
            title: "Realms",
            actionLabel: "See all",
            onAction: () {},
            height: kRealmCardHeight,
            children: [
              // One card per action state: Follow (page), Open (server), Join
              // (group), Open chat (joined group).
              for (final type in ["page", "server", "group"])
                SearchRealmCard(
                  realm: _realm(type),
                  followBusy: false,
                  joinBusy: false,
                  onToggleFollow: (_) {},
                  onJoinGroup: (_) {},
                  onOpen: (_) {},
                ),
              SearchRealmCard(
                realm: _realm("group", member: true),
                followBusy: false,
                joinBusy: false,
                onToggleFollow: (_) {},
                onJoinGroup: (_) {},
                onOpen: (_) {},
              ),
              const SearchRealmCardSkeleton(),
            ],
          ),
          const SizedBox(height: 20),
          SearchRealmCard(
            realm: _realm("group"),
            wide: true,
            followBusy: false,
            joinBusy: false,
            onToggleFollow: (_) {},
            onJoinGroup: (_) {},
            onOpen: (_) {},
          ),
          const SizedBox(height: 10),
          const SearchRealmCardSkeleton(wide: true),
          const SizedBox(height: 10),
          SearchContentCard(post: _post(), onOpen: (_) {}, compact: true),
          const SizedBox(height: 10),
          SearchContentCard(post: _post(), onOpen: (_) {}),
          const SizedBox(height: 10),
          const SearchContentCardSkeleton(),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Contacts rows, group tiles and rail lay out at 360px',
      (tester) async {
    await _pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CLRailSection(
            title: "Group chats",
            actionLabel: "See all 12",
            onAction: () {},
            height: 100,
            children: [
              for (var i = 0; i < 4; i++)
                CLGroupTile(group: _group(), onOpen: (_) {}),
              const CLGroupTileSkeleton(),
            ],
          ),
          const SizedBox(height: 20),
          // One row per section action: message (connection), Follow back
          // (follower), Unfollow (following).
          CLEntityRow(
            entityId: "u1",
            displayName: _longName,
            subtitle: "214 mutual · Active now",
            isVerified: true,
            online: true,
            action: const CLRowIconAction(icon: Icons.forum),
          ),
          const SizedBox(height: 10),
          CLEntityRow(
            entityId: "u2",
            displayName: _longName,
            subtitle: "@bartholomewmaximilian · 12 minutes ago",
            isVerified: true,
            isRealm: true,
            action: CLMiniBtn(label: "Follow back", onPressed: () {}),
          ),
          const SizedBox(height: 10),
          CLEntityRow(
            entityId: _networkItem().entityId,
            displayName: _networkItem().displayName,
            subtitle: "@${_networkItem().handle}",
            action: CLMiniBtn(
                label: "Unfollow",
                variant: CLBtnVariant.outline,
                onPressed: () {}),
          ),
          const SizedBox(height: 10),
          const CLEntityRowSkeleton(),
          const SizedBox(height: 20),
          // The See-all grid layout, at the same cell extent the screen uses.
          SizedBox(
            height: 240,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                mainAxisExtent: 110,
              ),
              itemCount: 6,
              itemBuilder: (_, __) =>
                  CLGroupTile(group: _group(), fillWidth: true, onOpen: (_) {}),
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notification rows lay out at 360px', (tester) async {
    await _pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Actionable rows are the tight case - Confirm/Decline take a column
          // of the row's width.
          CLNotificationRow(
            notification: _notification(actionable: true),
            busy: false,
            onAccept: (_) {},
            onDecline: (_) {},
          ),
          const SizedBox(height: 8),
          CLNotificationRow(
            notification: _notification(actionable: true),
            detail: true,
            busy: false,
            onAccept: (_) {},
            onDecline: (_) {},
          ),
          const SizedBox(height: 8),
          CLNotificationRow(
            notification: _notification(read: true),
            busy: false,
            onAccept: (_) {},
            onDecline: (_) {},
          ),
          const SizedBox(height: 8),
          CLNotificationRow(
            notification: _notification(read: true),
            detail: true,
            busy: false,
            onAccept: (_) {},
            onDecline: (_) {},
          ),
          const SizedBox(height: 8),
          const CLNotificationRowSkeleton(),
          const CLNotificationRowSkeleton(detail: true),
          const SizedBox(height: 8),
          const CLSectionEmpty(
            icon: Icons.groups,
            title: "No group chats yet",
            subtitle: "Group conversations you join show up here.",
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('a contact request is actionable only while pending', () {
    expect(_notification(actionable: true).isActionable, isTrue);
    expect(
      _notification(actionable: true).copyWith(referenceStatus: true).isActionable,
      isFalse,
    );
    // Every other type is never actionable, regardless of referenceStatus.
    expect(_notification().isActionable, isFalse);
  });

  test('compact counts and realm reach labels match web', () {
    expect(clCompactCount(999), "999");
    expect(clCompactCount(1200), "1.2k");
    expect(clCompactCount(2000), "2k");
    expect(clCompactCount(4100000), "4.1M");
    // A page's reach is its followers; every other kind counts members.
    expect(realmReachLabel(_realm("page")), "4.1k followers");
    expect(realmReachLabel(_realm("group")), "1.2M members");
    expect(realmTypeLabel("group"), "Group");
  });

  test('a follow flip patches every section it appears in', () {
    final item = _networkItem();
    final overview = NetworkOverview(
      connections: NetworkOverviewSection(
          hasMore: false, total: 1, results: [item]),
      followers: NetworkOverviewSection(
          hasMore: false, total: 1, results: [item]),
      following: NetworkOverviewSection.empty,
    );
    final patched = overview.patchFollow(item.entityId, true);
    expect(patched.connections.results.first.followsRightNow, isTrue);
    expect(patched.followers.results.first.followsRightNow, isTrue);
    // Totals and paging flags survive the patch.
    expect(patched.connections.total, 1);
  });
}
