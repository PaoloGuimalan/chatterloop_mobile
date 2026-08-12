import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_composer.dart';
import 'package:chatterloop_app/core/reusables/widgets/report_sheet.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/profile/widgets/diary_card.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_feed.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class UserProfileScreen extends StatefulWidget {
  final String username;
  const UserProfileScreen({super.key, required this.username});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  /// The feed renders as a section of THIS screen's scroll view (see
  /// ProfileFeed), so paging is driven from here rather than by a nested
  /// scrollable of its own.
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ProfileFeedState> _feedKey = GlobalKey<ProfileFeedState>();

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _feedKey.currentState?.loadMore();
    }
  }

  PublicProfile? profile;
  bool isLoading = true;
  bool notFound = false;
  bool isConnectionActionLoading = false;
  bool isOpeningMessage = false;
  bool isPokeLoading = false;

  /// Following is entity->entity now, so a person can be followed exactly
  /// like a page. Mirrored into local state so the button flips immediately.
  bool _isFollowing = false;

  /// A follow of a PRIVATE profile that its owner has not approved yet.
  /// Mutually exclusive with [_isFollowing] - together they give the button
  /// its three states.
  bool _isFollowPending = false;
  bool _isUpdatingFollow = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
    profileRelationshipUpdates.addListener(_onRelationshipUpdate);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    profileRelationshipUpdates.removeListener(_onRelationshipUpdate);
    super.dispose();
  }

  /// Refresh when the person whose profile is on screen answers a request we
  /// sent them - a contact accept, or a follow-request approval.
  ///
  /// Matched against THIS profile's entity id: the event names the other
  /// party, and refreshing on an unaddressed one would reload whatever screen
  /// happened to be open. Without this the button keeps reading "Requested",
  /// and a private profile stays locked, until a manual pull-to-refresh.
  void _onRelationshipUpdate() {
    final changed = profileRelationshipUpdates.value;
    if (changed == null || changed.entityId.isEmpty) return;
    if (profile?.entityId != changed.entityId) return;
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getPublicProfileRequest(widget.username);
    if (!mounted) return;

    // /api/user/auth/:handle/ serves people AND pages from one route. A realm
    // payload has none of the user fields this screen reads, so it would
    // render a blank profile with dead buttons - hand it to the realm screen
    // instead. pushReplacement so Back doesn't land on the broken screen.
    if (result != null && result.isRealmPayload) {
      context.pushReplacement('/realm/${result.slug ?? widget.username}');
      return;
    }

    setState(() {
      profile = result;
      notFound = result == null;
      isLoading = false;
      _isFollowing = result?.isFollower ?? false;
      _isFollowPending = result?.isFollowPending ?? false;
    });
  }

  /// Follow/unfollow this person. Same endpoint pages use - it takes any
  /// entity id. Optimistic, like the realm profile's follow button.
  Future<void> _toggleFollow() async {
    if (profile == null || _isUpdatingFollow) return;

    final wasFollowing = _isFollowing;
    final wasPending = _isFollowPending;

    // Pending counts as "on": cancelling a request is the same DELETE as
    // unfollowing, since it drops the row whatever its status.
    final isActive = wasFollowing || wasPending;

    setState(() {
      _isUpdatingFollow = true;
      _isFollowing = !isActive;
      _isFollowPending = false;
    });

    final result = await ProfileApi()
        .setEntityFollowRequest(entityId: profile!.entityId, follow: !isActive);

    if (!mounted) return;
    setState(() {
      _isUpdatingFollow = false;
      if (!result.ok) {
        // Restore BOTH flags - assuming !was would lose the pending state.
        _isFollowing = wasFollowing;
        _isFollowPending = wasPending;
      } else if (!isActive && result.isPending) {
        // This profile is private, so the follow did not take effect - it is
        // a request awaiting approval, not an established follow.
        _isFollowing = false;
        _isFollowPending = true;
      }
    });
  }

  Future<void> _addContact() async {
    if (profile == null) return;
    setState(() => isConnectionActionLoading = true);
    final ok = await ContactsApi().requestContactRequest(profile!.entityId);
    if (!mounted) return;
    setState(() => isConnectionActionLoading = false);
    if (ok) await _load();
  }

  /// "cancel" a request you sent, or "decline" one sent to you - both use
  /// the same DELETE endpoint, just a different action header. Matches
  /// webapp's Profile.tsx initiateConnectionProcess("cancel"/"decline").
  Future<void> _declineConnection(String action) async {
    if (profile == null || profile!.connectionId == null) return;
    setState(() => isConnectionActionLoading = true);
    final ok = await ContactsApi().declineContactRequest(
        connectionId: profile!.connectionId!,
        entityId: profile!.entityId,
        action: action);
    if (!mounted) return;
    setState(() => isConnectionActionLoading = false);
    if (ok) await _load();
  }

  Future<void> _acceptConnection() async {
    if (profile == null || profile!.connectionId == null) return;
    setState(() => isConnectionActionLoading = true);
    final ok = await ContactsApi().acceptContactRequest(
        connectionId: profile!.connectionId!, entityId: profile!.entityId);
    if (!mounted) return;
    setState(() => isConnectionActionLoading = false);
    if (ok) await _load();
  }

  /// Only reachable once already connected (mirrors webapp - server also
  /// enforces this, 403ing otherwise). Poke doesn't change any connection
  /// state, so there's nothing to reload after - just surface the
  /// server's message ("You poked @username" / a rejection reason) as a
  /// toast, same as webapp's alert.
  Future<void> _pokeUser() async {
    if (profile == null) return;
    setState(() => isPokeLoading = true);
    final result = await ContactsApi().pokeUserRequest(profile!.id);
    if (!mounted) return;
    setState(() => isPokeLoading = false);
    if (result.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message!)),
      );
    }
  }

  /// Mirrors webapp's Profile.tsx Message button: independent of
  /// connection status. If already connected, jump straight to the
  /// existing conversation; otherwise get-or-create one via /m/crtc.
  Future<void> _openMessage() async {
    if (profile == null) return;

    if (profile!.connectionAccomplished == true &&
        profile!.connectionId != null) {
      context.push('/conversation/${profile!.connectionId}');
      return;
    }

    setState(() => isOpeningMessage = true);
    final conversationId = await ConversationsApi()
        .createInitialConversationRequest(profile!.entityId);
    if (!mounted) return;
    setState(() => isOpeningMessage = false);

    if (conversationId != null) {
      context.push('/conversation/$conversationId');
    }
  }

  /// Block from the profile - webapp's blockUserProcess: confirm, then
  /// POST /api/user/blocks {entityID}, and on success leave the (now-blocked)
  /// profile. The confirm step is a dialog rather than the webapp's inline
  /// two-tap button.
  /// Unfriend an established connection. Webapp removes it on the first tap;
  /// on mobile a mis-tap is far likelier (the button sits next to Poke and
  /// Message), and removing is destructive and silent - the other side just
  /// disappears from both contact lists - so it confirms first. Uses the
  /// same "remove" action as cancelling a pending request.
  Future<void> _removeConnection() async {
    if (profile == null || profile!.connectionId == null) return;
    final p = cl(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Remove @${profile!.username}?',
            style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
        content: Text(
          "You'll both be removed from each other's contacts. You can send a new request later.",
          style: TextStyle(color: p.text2, fontSize: CLType.body),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: p.text2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: p.pink),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _declineConnection("remove");
  }

  Future<void> _blockUser() async {
    if (profile == null) return;
    final p = cl(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Block @${profile!.username}?',
            style: TextStyle(color: p.text, fontSize: CLType.screenTitle)),
        content: Text(
          "They won't be able to contact you, see your posts, or find your profile in search.",
          style: TextStyle(color: p.text2, fontSize: CLType.body),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: p.text2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: p.pink),
              child: const Text('Block')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await SettingsApi().blockAccount(profile!.entityId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message ??
            (result.ok ? 'Account blocked' : 'Could not block this account'))));
    if (result.ok) {
      // Refresh the contacts + conversations lists so the now-blocked account
      // (and any conversation with them) drops off those tabs immediately,
      // then leave the profile.
      await _refreshListsAfterBlock();
      if (!mounted) return;
      context.pop();
    }
  }

  /// Re-fetch the contacts and conversation lists into Redux after a block.
  /// Both tabs read straight from Redux and each only auto-fetches once (an
  /// isInitialized guard), so without this the blocked user/conversation
  /// would linger on those tabs until a full app restart.
  Future<void> _refreshListsAfterBlock() async {
    final store = StoreProvider.of<AppState>(context);
    final convRes = await ConversationsApi().getConversationListRequest();
    if (convRes != null) {
      store.dispatch(DispatchModel(setMessagesListT, convRes.items));
    }
    final contactsRes = await ContactsApi().getContactsRequest();
    store.dispatch(DispatchModel(setContactsListT, contactsRes.results));
  }

  /// Report this account. The sheet itself lives in report_sheet.dart - every
  /// surface that can file a report shares it.
  void _openReportSheet() {
    if (profile == null) return;
    showReportSheet(
      context,
      targetType: ReportTargetType.user,
      targetId: profile!.entityId,
    );
  }

  /// Never show block/report on your own profile (reachable if you open your
  /// own username via search) - the server would reject it anyway.
  bool _isSelf(BuildContext context) {
    if (profile == null) return false;
    final me = StoreProvider.of<AppState>(context).state.userAuth.user;
    return me.username == profile!.username;
  }

  /// Opens the composer in avatar/cover mode. Changing either IS a post -
  /// Node's /createpost writes user_account.profile/.coverphoto and files the
  /// feed entry in one call - so afterwards both the profile and its feed are
  /// reloaded rather than just one of them.
  Future<void> _changeProfileMedia(ComposerMode mode) async {
    final saved = await showCreatePostSheet(context, mode: mode);
    if (!saved || !mounted) return;
    await _load();
    _feedKey.currentState?.reload();
  }

  /// This profile as a tag chip for the composer. The picker speaks
  /// SearchResultUser, and a profile payload carries everything it needs -
  /// so no lookup, and the chip is there before the sheet even opens.
  SearchResultUser? _profileAsTag() {
    if (profile == null || profile!.entityId.isEmpty) return null;
    return SearchResultUser(
      id: profile!.id,
      entityId: profile!.entityId,
      username: profile!.username,
      firstName: profile!.firstName,
      middleName: profile!.middleName,
      lastName: profile!.lastName,
      profile: profile!.profile,
      hasConnection: profile!.hasConnection == true,
      connectionAccomplished: profile!.connectionAccomplished == true,
      isActionByEntity: false,
    );
  }

  Widget _moreMenu(CLPalette p) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PopupMenuButton<String>(
        tooltip: 'More',
        color: p.surface,
        onSelected: (v) {
          if (v == 'report') _openReportSheet();
          if (v == 'block') _blockUser();
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'report',
            child: Row(children: [
              Icon(Icons.report, size: 18, color: p.pink),
              const SizedBox(width: 10),
              Text('Report', style: TextStyle(color: p.pink)),
            ]),
          ),
          PopupMenuItem(
            value: 'block',
            child: Row(children: [
              Icon(Icons.block, size: 18, color: p.pink),
              const SizedBox(width: 10),
              Text('Block', style: TextStyle(color: p.pink)),
            ]),
          ),
        ],
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
            ],
          ),
          child: Icon(Icons.more_vert, size: 18, color: p.text),
        ),
      ),
    );
  }

  /// Mirrors webapp's four connection states exactly (Profile.tsx): no
  /// connection yet -> Add; a pending request you sent -> Cancel Request;
  /// a pending request they sent -> Accept/Decline; already connected ->
  /// Connected + Poke. Message shows alongside independent of connection
  /// state, EXCEPT on a locked profile (canView false), where it is hidden.
  Widget _connectionActions(CLPalette p) {
    final rows = <Widget>[];

    // Your own profile has no connection actions - it shows account state
    // instead. Carried over from the old in-shell profile tab this screen
    // replaced, so nothing was lost when the two merged into one screen.
    if (_isSelf(context)) {
      final me = StoreProvider.of<AppState>(context).state.userAuth.user;
      if (me.isVerified) return const SizedBox.shrink();
      return const CLBadge(
          label: "Email not verified", tone: CLBadgeTone.pink);
    }

    // Follow is independent of the connection state - you can follow someone
    // you are not connected to, exactly as on a page.
    rows.add(CLBtn(
      label: _isUpdatingFollow
          ? "…"
          : _isFollowing
              ? "Following"
              : _isFollowPending
                  ? "Requested"
                  : "Follow",
      size: CLBtnSize.md,
      // "Requested" is already actioned, so it reads like "Following" rather
      // than an untouched call to action.
      variant: (_isFollowing || _isFollowPending)
          ? CLBtnVariant.outline
          : CLBtnVariant.soft,
      onPressed: _isUpdatingFollow ? null : _toggleFollow,
    ));

    if (profile!.hasConnection == false) {
      rows.add(CLBtn(
        label: isConnectionActionLoading ? "Sending…" : "Add Contact",
        size: CLBtnSize.md,
        variant: CLBtnVariant.soft,
        onPressed: isConnectionActionLoading ? null : _addContact,
      ));
    } else if (profile!.hasConnection == true &&
        profile!.connectionAccomplished != true) {
      if (profile!.isConnectionInitiator == true) {
        rows.add(CLBtn(
          label: isConnectionActionLoading ? "Cancelling…" : "Cancel Request",
          size: CLBtnSize.md,
          variant: CLBtnVariant.danger,
          onPressed: isConnectionActionLoading
              ? null
              : () => _declineConnection("remove"),
        ));
      } else {
        rows.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CLBtn(
              label: isConnectionActionLoading ? "…" : "Accept",
              size: CLBtnSize.md,
              onPressed: isConnectionActionLoading ? null : _acceptConnection,
            ),
            const SizedBox(width: 8),
            CLBtn(
              label: "Decline",
              size: CLBtnSize.md,
              variant: CLBtnVariant.outline,
              onPressed: isConnectionActionLoading
                  ? null
                  : () => _declineConnection("decline"),
            ),
          ],
        ));
      }
    } else if (profile!.hasConnection == true &&
        profile!.connectionAccomplished == true) {
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CLBtn(
            label: isConnectionActionLoading ? "Removing…" : "Connected",
            iconL: Icons.how_to_reg,
            size: CLBtnSize.md,
            variant: CLBtnVariant.outline,
            onPressed: isConnectionActionLoading ? null : _removeConnection,
          ),
          const SizedBox(width: 8),
          CLBtn(
            label: isPokeLoading ? "…" : "Poke",
            size: CLBtnSize.md,
            variant: CLBtnVariant.outline,
            onPressed: isPokeLoading ? null : _pokeUser,
          ),
        ],
      ));
    }

    // Message is hidden on a locked profile. canView false means private AND
    // we are neither an accepted connection nor an approved follower - so
    // offering to open a conversation would be offering a way around the
    // privacy setting. Follow / Add Contact stay, since requesting access is
    // exactly what should still be possible from here.
    final canMessage = profile?.canView != false;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canMessage)
          CLBtn(
            label: isOpeningMessage ? "Opening…" : "Message",
            size: CLBtnSize.md,
            onPressed: isOpeningMessage ? null : _openMessage,
          ),
        ...rows,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return CLScreen(
      backgroundColor: p.bg,
      // Transparent + extended behind the body so the back button floats
      // over the cover photo, matching webapp's floating circular back
      // button on the profile page instead of a hard app-bar strip.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.surface,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
              ],
            ),
            child: Icon(Icons.arrow_back, size: 18, color: p.text),
          ),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (!isLoading && !notFound && profile != null && !_isSelf(context))
            _moreMenu(p),
        ],
      ),
      body: isLoading
          ? const SingleChildScrollView(child: ProfileHeaderSkeleton())
          : notFound || profile == null
              ? Center(
                  child: Text("This profile is unavailable",
                      style: TextStyle(color: p.text2)))
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      StoreConnector<AppState, bool>(
                        distinct: true,
                        converter: (store) =>
                            store.state.presence[profile!.entityId]?.online ??
                            false,
                        builder: (context, online) => ProfileHeader(
                          id: profile!.id,
                          displayName: profile!.displayName,
                          username: profile!.username,
                          email: profile!.email,
                          avatarSrc: profile!.profile,
                          coverSrc: profile!.coverphoto,
                          isBadged: profile!.isBadged,
                          isPrivate: profile!.isPrivate,
                          gender: profile!.gender,
                          online: online,
                          // OWNER ONLY, and "owner" means the acting entity
                          // IS this profile - the same rule the composer and
                          // the post options use. Everyone else gets no camera
                          // button at all, so there is nothing to press; the
                          // server enforces it too, since it writes the avatar
                          // of whoever the token says is posting.
                          onChangeAvatar: isActingEntity(profile!.entityId)
                              ? () => _changeProfileMedia(
                                  ComposerMode.profilePhoto)
                              : null,
                          onChangeCover: isActingEntity(profile!.entityId)
                              ? () => _changeProfileMedia(
                                  ComposerMode.coverPhoto)
                              : null,
                          joinedLabel:
                              formattedDateToWords(profile!.joinedDate),
                          birthdateLabel: formattedBirthdate(
                              profile!.birthMonth,
                              profile!.birthDay,
                              profile!.birthYear),
                          actions: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
                            child: _connectionActions(p),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // A locked profile still renders its header above - name,
                      // photos, join date and the follow/connect actions - so
                      // it stays identifiable enough to send a request to. Only
                      // the content below is withheld, and it says so rather
                      // than showing an empty card that reads as broken.
                      if (!profile!.canView)
                        _LockedProfileNotice(
                            displayName: profile!.displayName)
                      else
                        // Renders on anyone's profile - the totals endpoint is
                        // public - but only links through on your own, since
                        // the entries themselves are self-only.
                        ProfileDiaryCard(
                          username: profile!.username,
                          isSelf: _isSelf(context),
                        ),
                      // Posts only on a profile you're allowed to see - the
                      // endpoint enforces this too, but asking for a locked
                      // profile's feed just to render an empty section is a
                      // request that can only ever come back empty.
                      if (profile!.canView) ...[
                        const SizedBox(height: 16),
                        // Sits directly above the feed, like web's. Gated on
                        // the same canView as the feed itself: writing on a
                        // profile means tagging its owner in a post, and a
                        // profile you can't see isn't one you can write on.
                        // No entity id means nothing to tag and no way to tell
                        // whose profile this is - so no composer, rather than
                        // one that might post the wrong thing.
                        if (profile!.entityId.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: CLSpacing.contentGutter),
                            // Own-vs-visitor, the placeholder and the
                            // pre-selected tag are all decided from the acting
                            // entity inside the card - see isActingEntity.
                            child: ProfileComposerCard.forProfile(
                              profile: _profileAsTag()!,
                              onPosted: () => _feedKey.currentState?.reload(),
                            ),
                          ),
                        ProfileFeed(
                          key: _feedKey,
                          handle: profile!.username,
                          emptyMessage: _isSelf(context)
                              ? "Posts you share will show up here."
                              : "${profile!.displayName} hasn't posted anything yet.",
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

/// Shown in place of a locked profile's content.
///
/// Deliberately explains the state rather than just hiding things: the header
/// above still renders, so without this the screen looks like a profile whose
/// content failed to load.
class _LockedProfileNotice extends StatelessWidget {
  final String displayName;

  const _LockedProfileNotice({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final name = displayName.trim().isEmpty ? "This account" : displayName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CLSpacing.contentGutter),
      child: CLCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.lock_outline, size: 34, color: p.text3),
              const SizedBox(height: 12),
              Text(
                "This account is private",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.text,
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Follow $name to see their posts and activity. "
                "They'll need to approve your request.",
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text2, fontSize: CLType.bodySm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
