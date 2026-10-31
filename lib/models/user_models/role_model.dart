/// One exact permission set. Equal names do not make two definitions equal.
class RoleDefinition {
  final int id;
  final String name;
  final bool isDefault;
  final List<String> permissions;

  const RoleDefinition(
      {required this.id,
      required this.name,
      this.isDefault = false,
      this.permissions = const []});

  factory RoleDefinition.fromJson(Map<String, dynamic> json) => RoleDefinition(
        id: int.parse(json['id'].toString()),
        name: json['name'].toString(),
        isDefault: json['is_default'] == true,
        permissions: (json['permissions'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
      );

  String get label =>
      '${name[0].toUpperCase()}${name.substring(1)} · #$id${isDefault ? ' (default)' : ''}';
  String get summary =>
      permissions.isEmpty ? 'No permissions' : permissions.join(', ');

  static RoleDefinition? defaultFor(
      Iterable<RoleDefinition> roles, String name) {
    for (final role in roles) {
      if (role.name == name && role.isDefault) return role;
    }
    return null;
  }
}
