import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
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
  PublicProfile? profile;
  bool isLoading = true;
  bool notFound = false;
  bool isConnectionActionLoading = false;
  bool isOpeningMessage = false;
  bool isPokeLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getPublicProfileRequest(widget.username);
    if (!mounted) return;
    setState(() {
      profile = result;
      notFound = result == null;
      isLoading = false;
    });
  }

  Future<void> _addContact() async {
    if (profile == null) return;
    setState(() => isConnectionActionLoading = true);
    final ok = await ContactsApi().requestContactRequest(profile!.id);
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
        toUserId: profile!.id,
        action: action);
    if (!mounted) return;
    setState(() => isConnectionActionLoading = false);
    if (ok) await _load();
  }

  Future<void> _acceptConnection() async {
    if (profile == null || profile!.connectionId == null) return;
    setState(() => isConnectionActionLoading = true);
    final ok = await ContactsApi().acceptContactRequest(
        connectionId: profile!.connectionId!, toUserId: profile!.id);
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

  /// Mirrors webapp's four connection states exactly (Profile.tsx): no
  /// connection yet -> Add; a pending request you sent -> Cancel Request;
  /// a pending request they sent -> Accept/Decline; already connected ->
  /// Connected + Poke. Message always shows alongside, independent of
  /// connection state.
  Widget _connectionActions(CLPalette p) {
    final rows = <Widget>[];

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
            label: "Connected",
            size: CLBtnSize.md,
            variant: CLBtnVariant.outline,
            onPressed: null,
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
                    ],
                  ),
                ),
    );
  }
}
