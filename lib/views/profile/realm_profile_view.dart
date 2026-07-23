// Read-only profile for a page/realm - the counterpart to
// user_profile_view.dart, and deliberately built on the same ProfileHeader
// hero so the two read as one screen with different content rather than two
// designs. Mirrors webapp's RealmProfile.tsx.
//
// The posts feed webapp shows below this is not built on mobile yet: there is
// no post-card UI anywhere in the app (feed_view.dart only fetches into
// Redux), so that is its own feature rather than something trimmed out here.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/contacts_api.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/views/profile/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RealmProfileScreen extends StatefulWidget {
  final String slug;
  const RealmProfileScreen({super.key, required this.slug});

  @override
  State<RealmProfileScreen> createState() => _RealmProfileScreenState();
}

class _RealmProfileScreenState extends State<RealmProfileScreen> {
  RealmProfile? _realm;
  bool _isLoading = true;

  /// Held separately from [_realm] so the button can flip immediately on tap
  /// and the count can move with it, without refetching the whole profile.
  bool _isFollowing = false;
  bool _isConnectionActionLoading = false;
  int _followers = 0;
  bool _isUpdatingFollow = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getRealmProfileRequest(widget.slug);
    if (!mounted) return;
    setState(() {
      _realm = result;
      _isFollowing = result?.isFollower ?? false;
      _followers = result?.followersCount ?? 0;
      _isLoading = false;
    });
  }

  /// entity_id is the canonical contact target - the endpoint resolves it
  /// directly, so a page is as valid a target as a person.
  Future<void> _addRealmContact() async {
    final r = _realm;
    if (r == null || _isConnectionActionLoading) return;
    setState(() => _isConnectionActionLoading = true);
    final ok = await ContactsApi().requestContactRequest(r.entityId);
    if (!mounted) return;
    setState(() => _isConnectionActionLoading = false);
    if (ok) await _load();
  }

  Future<void> _acceptRealmConnection() async {
    final r = _realm;
    if (r == null || r.connectionId == null || _isConnectionActionLoading) {
      return;
    }
    setState(() => _isConnectionActionLoading = true);
    final ok = await ContactsApi().acceptContactRequest(
        connectionId: r.connectionId!, entityId: r.entityId);
    if (!mounted) return;
    setState(() => _isConnectionActionLoading = false);
    if (ok) await _load();
  }

  /// "remove" withdraws a request I sent, "decline" rejects one sent to me.
  Future<void> _respondToRealmConnection(String action) async {
    final r = _realm;
    if (r == null || r.connectionId == null || _isConnectionActionLoading) {
      return;
    }
    setState(() => _isConnectionActionLoading = true);
    final ok = await ContactsApi().declineContactRequest(
        connectionId: r.connectionId!, entityId: r.entityId, action: action);
    if (!mounted) return;
    setState(() => _isConnectionActionLoading = false);
    if (ok) await _load();
  }

  Future<void> _toggleFollow() async {
    final realm = _realm;
    if (realm == null || _isUpdatingFollow) return;

    final wasFollowing = _isFollowing;
    // Optimistic: following is cheap and reversible, and waiting on the round
    // trip makes the button feel broken.
    setState(() {
      _isUpdatingFollow = true;
      _isFollowing = !wasFollowing;
      _followers += wasFollowing ? -1 : 1;
    });

    final ok = await ProfileApi()
        .setEntityFollowRequest(entityId: realm.entityId, follow: !wasFollowing);

    if (!mounted) return;
    setState(() {
      _isUpdatingFollow = false;
      if (!ok) {
        _isFollowing = wasFollowing;
        _followers += wasFollowing ? 1 : -1;
      }
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't update follow. Try again."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final realm = _realm;

    return Scaffold(
      backgroundColor: p.bg,
      // Same treatment as user_profile_view: transparent bar extended behind
      // the body so the back button floats over the cover photo, instead of a
      // hard header strip pushing the cover down. The two screens have to
      // match here or switching between them visibly jumps.
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
      body: _isLoading
          ? const SingleChildScrollView(child: ProfileHeaderSkeleton())
          : realm == null
              ? Center(
                  child: CLEmptyState(
                    icon: Icons.error_outline,
                    iconBg: p.surface2,
                    iconColor: p.text3,
                    title: "Couldn't load this page",
                    subtitle: "It may have been removed.",
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      ProfileHeader(
                        id: realm.id,
                        displayName: realm.name,
                        username: realm.slug ?? realm.id,
                        avatarSrc: realm.profile,
                        coverSrc: realm.coverPhoto,
                        actions: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _actions(p, realm),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _details(p, realm),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  /// Sits in the same slot the user profile fills with Add Contact / Message,
  /// so the two screens line up.
  Widget _actions(CLPalette p, RealmProfile realm) {
    // Managing a page is a webapp-only surface for now, so admins get a
    // disabled-looking state rather than a Follow button aimed at themselves.
    if (realm.isAdmin) {
      return CLBtn(
        label: "You manage this page",
        variant: CLBtnVariant.outline,
        block: true,
        onPressed: null,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CLBtn(
          label: _isFollowing ? "Following" : "Follow",
          iconL: _isFollowing ? Icons.check : Icons.add,
          variant: _isFollowing ? CLBtnVariant.outline : CLBtnVariant.primary,
          block: true,
          onPressed: _isUpdatingFollow ? null : _toggleFollow,
        ),
        const SizedBox(height: 8),
        _connectionAction(realm),
      ],
    );
  }

  /// A Connection is entity<->entity, so a page can be a contact just like a
  /// person. Same state machine the user profile uses: settled first, then
  /// WHO asked - initiator withdraws, receiver answers.
  Widget _connectionAction(RealmProfile realm) {
    if (realm.connectionAccomplished == true) {
      return CLBtn(
        label: "Connected",
        variant: CLBtnVariant.outline,
        block: true,
        onPressed: null,
      );
    }

    if (!realm.hasConnection) {
      return CLBtn(
        label: _isConnectionActionLoading ? "Sending…" : "Add Contact",
        iconL: Icons.person_add_alt,
        variant: CLBtnVariant.soft,
        block: true,
        onPressed: _isConnectionActionLoading ? null : _addRealmContact,
      );
    }

    if (realm.isConnectionInitiator == true) {
      return CLBtn(
        label: _isConnectionActionLoading ? "Cancelling…" : "Cancel Request",
        variant: CLBtnVariant.danger,
        block: true,
        onPressed: _isConnectionActionLoading
            ? null
            : () => _respondToRealmConnection("remove"),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: CLBtn(
            label: _isConnectionActionLoading ? "…" : "Accept",
            block: true,
            onPressed:
                _isConnectionActionLoading ? null : _acceptRealmConnection,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CLBtn(
            label: "Decline",
            variant: CLBtnVariant.outline,
            block: true,
            onPressed: _isConnectionActionLoading
                ? null
                : () => _respondToRealmConnection("decline"),
          ),
        ),
      ],
    );
  }

  /// Description and follower count, in the same card language the user
  /// profile uses for gender/joined/birthdate.
  Widget _details(CLPalette p, RealmProfile realm) {
    final description = realm.description;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CLCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (description != null && description.isNotEmpty) ...[
              Text(description,
                  style: TextStyle(color: p.text, fontSize: 14, height: 1.4)),
              const SizedBox(height: 12),
            ],
            _infoRow(p, Icons.people_alt_outlined,
                "$_followers follower${_followers == 1 ? '' : 's'}"),
            const SizedBox(height: 4),
            _infoRow(p, Icons.workspace_premium_outlined,
                realm.type == "page" ? "Page" : realm.type),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(CLPalette p, IconData icon, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 19, color: p.text2),
            const SizedBox(width: 8),
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.text, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}
