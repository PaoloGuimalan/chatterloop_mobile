import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:chatterloop_app/views/profile/widgets/diary_card.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

/// Report reason values/labels - identical to webapp's Profile.tsx
/// reportReasons list.
const _kReportReasons = <(String, String)>[
  ('spam', 'Spam'),
  ('harassment', 'Harassment or bullying'),
  ('hate_speech', 'Hate speech'),
  ('violence', 'Violence or dangerous behavior'),
  ('nudity', 'Nudity or sexual content'),
  ('csae', 'Child sexual abuse or exploitation'),
  ('impersonation', 'Impersonation'),
  ('misinformation', 'Misinformation'),
  ('other', 'Other'),
];

class UserProfileScreen extends StatefulWidget {
  final String username;
  const UserProfileScreen({super.key, required this.username});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicProfile? profile;
  bool isLoading = true;
  bool notFound = false;
  bool isConnectionActionLoading = false;
  bool isOpeningMessage = false;
  bool isPokeLoading = false;

  /// Following is entity->entity now, so a person can be followed exactly
  /// like a page. Mirrored into local state so the button flips immediately.
  bool _isFollowing = false;
  bool _isUpdatingFollow = false;

  @override
  void initState() {
    super.initState();
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
    });
  }

  /// Follow/unfollow this person. Same endpoint pages use - it takes any
  /// entity id. Optimistic, like the realm profile's follow button.
  Future<void> _toggleFollow() async {
    if (profile == null || _isUpdatingFollow) return;

    final wasFollowing = _isFollowing;
    setState(() {
      _isUpdatingFollow = true;
      _isFollowing = !wasFollowing;
    });

    final ok = await ProfileApi().setEntityFollowRequest(
        entityId: profile!.entityId, follow: !wasFollowing);

    if (!mounted) return;
    setState(() {
      _isUpdatingFollow = false;
      if (!ok) _isFollowing = wasFollowing;
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
            style: TextStyle(color: p.text, fontSize: 17)),
        content: Text(
          "You'll both be removed from each other's contacts. You can send a new request later.",
          style: TextStyle(color: p.text2, fontSize: 14),
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
            style: TextStyle(color: p.text, fontSize: 17)),
        content: Text(
          "They won't be able to contact you, see your posts, or find your profile in search.",
          style: TextStyle(color: p.text2, fontSize: 14),
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

  /// Report sheet - webapp's report modal: a reason dropdown (default "spam")
  /// + optional description, POST /api/user/reports.
  void _openReportSheet() {
    if (profile == null) return;
    final p = cl(context);
    String reason = 'spam';
    final descController = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.flag_outlined, color: p.text, size: 20),
                  const SizedBox(width: 8),
                  Text('Report this account',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                ]),
                const SizedBox(height: 16),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.input,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                    border: Border.all(color: p.border2),
                  ),
                  child: DropdownButton<String>(
                    value: reason,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: p.surface,
                    style: TextStyle(color: p.text, fontSize: 14),
                    items: _kReportReasons
                        .map((r) =>
                            DropdownMenuItem(value: r.$1, child: Text(r.$2)))
                        .toList(),
                    onChanged: (v) => setSheet(() => reason = v ?? 'spam'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  style: TextStyle(color: p.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add more details (optional)',
                    hintStyle: TextStyle(color: p.text3, fontSize: 13.5),
                    filled: true,
                    fillColor: p.input,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.border2)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.border2)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.brand)),
                  ),
                ),
                const SizedBox(height: 16),
                CLBtn(
                  label: submitting ? 'Submitting…' : 'Submit report',
                  block: true,
                  size: CLBtnSize.lg,
                  onPressed: submitting
                      ? null
                      : () async {
                          setSheet(() => submitting = true);
                          final result = await SettingsApi().reportUser(
                            targetId: profile!.entityId,
                            reason: reason,
                            description: descController.text.trim(),
                          );
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(result.message ??
                                  (result.ok
                                      ? 'Report submitted'
                                      : 'Could not submit report'))));
                        },
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        });
      },
    );
  }

  /// Never show block/report on your own profile (reachable if you open your
  /// own username via search) - the server would reject it anyway.
  bool _isSelf(BuildContext context) {
    if (profile == null) return false;
    final me = StoreProvider.of<AppState>(context).state.userAuth.user;
    return me.username == profile!.username;
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
              Icon(Icons.flag_outlined, size: 18, color: p.text2),
              const SizedBox(width: 10),
              Text('Report', style: TextStyle(color: p.text)),
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
  /// Connected + Poke. Message always shows alongside, independent of
  /// connection state.
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
          : (_isFollowing ? "Following" : "Follow"),
      size: CLBtnSize.md,
      variant: _isFollowing ? CLBtnVariant.outline : CLBtnVariant.soft,
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

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
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
    return Scaffold(
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
                          gender: profile!.gender,
                          online: online,
                          joinedLabel:
                              formattedDateToWords(profile!.joinedDate),
                          birthdateLabel: formattedBirthdate(
                              profile!.birthMonth,
                              profile!.birthDay,
                              profile!.birthYear),
                          actions: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _connectionActions(p),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Renders on anyone's profile - the totals endpoint is
                      // public - but only links through on your own, since the
                      // entries themselves are self-only.
                      ProfileDiaryCard(
                        username: profile!.username,
                        isSelf: _isSelf(context),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
