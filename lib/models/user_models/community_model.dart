import 'package:chatterloop_app/models/user_models/realm_policy_model.dart';

/// Community destination metadata. It is never an acting identity.
class Community {
  final RealmCapabilities capabilities;
  final Map<String, bool> features;
  final String? myRoleName;
  final String realmId;
  final String entityId;
  final String name;
  final String? slug;
  final String? profile;
  final bool isPrivate;
  final bool isMember;
  final bool isVerified;
  final String description;
  final String? coverPhoto;
  final int? memberCount;
  final String? myRole;
  final int? myRoleId;
  final bool requestPending;
  bool get canInteract => !isPrivate || isMember;
  bool get canManage => capabilities.values.isNotEmpty
      ? capabilities.allows("can_manage")
      : ["owner", "admin", "moderator"].contains(myRole);
  const Community(
      {required this.realmId,
      this.capabilities = const RealmCapabilities(),
      this.features = const {},
      this.myRoleName,
      required this.entityId,
      required this.name,
      this.slug,
      this.profile,
      this.isPrivate = false,
      this.isMember = false,
      this.isVerified = false,
      this.description = '',
      this.coverPhoto,
      this.memberCount,
      this.myRole,
      this.myRoleId,
      this.requestPending = false});
  factory Community.fromJson(Map<String, dynamic> json) => Community(
      capabilities: RealmCapabilities.fromJson(json['capabilities']),
      features: json['features'] is Map
          ? Map.unmodifiable((json['features'] as Map)
              .map((key, value) => MapEntry(key.toString(), value == true)))
          : const {},
      myRoleName: json['my_role_name']?.toString(),
      realmId: (json['realm_id'] ?? '').toString(),
      entityId: (json['entity_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: json['slug']?.toString(),
      profile: json['profile']?.toString(),
      isPrivate: json['is_private'] == true,
      isMember: json['is_member'] == true,
      isVerified: json['is_verified'] == true,
      description: (json['description'] ?? '').toString(),
      coverPhoto: json['cover_photo']?.toString(),
      memberCount: json['member_count'] is num
          ? (json['member_count'] as num).toInt()
          : null,
      myRole: json['my_role']?.toString(),
      myRoleId: int.tryParse(json['my_role_id']?.toString() ?? ''),
      requestPending: json['request_pending'] == true);
  static Community? parse(dynamic value) => value is Map
      ? Community.fromJson(Map<String, dynamic>.from(value))
      : null;

  Community withMembership({required bool member, required bool pending}) =>
      Community(
          capabilities: member ? capabilities : const RealmCapabilities(),
          features: features,
          myRoleName: member ? myRoleName : null,
          realmId: realmId,
          entityId: entityId,
          name: name,
          slug: slug,
          profile: profile,
          isPrivate: isPrivate,
          isMember: member,
          isVerified: isVerified,
          description: description,
          coverPhoto: coverPhoto,
          memberCount: memberCount,
          myRole: member ? myRole : null,
          myRoleId: member ? myRoleId : null,
          requestPending: pending);
}
