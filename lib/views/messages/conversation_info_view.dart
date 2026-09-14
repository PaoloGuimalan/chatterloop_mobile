// Conversation info - the mobile counterpart of webapp's
// ConversationInfoModal.
//
// Built entirely from what the conversation screen has ALREADY loaded
// (ConversationInfoModel), so opening it costs no request. That is also why it
// takes the model rather than an id: re-fetching here would show a second,
// possibly different, copy of what the screen behind it is already showing.
//
// A pushed screen rather than a modal: web's is a full-height panel, which on
// a phone is a screen wearing a modal's clothes.
//
// SCOPE: identity and members. Web's modal also carries a shared-files browser
// with Media / Audio / Files tabs - deliberately left out for now, so this
// screen stays the thing it does well. The data for it (conversationfiles) is
// already on the model when it is wanted.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class ConversationInfoScreen extends StatelessWidget {
  final ConversationInfoModel info;

  /// Display name for the conversation - resolved by the screen behind this
  /// one, which already does that work for its own header.
  final String title;
  final String? profile;
  final String conversationType;

  const ConversationInfoScreen({
    super.key,
    required this.info,
    required this.title,
    required this.conversationType,
    this.profile,
  });

  bool get _isSingle => conversationType == 'single';

  /// A channel is a room, not a person - so it shows its TYPE, the same way the
  /// conversation header and the channels list do, rather than an avatar with
  /// initials standing in for a face it never had.
  bool get _isChannel =>
      conversationType == 'channel' || conversationType == 'server';

  /// Same matrix as the channels list: lock for private, hash for public.
  IconData get _channelIcon => info.isPrivate ? Icons.lock : Icons.tag;

  /// The OTHER party in a direct message - whose badge and page flag belong
  /// beside the title. Null for anything else: a group's title is the group's
  /// own name, and a member's badge belongs on their row, not on the heading.
  ///
  /// Matched by exclusion rather than by picking [0], because usersWithInfo
  /// includes you.
  UsersContactPreview? get _counterpart {
    if (!_isSingle) return null;
    final me = appStore.state.userAuth.user.entityId;
    for (final person in info.usersWithInfo) {
      if (person.entityID.isNotEmpty && person.entityID != me) return person;
    }
    return null;
  }

  /// Web's header label: "Channel" for a server, else "Group Chat". Extended
  /// for the kinds this app can reach that web's ternary doesn't name.
  String get _kindLabel => switch (conversationType) {
        // Private/public, as the channels list distinguishes them - "Channel"
        // alone drops the one thing the icon is telling you.
        'server' ||
        'channel' =>
          info.isPrivate ? 'Private channel' : 'Text channel',
        'voice' => 'Voice room',
        'single' => 'Direct message',
        _ => 'Group Chat',
      };

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final people = info.usersWithInfo;

    return CLScreen(
      // p.surface, not p.bg: the AppBar is surface (see appBarTheme) and this
      // screen is one continuous panel of identity - a bg-coloured body under
      // a surface-coloured header draws a seam across it for no reason. Other
      // screens keep bg because their content sits in surface CARDS, which
      // need something to sit against; nothing here is a card.
      backgroundColor: p.surface,
      // No title. The screen opens with the conversation's own name at 84px
      // right below it - a header saying "Conversation info" above that is
      // labelling something already unmistakable, and it competes with the
      // name for the eye. The back button is what the bar is here for.
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            CLSpacing.contentGutter, 16, CLSpacing.contentGutter, 24),
        children: [
          Center(
            child: Column(
              children: [
                if (_isChannel)
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                    ),
                    child: Icon(_channelIcon, size: 34, color: p.text2),
                  )
                else
                  CLAvatar(
                    id: info.contactID,
                    // Null for a group: a group is not an entity and has no
                    // presence of its own, which is why the label below reads
                    // "Members are Active" rather than naming anyone.
                    entityId: _counterpart?.entityID,
                    name: title,
                    src: clCleanMediaSrc(profile),
                    size: 84,
                    // A group reads as a room, not a person - the same squared
                    // treatment the messages list gives group rows.
                    cornerRadius: _isSingle ? null : CLRadii.lg,
                  ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: CLType.screenTitle,
                            fontWeight: FontWeight.w800,
                            color: p.text),
                      ),
                    ),
                    // Bigger, and a wider gap, than a list row's - this is
                    // a screen title. The glyphs and their order are the
                    // shared part.
                    ...clEntityMarkers(
                      context,
                      isVerified: _counterpart?.isVerified == true,
                      isPage: _counterpart?.isPage == true,
                      isBot: _counterpart?.isBot == true,
                      badgeSize: 17,
                      kindSize: 15,
                      gap: 5,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // For a DM this slot carries PRESENCE, not the kind label.
                //
                // Two reasons. It is the slot the conversation header itself
                // uses for presence, so arriving here from that header finds
                // the same fact in the same place rather than losing it; and
                // "Direct message" is the one line on this screen that tells
                // a reader nothing they cannot see - there is a single face
                // above it and no member list below it.
                //
                // Every other kind keeps its label: a channel's private/public
                // distinction and a group's "Group Chat" are not derivable
                // from the rest of the screen.
                if (_isSingle)
                  _PresenceLine(entityId: _counterpart?.entityID)
                else
                  Text(_kindLabel,
                      style:
                          TextStyle(fontSize: CLType.caption, color: p.text2)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Members. Web shows this for everything except a single
          // conversation, where the "members" are just the two of you.
          if (!_isSingle) ...[
            Text(
              people.length == 1 ? '1 member' : '${people.length} members',
              style: TextStyle(
                  fontSize: CLType.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: p.text),
            ),
            const SizedBox(height: 8),
            // A panel, like the profile screen's details and diary sections -
            // it gives the list somewhere to live instead of floating on the
            // page. surface2 rather than CLCard: this screen's background is
            // already surface (see above), so a surface card on it would be
            // an outline around nothing.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: p.surface2,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(CLRadii.md),
              ),
              child: people.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: CLSectionEmpty(
                        icon: Icons.group_outlined,
                        title: 'No members listed',
                        subtitle:
                            'Nobody could be resolved for this conversation.',
                      ),
                    )
                  : Column(
                      children: [
                        for (final person in people) _PersonRow(person: person),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final UsersContactPreview person;
  const _PersonRow({required this.person});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final name = [
      person.fullname.firstName,
      person.fullname.lastName,
    ].where((part) => part.trim().isNotEmpty && part != 'N/A').join(' ');

    // NOT tappable, though web's rows navigate to the member's profile.
    //
    // This screen and the server info screen are both display only, and they
    // now agree: a member list here tells you WHO is in the conversation, and
    // that is all it does. Half the rows leading somewhere and half not - a page
    // member has no user profile route - is worse than none of them leading
    // anywhere, and the profile is a tap away from any message they have sent.
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CLAvatar(
                id: person.entityID,
                // The server sends usersWithInfo[].entityID as `p.id` - the
                // real entity - so a member row keys on presence the same way
                // the counterpart avatar above it does.
                //
                // Group co-members are outside the server's presence scope
                // unless they are ALSO a contact or a DM counterpart, so a
                // list of strangers stays unmarked. That is the server's rule,
                // not a gap here.
                entityId: person.entityID,
                name: name,
                src: person.profile,
                size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name.isEmpty ? person.userID : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: CLType.body,
                                fontWeight: FontWeight.w600,
                                color: p.text)),
                      ),
                      // Members are ENTITIES, so a page or a bot can be in
                      // a group - which for a bot is the whole point of
                      // adding one.
                      ...clEntityMarkers(
                        context,
                        isVerified: person.isVerified == true,
                        isPage: person.isPage,
                        isBot: person.isBot,
                        badgeSize: 13,
                        kindSize: 12,
                      ),
                    ],
                  ),
                  if (person.userID.isNotEmpty)
                    Text('@${person.userID}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CLType.caption, color: p.text2)),
                ],
              ),
            ),
          ],
        ));
  }
}

/// "Active Now" / "Active 5 minutes ago" for the DM counterpart, kept live.
///
/// Self-subscribed rather than threaded down from the screen: a presence frame
/// for ANY contact replaces the whole presence map, so reading it higher up
/// would rebuild this entire screen - avatars, member list and all - every
/// time anybody at all connected. The conversation header this mirrors made
/// the same call for the same reason.
///
/// The wording matches `_headerSubtitle` in conversation_view exactly. Two
/// screens describing one person's availability in two different phrasings is
/// the kind of difference a reader notices and cannot explain.
class _PresenceLine extends StatelessWidget {
  final String? entityId;

  const _PresenceLine({required this.entityId});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return StoreConnector<AppState, PresenceInfo?>(
      distinct: true,
      converter: (store) =>
          entityId == null ? null : store.state.presence[entityId],
      builder: (context, info) {
        final online = info?.online == true;
        final label = info == null
            ? "Recently Active"
            : online
                ? "Active Now"
                : info.lastSeen != null
                    ? "Active ${timeSince(info.lastSeen!)}"
                    : "Recently Active";

        return Text(
          label,
          style: TextStyle(
            fontSize: CLType.caption,
            // Online is the one state worth colouring. "Active 3 hours ago" in
            // green would read as a status light for something that is not
            // currently true.
            color: online ? p.online : p.text2,
            fontWeight: online ? FontWeight.w600 : FontWeight.w400,
          ),
        );
      },
    );
  }
}
