// A realm invite, as the Django invite API serializes it
// (community/serializers.py InviteSerializer). Counterpart of the webapp's
// src/app/widgets/invites/invites.ts - the sentence and the destination are
// the same rules in both, and the server's own copy is
// community/invite_rules.py.

import 'package:chatterloop_app/core/utils/endpoints.dart';

/// Someone on an invite - the inviter or the invitee - as EntitySerializer
/// writes them: `{id, type, details}`, where details is a user's or a realm's
/// own fields.
class InviteEntity {
  final String id;
  final String type;
  final String name;
  final String? handle;
  final String? profile;

  const InviteEntity({
    required this.id,
    required this.type,
    required this.name,
    this.handle,
    this.profile,
  });

  static String? _usable(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'none' || text == 'N/A') {
      return null;
    }
    return text;
  }

  static InviteEntity? fromJson(Object? json) {
    if (json is! Map) return null;
    final details =
        json['details'] is Map ? Map<String, dynamic>.from(json['details']) : {};
    final fullName = [details['first_name'], details['last_name']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(' ')
        .trim();
    final handle = _usable(details['username']) ?? _usable(details['slug']);
    return InviteEntity(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'user').toString(),
      name: fullName.isNotEmpty
          ? fullName
          : (_usable(details['name']) ?? handle ?? 'Someone'),
      handle: handle,
      profile: _usable(details['profile']),
    );
  }
}

class RealmInvite {
  final String id;
  final String realmId;
  final String realmName;
  final String realmType;
  final String? realmSlug;
  final String? realmProfile;

  /// "invite" (we asked them) or "request" (they asked to be let in).
  final String kind;

  /// pending | accepted | declined | revoked
  final String status;

  /// join | manage | follow
  final String purpose;

  /// admin | moderator, for a "manage" invite.
  final String? role;
  final InviteEntity? inviter;
  final String? targetEmail;
  final InviteEntity? targetEntity;
  final String token;

  const RealmInvite({
    required this.id,
    required this.realmId,
    required this.realmName,
    required this.realmType,
    this.realmSlug,
    this.realmProfile,
    required this.kind,
    required this.status,
    required this.purpose,
    this.role,
    this.inviter,
    this.targetEmail,
    this.targetEntity,
    required this.token,
  });

  bool get isPending => status == 'pending';

  RealmInvite withStatus(String next) => RealmInvite(
        id: id,
        realmId: realmId,
        realmName: realmName,
        realmType: realmType,
        realmSlug: realmSlug,
        realmProfile: realmProfile,
        kind: kind,
        status: next,
        purpose: purpose,
        role: role,
        inviter: inviter,
        targetEmail: targetEmail,
        targetEntity: targetEntity,
        token: token,
      );

  factory RealmInvite.fromJson(Map<String, dynamic> json) => RealmInvite(
        id: (json['id'] ?? '').toString(),
        realmId: (json['realm_id'] ?? '').toString(),
        realmName: (json['realm_name'] ?? '').toString(),
        realmType: (json['realm_type'] ?? '').toString(),
        realmSlug: InviteEntity._usable(json['realm_slug']),
        realmProfile: InviteEntity._usable(json['realm_profile']),
        kind: (json['kind'] ?? 'invite').toString(),
        status: (json['status'] ?? 'pending').toString(),
        purpose: (json['purpose'] ?? 'join').toString(),
        role: InviteEntity._usable(json['role']),
        inviter: InviteEntity.fromJson(json['inviter']),
        targetEmail: InviteEntity._usable(json['target_email']),
        targetEntity: InviteEntity.fromJson(json['target_entity']),
        token: (json['invite_token'] ?? '').toString(),
      );

  /// "Maya invited you to join the group Weekend Hikers." - mirrors the
  /// server's invite_sentence.
  String get sentence {
    final who = inviter?.name ?? 'Someone';
    if (purpose == 'manage') {
      return '$who invited you to help run $realmName as '
          '${role == 'admin' ? 'an admin' : 'a moderator'}.';
    }
    if (purpose == 'follow') return '$who invited you to follow $realmName.';
    final noun = switch (realmType) {
      'group' => 'the group ',
      'server' => 'the server ',
      'conference' => 'the conference ',
      _ => '',
    };
    return '$who invited you to join $noun$realmName.';
  }

  /// "to follow" / "as an admin" - what a pending invite is for, in a list.
  String get purposeLabel => purpose == 'follow'
      ? 'to follow'
      : purpose == 'manage'
          ? (role == 'admin' ? 'as an admin' : 'as a moderator')
          : 'to join';

  /// A conference invite's way in: the conference's lobby on the WEB, with
  /// the token - the lobby shows the invite, takes the answer and lets you
  /// join. The app has no conference screens, so this is opened in the
  /// browser. Null for any other realm.
  String? get conferenceUrl => realmType == 'conference' && realmSlug != null
      ? '${Endpoints.origin}/conference/${Uri.encodeComponent(realmSlug!)}'
          '?invite_token=${Uri.encodeQueryComponent(token)}'
      : null;

  /// The address to show for [conferenceUrl] - without the token, which is
  /// long and means nothing to read.
  String? get conferenceAddress => conferenceUrl == null
      ? null
      : '${Uri.parse(Endpoints.origin).host}/conference/$realmSlug';

  /// Where an ACCEPTED invite takes you in the app, or null where the app has
  /// no screen for it (a conference - see [conferenceUrl]).
  String? get destination {
    switch (realmType) {
      case 'group':
        return '/conversation/$realmId';
      case 'server':
        return '/server/$realmId';
      case 'page':
        // Following lands on the page; joining its team, on its manage screen.
        if (realmSlug == null) return null;
        return purpose == 'manage'
            ? '/realm/$realmSlug/manage'
            : '/realm/$realmSlug';
      default:
        return null;
    }
  }
}
