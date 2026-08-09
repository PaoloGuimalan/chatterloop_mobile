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
import 'package:chatterloop_app/core/routes/app_router.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/widgets/entity_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/group_tile.dart';
import 'package:chatterloop_app/core/reusables/widgets/notification_row.dart';
import 'package:chatterloop_app/core/reusables/widgets/search_cards.dart';
import 'package:chatterloop_app/models/notifications_models/notifications_v2_model.dart';
import 'package:chatterloop_app/models/user_models/network_models.dart';
import 'package:chatterloop_app/models/user_models/search_v2_models.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/realm/realm_sections.dart';
import 'package:chatterloop_app/views/realm/realm_manage_view.dart';
import 'package:chatterloop_app/views/servers/create_realm_view.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:chatterloop_app/views/servers/servers_view.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
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
  _rosterIdContracts();

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

  // A photo that isn't square must arrive at its natural proportions and be
  // CROPPED by BoxFit.cover - not squeezed into the box.
  //
  // Image.network's cacheWidth AND cacheHeight together mean
  // ResizeImagePolicy.exact, which decodes to precisely WxH and distorts the
  // aspect ratio. That handed cover an already-square bitmap with nothing left
  // to crop, and every landscape group-chat photo rendered squished across -
  // on the messages list and the contacts group rail alike, since both are
  // CLAvatar.
  testWidgets('an avatar decodes without distorting its aspect ratio',
      (tester) async {
    await _pump(
      tester,
      const CLAvatar(
        id: 'e1',
        name: _longName,
        src: 'https://example.invalid/wide.jpg',
        size: 54,
        cornerRadius: 16,
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);

    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).policy, ResizeImagePolicy.fit);

    // Both caps set with `fit` bounds the LONG edge; the short edge - the one
    // cover has to fill - lands under it, so the cap carries 2x headroom.
    expect(provider.width, 108);
    expect(provider.height, 108);
  });

  testWidgets('a scrollable chips rail shows both chevrons, never a hole',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: CLChipsRail(children: [
            // Long enough labels that the row certainly overflows 360px.
            for (final label in [
              "Group chats · 12",
              "Connections · 38",
              "Followers · 214",
              "Following · 96",
            ])
              CLChip(label: label, icon: Icons.groups),
          ]),
        ),
      ),
    ));
    await tester.pump();

    // At rest the rail sits at its start, so the left chevron cannot scroll -
    // but it must still be RENDERED (dimmed), otherwise its reserved 26px slot
    // is a blank gap to the left of the first chip.
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // Measured on the chip's BOX, not its label - a chip has 14px of padding
    // and an icon before its text.
    final leftArrow = tester.getRect(find.byIcon(Icons.chevron_left));
    final firstChip = tester.getRect(find.byType(CLChip).first);
    // The chevron occupies the space before the chips rather than leaving it
    // empty. Allow 12: the 6px gutter, plus the ~5px by which a 16px glyph
    // falls short of its 26px circle. A reserved-but-empty slot would put ~32
    // here.
    expect(leftArrow.right, lessThan(firstChip.left));
    expect(firstChip.left - leftArrow.right, lessThanOrEqualTo(12));

    expect(tester.takeException(), isNull);
  });

  // The parallax on a page push must NOT run for a see-through route stacked on
  // top: the drift only works because an opaque incoming page hides the gap it
  // leaves behind. Under a transparent route (the message long-press preview)
  // that gap is bare black down the right edge. Testing "is it a PageRoute" was
  // not enough - HeroDialogRoute IS one, since heroes only fly between page
  // routes; it's just not opaque.
  group('page transition', () {
    final bodyKey = UniqueKey();
    final navKey = GlobalKey<NavigatorState>();

    /// Pushes `route` and returns how far the page below moved horizontally,
    /// sampled PART-WAY through the transition. Sampling after it settles isn't
    /// possible for an opaque push - Overlay stops building the covered route,
    /// so there's nothing left to measure - and mid-flight is the more precise
    /// question anyway, since the parallax is a transition effect.
    Future<double> pushAndMeasure(
        WidgetTester tester, Route<void> route) async {
      // No `home:` - it wins over onGenerateRoute for '/', so the route under
      // test would never be built.
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        onGenerateRoute: (_) => CLPageRoute(
          page: CLPage(
            key: const ValueKey('root'),
            child: Container(key: bodyKey, color: const Color(0xFF112233)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byKey(bodyKey)).dx;

      navKey.currentState!.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final shift = tester.getTopLeft(find.byKey(bodyKey)).dx - before;

      await tester.pumpAndSettle();
      return shift;
    }

    testWidgets('a transparent route leaves the page where it is',
        (tester) async {
      // Same shape as flutter_chat_reactions' HeroDialogRoute.
      final shift = await pushAndMeasure(tester, _TransparentPageRoute());
      expect(shift, 0);
    });

    testWidgets('another app page still gets the parallax', (tester) async {
      // Pushing one of our own pages - the only pairing the parallax ever
      // applied to, since a transition needs both canTransitionTo here AND
      // canTransitionFrom on the incoming route, and MaterialPageRoute's
      // requires the route below to be a Material one.
      final shift = await pushAndMeasure(
        tester,
        CLPageRoute(
          page: const CLPage(
            key: ValueKey('next'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      expect(shift, lessThan(0));
    });
  });

  // The two halves of the same bug, which have bitten this app more than once:
  // a PUSHED screen must keep its body clear of the Android nav bar, and a TAB
  // screen must NOT - the shell's bottom nav already consumed that inset, so
  // insetting again leaves a dead strip above the nav bar.
  // Webapp's formPreset / Followers gating, transcribed. These are product
  // decisions with no derivation behind them, so the only thing keeping the
  // two clients in step is that they say the same thing.
  group('manage realm varies by realm kind', () {
    RealmProfile realm(String type, {String? parent}) => RealmProfile(
          id: 'r1',
          entityId: 'e1',
          name: 'Thing',
          type: type,
          parent: parent,
          followersCount: 0,
          isAdmin: true,
        );

    test('each kind gets webapp\'s field preset', () {
      expect(realmFormFields(realm('group')), ['name', 'privacy']);
      expect(realmFormFields(realm('voice')), ['name']);
      expect(realmFormFields(realm('page')),
          ['name', 'description', 'email', 'slug']);
      expect(
          realmFormFields(realm('server')), ['name', 'description', 'privacy']);
    });

    test('a group with a parent is a channel, and loses privacy', () {
      // The one derived kind. Privacy is deliberately not offered on a
      // channel - web notes it needs every server member added on a switch
      // to public.
      expect(realmFormKind(realm('group', parent: 's1')), 'channel');
      expect(realmFormFields(realm('group', parent: 's1')), ['name']);
      // A parentless group is still a group.
      expect(realmFormKind(realm('group')), 'group');
    });

    test('only a page has followers or a dashboard', () {
      // Both gate a section AND, for followers, the count under the realm's
      // name - a group has members, so "0 followers" there is a category
      // error rather than an empty state.
      expect(realmHasFollowers(realm('page')), isTrue);
      expect(realmHasDashboard(realm('page')), isTrue);
      for (final type in ['group', 'server', 'voice']) {
        expect(realmHasFollowers(realm(type)), isFalse, reason: type);
        expect(realmHasDashboard(realm(type)), isFalse, reason: type);
      }
      // A channel is a group, so it inherits the same answer.
      expect(realmHasFollowers(realm('group', parent: 's1')), isFalse);
      expect(realmHasDashboard(realm('group', parent: 's1')), isFalse);
    });

    test('only pages and servers have a cover photo', () {
      // Deliberately NOT web's behaviour - it offers the cover uploader for
      // every kind. A group, channel or voice room renders no banner, so an
      // upload there goes nowhere.
      expect(realmHasCoverPhoto(realm('page')), isTrue);
      expect(realmHasCoverPhoto(realm('server')), isTrue);
      for (final type in ['group', 'voice']) {
        expect(realmHasCoverPhoto(realm(type)), isFalse, reason: type);
      }
      expect(realmHasCoverPhoto(realm('group', parent: 's1')), isFalse);
    });

    test('slug belongs to pages alone', () {
      // A group has no slug field to show, so nothing may send one either.
      for (final type in ['group', 'voice', 'server']) {
        expect(realmFormFields(realm(type)), isNot(contains('slug')));
      }
    });

    test('an unknown kind falls back to the one universal field', () {
      expect(realmFormFields(realm('something-new')), ['name']);
    });

    test('you are never removable from your own roster', () {
      // Removing yourself here is a demotion with no way back - you would
      // lose the screen that does it. Leaving is a deliberate action in the
      // conversation menu instead.
      appStore.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount('account-me', 'me', 'Me', '', 'Mine', null, true, true,
                null, null, null, null,
                personalEntityId: 'entity-me')),
      ));

      const me = RealmPerson(
          entityId: 'entity-me',
          accountId: 'account-me',
          displayName: 'Me',
          handle: 'me');
      const alsoMe = RealmPerson(
          entityId: 'entity-me',
          accountId: '',
          displayName: 'Me',
          handle: 'me');
      const someoneElse = RealmPerson(
          entityId: 'entity-other',
          accountId: 'account-other',
          displayName: 'Other',
          handle: 'other');

      expect(isSelf(me), isTrue);
      // Either id matching is enough - the two lists key on different ones.
      expect(isSelf(alsoMe), isTrue);
      expect(isSelf(someoneElse), isFalse);

      // An unresolved row must not read as "you" just because both ids are
      // blank.
      const unresolved =
          RealmPerson(entityId: '', accountId: '', displayName: '', handle: '');
      expect(isSelf(unresolved), isFalse);
    });
  });

  group('sheet bottom gap', () {
    Future<double> gapUnder(WidgetTester tester, double inset,
        {double minimum = 12}) async {
      late double gap;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: inset)),
        child: Builder(builder: (context) {
          gap = clSheetBottomGap(context, minimum: minimum);
          return const SizedBox();
        }),
      ));
      return gap;
    }

    testWidgets('clears a button nav bar without stacking onto it',
        (tester) async {
      // The band of dead surface at the bottom of a sheet is this value being
      // ADDED to the content's own padding instead of replacing it.
      expect(await gapUnder(tester, 48), 48);
      expect(await gapUnder(tester, 48, minimum: 16), 48);
    });

    testWidgets('keeps a comfortable gap where there is no inset',
        (tester) async {
      // Gesture navigation reports ~0, and a sheet flush against the screen
      // edge is what the flat padding was there to avoid.
      expect(await gapUnder(tester, 0), 12);
      expect(await gapUnder(tester, 8), 12);
    });
  });

  group('system nav bar insets', () {
    const navBarHeight = 48.0;
    const screenHeight = 780.0;
    final bodyKey = UniqueKey();

    Future<Size> pumpBody(
        WidgetTester tester, Widget Function(Widget) wrap) async {
      tester.view.physicalSize = const Size(360, screenHeight);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewPadding = const FakeViewPadding(bottom: navBarHeight);
      tester.view.padding = const FakeViewPadding(bottom: navBarHeight);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: wrap(SizedBox.expand(key: bodyKey)),
      ));
      return tester.getSize(find.byKey(bodyKey));
    }

    testWidgets('CLScreen holds its body above the nav bar', (tester) async {
      final size = await pumpBody(tester, (body) => CLScreen(body: body));
      expect(size.height, screenHeight - navBarHeight);
    });

    testWidgets('a tab Scaffold fills the full height', (tester) async {
      // What Explore/Contacts/Messages do - the shell owns the inset.
      final size = await pumpBody(tester, (body) => Scaffold(body: body));
      expect(size.height, screenHeight);
    });
  });

  test('a contact request is actionable only while pending', () {
    expect(_notification(actionable: true).isActionable, isTrue);
    expect(
      _notification(actionable: true)
          .copyWith(referenceStatus: true)
          .isActionable,
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
      connections:
          NetworkOverviewSection(hasMore: false, total: 1, results: [item]),
      followers:
          NetworkOverviewSection(hasMore: false, total: 1, results: [item]),
      following: NetworkOverviewSection.empty,
    );
    final patched = overview.patchFollow(item.entityId, true);
    expect(patched.connections.results.first.followsRightNow, isTrue);
    expect(patched.followers.results.first.followsRightNow, isTrue);
    // Totals and paging flags survive the patch.
    expect(patched.connections.total, 1);
  });
}

/// A stand-in for flutter_chat_reactions' HeroDialogRoute: a PageRoute (it must
/// be one, so heroes can fly to it) that does NOT cover the page below.
class _TransparentPageRoute extends PageRoute<void> {
  @override
  bool get opaque => false;

  @override
  Color get barrierColor => const Color(0x8A000000);

  @override
  String get barrierLabel => 'test overlay';

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      const SizedBox.shrink();
}

// The ids each realm-roster action is keyed by. Every one of these is a
// field name that lies about its contents, and getting one wrong produces a
// request that SUCCEEDS and does nothing - which is exactly how remove and
// leave failed the first time.
void _rosterIdContracts() {
  group('realm roster ids', () {
    test('removing a member is keyed by entity id, not account id', () {
      final person = RealmPerson.fromMemberJson({
        'member_id': 'm1',
        'realm': 'r1',
        'role': 'admin',
        'entity': {
          'id': 'entity-1',
          'details': {'id': 'account-1', 'username': 'bart'},
        },
      });

      // `account_ids` takes this one, despite its name.
      expect(person.removalId, 'entity-1');
      expect(person.entityId, 'entity-1');
      expect(person.accountId, 'account-1');
      // The role endpoint takes the member ROW's id instead.
      expect(person.memberId, 'm1');
      expect(person.realmId, 'r1');
      expect(person.isRealmAdmin, isTrue);
    });

    test('removing a follower is keyed by the follow row', () {
      final person = RealmPerson.fromFollowerJson({
        'follow_id': 'f1',
        'follower': {
          'id': 'entity-2',
          'details': {'id': 'account-2', 'username': 'nia'},
        },
      });

      expect(person.removalId, 'f1');
      // A follower has no role and no member row.
      expect(person.role, isNull);
      expect(person.memberId, isEmpty);
    });
  });

  group('removed from a realm', () {
    test('the removal is keyed by realm_id, and the kind comes with it', () {
      // The Node payload, verbatim from routes/realms/index.js - published to
      // events_<entity_id> for each removed member, which is why nothing
      // downstream checks whether it is about you.
      final removal = realmRemovalFromSseEvent({
        'status': true,
        'auth': true,
        'onseen': false,
        'message': 'User removed from realm realm-9',
        'result': {
          'realm_id': 'realm-9',
          'entityID': 'entity-me',
          'type': 'server',
        },
      });

      expect(removal, isNotNull);
      // realm_id, not id - the screens compare this against the server they are
      // showing, so reading the wrong key means never getting out of it.
      expect(removal!.realmId, 'realm-9');
      expect(removal.type, 'server');
    });

    test('anything without a realm_id is ignored', () {
      expect(realmRemovalFromSseEvent({'status': true}), isNull);
      expect(realmRemovalFromSseEvent({'result': 'not a map'}), isNull);
      expect(
          realmRemovalFromSseEvent({
            'result': {'type': 'server'}
          }),
          isNull);
    });

    test('two removals of the same realm both notify', () {
      // Identity equality, deliberately: ValueNotifier drops an equal value, so
      // being removed, added back and removed again would fire once with a
      // value type.
      final first = RealmRemoval('r1', 'server');
      final second = RealmRemoval('r1', 'server');
      expect(first == second, isFalse);
    });
  });

  group('server directory card', () {
    // The real cell: two up at 0.78, in the width the pane actually has on a
    // 360px phone once the 60px rail and the list gutters are taken out.
    Future<void> pumpCards(WidgetTester tester, Widget card) => _pump(
          tester,
          SizedBox(
            width: 360 - 61 - 28,
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: [card, card],
            ),
          ),
        );

    RealmProfile server({String? description}) => RealmProfile(
          id: 'srv-1',
          entityId: 'ent-1',
          name: _longName,
          type: 'server',
          description: description,
          followersCount: 0,
          membersCount: 12840,
          isVerified: true,
          isAdmin: false,
        );

    testWidgets('fits a long name and a long description', (tester) async {
      await pumpCards(
          tester,
          ServerCard(
            server: server(
                description: 'A very long server description that goes on '
                    'well past the three lines this card can show, to prove '
                    'the cell clips it instead of growing.'),
            isMember: false,
            busy: false,
            onOpen: () {},
            onJoin: () {},
          ));
      expect(find.text('Join'), findsNWidgets(2));
    });

    testWidgets('fits with no description at all', (tester) async {
      await pumpCards(
          tester,
          ServerCard(
            server: server(),
            isMember: true,
            busy: false,
            onOpen: () {},
            onJoin: () {},
          ));
      // A member gets Open, and the placeholder stands in for the description
      // so the button does not float up to the avatar.
      expect(find.text('Open'), findsNWidgets(2));
      expect(find.text('No description'), findsNWidgets(2));
    });

    testWidgets('the skeleton fits the same cell', (tester) async {
      await pumpCards(tester, const ServerCardSkeleton());
    });
  });

  group('creating a server or a channel', () {
    test('a server picks members globally', () {
      // Both privacies: a private SERVER still starts with only you in it, so
      // it still asks. Only a channel's privacy decides whether it asks at all.
      for (final isPrivate in [true, false]) {
        expect(
          createRealmMemberSource(isChannel: false, isPrivate: isPrivate),
          CreateRealmMemberSource.globalEntities,
          reason: 'private=$isPrivate',
        );
      }
    });

    test('a private channel picks from the parent server only', () {
      // The product rule: you can only add someone to a channel who is
      // already in the server that owns it, so a global search here would
      // list people who cannot be added and fail only after selecting them.
      expect(
        createRealmMemberSource(isChannel: true, isPrivate: true),
        CreateRealmMemberSource.parentServerMembers,
      );
    });

    test('a public channel picks nobody', () {
      // Membership follows the server, which is why web hides the picker
      // entirely - and why the payload must carry no members even if some were
      // ticked before the privacy was switched back.
      expect(
        createRealmMemberSource(isChannel: true, isPrivate: false),
        CreateRealmMemberSource.none,
      );
    });

    test('the two create endpoints are the ones webapp posts to', () {
      // Both live on the /u/ router, not /s/ - and they are separate routes,
      // which is the mistake worth pinning: a channel posted to createserver
      // would create a top-level server named after the channel.
      final endpoints = Endpoints();
      expect(endpoints.createServer, '/u/createserver');
      expect(endpoints.createChannel, '/u/createchannel');
      // And the server-specific add, which fans out to the public channels.
      expect(endpoints.addNewMemberToServer, '/s/addnewmembertoserver');
      expect(endpoints.addNewMember, '/m/addnewmember');
    });
  });
}
