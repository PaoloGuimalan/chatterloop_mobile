/// One row from GET /api/user/blocks - matches webapp's IBlockedAccount
/// (BlockedAccounts.tsx). Unblock keys off `entityID`, list keys off `id`.
class BlockedAccount {
  final String id;
  final String entityID;
  final String username;
  final String firstName;
  final String lastName;
  final String profile;
  final String createdAt;

  /// "user" or "realm". Blocks are entity-level, so a page can be blocked from
  /// its profile and shows up in this same list - the row needs to say which
  /// it is, because a page's name sits in [firstName] with an empty
  /// [lastName] and would otherwise be indistinguishable from a person.
  ///
  /// Defaults to "user": rows written before the field existed are all
  /// accounts.
  final String entityType;

  const BlockedAccount({
    required this.id,
    required this.entityID,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.profile,
    required this.createdAt,
    this.entityType = 'user',
  });

  factory BlockedAccount.fromJson(Map<String, dynamic> json) {
    return BlockedAccount(
      id: (json['id'] ?? '').toString(),
      entityID: (json['entityID'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      profile: (json['profile'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      entityType: (json['entityType'] ?? 'user').toString(),
    );
  }

  bool get isRealm => entityType == 'realm';

  String get displayName => '$firstName $lastName'.trim();
}
