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

  const BlockedAccount({
    required this.id,
    required this.entityID,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.profile,
    required this.createdAt,
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
    );
  }

  String get displayName => '$firstName $lastName'.trim();
}
