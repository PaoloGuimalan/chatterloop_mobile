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
import 'package:chatterloop_app/models/messages_models/conversation_info_model.dart';
import 'package:chatterloop_app/models/user_models/user_contacts_model.dart';
import 'package:flutter/material.dart';

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
                    name: title,
                    src: clCleanMediaSrc(profile),
                    size: 84,
                    // A group reads as a room, not a person - the same squared
                    // treatment the messages list gives group rows.
                    cornerRadius: _isSingle ? null : CLRadii.lg,
                  ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: CLType.screenTitle,
                      fontWeight: FontWeight.w800,
                      color: p.text),
                ),
                const SizedBox(height: 2),
                Text(_kindLabel,
                    style: TextStyle(fontSize: CLType.caption, color: p.text2)),
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
                id: person.entityID, name: name, src: person.profile, size: 36),
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
                      if (person.isVerified == true) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 13, color: p.brand),
                      ],
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
