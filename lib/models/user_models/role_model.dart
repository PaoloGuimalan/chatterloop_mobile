/// One exact permission set. Equal names do not make two definitions equal.
class RoleDefinition {
  final int id;
  final String name;
  final String? code;
  final String? realmId;
  final bool editable;
  final bool permissionsEditable;
  final bool assignable;
  final String? disabledReason;
  final bool isDefault;
  final List<String> permissions;

  const RoleDefinition(
      {required this.id,
      required this.name,
      this.code,
      this.realmId,
      this.editable = false,
      this.permissionsEditable = false,
      this.assignable = true,
      this.disabledReason,
      this.isDefault = false,
      this.permissions = const []});

  factory RoleDefinition.fromJson(Map<String, dynamic> json) => RoleDefinition(
        id: int.parse(json['id'].toString()),
        name: json['name'].toString(),
        code: json['code']?.toString(),
        realmId: json['realm_id']?.toString(),
        editable: json['editable'] == true,
        permissionsEditable: json['permissions_editable'] == true,
        assignable: json['assignable'] != false,
        disabledReason: json['disabled_reason']?.toString(),
        isDefault: json['is_default'] == true,
        permissions: (json['permissions'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
      );

  String get label =>
      '${name.isEmpty ? '' : name[0].toUpperCase() + name.substring(1)} · #$id${isDefault ? ' (default)' : ''}';
  String get summary =>
      permissions.isEmpty ? 'No permissions' : permissions.join(', ');
  bool get canInvite =>
      assignable && realmId != null && code != 'owner';

  static RoleDefinition? defaultFor(
      Iterable<RoleDefinition> roles, String name, {String? realmId}) {
    for (final role in roles) {
      if (role.code == name &&
          role.isDefault &&
          role.realmId != null &&
          (realmId == null || role.realmId == realmId)) {
        return role;
      }
    }
    return null;
  }
}
