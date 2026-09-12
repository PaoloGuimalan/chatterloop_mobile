import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/conversations_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/confirm_dialog.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';

/// A bot's profile.
///
/// Its own screen rather than a branch inside the user or realm one, because
/// almost nothing on either applies:
///
///  - NO COVER PHOTO. A bot has none to set and no admin to set one, so the
///    realm header's banner would be an empty band above every bot.
///  - NO POST FEED. Bots cannot post, so the Posts/Saved/Archived switcher,
///    its paging and its empty state would all be furniture around nothing.
///  - NO MEMBERS, ROLES OR ADMIN CONTROLS, and no contact request - a bot has
///    no session to see one in and no accept endpoint to call.
///
/// The PAYLOAD is the realm one: `/api/user/auth/<handle>/` maps a bot onto that
/// shape server-side, so this reuses RealmProfile and getRealmProfileRequest
/// rather than adding a parallel model. Only the layout is new.
class BotProfileScreen extends StatefulWidget {
  final String handle;

  const BotProfileScreen({super.key, required this.handle});

  @override
  State<BotProfileScreen> createState() => _BotProfileScreenState();
}

class _BotProfileScreenState extends State<BotProfileScreen> {
  RealmProfile? _bot;
  bool _isLoading = true;
  bool _isUpdatingFollow = false;
  bool _isOpeningMessage = false;

  bool _isFollowing = false;
  int _followers = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ProfileApi().getRealmProfileRequest(widget.handle);
    if (!mounted) return;
    setState(() {
      _bot = result;
      _isFollowing = result?.isFollower ?? false;
      _followers = result?.followersCount ?? 0;
      _isLoading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final bot = _bot;
    if (bot == null || _isUpdatingFollow) return;

    final wasFollowing = _isFollowing;
    // Unfollowing asks first, the same as a person or a page. The button is
    // its own opposite - "Following" becomes "Follow" - so a stray tap
    // silently undoes what it was reporting. A bot is named rather than
    // mentioned, and takes the noun-carrying wording so the copy can say
    // "following list" instead of a feed it never posts to.
    if (wasFollowing) {
      final confirmed = await confirmUnfollow(
        context,
        name: bot.name,
        isRealm: true,
        realmNoun: 'bot',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _isUpdatingFollow = true;
      // Optimistic, count included - a follower total that lags the button by
      // a round trip reads as a bug.
      _isFollowing = !wasFollowing;
      _followers = (_followers + (wasFollowing ? -1 : 1)).clamp(0, 1 << 31);
    });

    // isPending is ignored deliberately: it exists for private user profiles,
    // and a bot has no privacy gate - the server always reports false.
    final result = await ProfileApi().setEntityFollowRequest(
      entityId: bot.entityId,
      follow: !wasFollowing,
    );

    if (!mounted) return;
    setState(() {
      _isUpdatingFollow = false;
      if (!result.ok) {
        _isFollowing = wasFollowing;
        _followers = bot.followersCount;
      }
    });
  }

  /// Opens a direct conversation with the bot.
  ///
  /// Unconditional, like the page equivalent: a bot exists to be talked to, so
  /// there is no connection to check first and no private mode to protect.
  /// /m/crtc is entity-generic - two entity ids in, the existing conversation
  /// back if there is one.
  Future<void> _openMessage(RealmProfile bot) async {
    if (_isOpeningMessage) return;
    setState(() => _isOpeningMessage = true);

    final conversationId =
        await ConversationsApi().createInitialConversationRequest(bot.entityId);
    if (!mounted) return;
    setState(() => _isOpeningMessage = false);

    if (conversationId != null) {
      context.push('/conversation/$conversationId');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Couldn't open the conversation. Please try again."),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return CLScreen(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        title: Text(
          _bot?.name ?? "Bot",
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bot == null
              ? _notFound(p)
              : _body(p, _bot!),
    );
  }

  Widget _notFound(CLPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy, size: 40, color: p.text3),
              const SizedBox(height: 10),
              Text("Bot not found",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
              const SizedBox(height: 4),
              Text(
                "It may have been deactivated, or the handle is wrong.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: p.text3),
              ),
            ],
          ),
        ),
      );

  Widget _body(CLPalette p, RealmProfile bot) {
    final description = bot.description ?? "";

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CLAvatar(
              id: bot.entityId,
              name: bot.name,
              src: bot.profile,
              size: 68,
              cornerRadius: CLRadii.md,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          bot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                      // isBot unconditionally - this screen IS a bot's
                      // profile. The glyph says "software" and is separate
                      // from, not exclusive with, the verified check.
                      ...clEntityMarkers(
                        context,
                        isVerified: bot.isVerified,
                        isBot: true,
                        badgeSize: 15,
                        kindSize: 15,
                        gap: 5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "@${bot.slug ?? widget.handle} · $_followers "
                    "${_followers == 1 ? "follower" : "followers"}",
                    style: TextStyle(fontSize: 12.5, color: p.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(description,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: p.text2)),
        ],
        const SizedBox(height: 18),
        CLBtn(
          label: _isOpeningMessage ? "Opening…" : "Message",
          // The glyph the Messages tab uses, so "message" looks like one thing
          // across the app.
          iconL: Icons.forum,
          block: true,
          onPressed: _isOpeningMessage ? null : () => _openMessage(bot),
        ),
        const SizedBox(height: 8),
        CLBtn(
          label: _isFollowing ? "Following" : "Follow",
          iconL: _isFollowing ? Icons.check : Icons.add,
          variant: _isFollowing ? CLBtnVariant.outline : CLBtnVariant.primary,
          block: true,
          onPressed: _isUpdatingFollow ? null : _toggleFollow,
        ),
        // No contact action, and no disabled one either: a bot cannot accept a
        // request, so the button would exist only to be refused.
        const SizedBox(height: 20),
        // Said plainly rather than left as an absence. A profile with nothing
        // below the header reads as a feed that failed to load - which is what
        // somebody would report as a bug.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(CLRadii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.smart_toy, size: 18, color: p.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("This is a bot",
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Text(
                      "Bots don't post. You can follow it, message it "
                      "directly, or add it to a group chat and mention it "
                      "there.",
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: p.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
