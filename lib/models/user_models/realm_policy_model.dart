import 'package:chatterloop_app/models/user_models/role_model.dart';

/// Server hints only. Missing grants never confer UI access.
class RealmCapabilities {
  final Map<String, bool> values;
  const RealmCapabilities([this.values = const {}]);
  bool allows(String capability) => values[capability] == true;
  factory RealmCapabilities.fromJson(dynamic json) =>
      RealmCapabilities(json is Map
          ? Map.unmodifiable(
              json.map((key, value) => MapEntry(key.toString(), value == true)))
          : const {});
}

class RealmPermissionSettings {
  final RealmCapabilities capabilities;
  final List<RoleDefinition> roles;
  final List<RealmPermissionEntry> catalog;
  final Map<String, bool> features;
  RealmPermissionSettings.fromJson(Map<String, dynamic> json)
      : capabilities = RealmCapabilities.fromJson(json['capabilities']),
        roles = _rows(json['roles']).map(RoleDefinition.fromJson).toList(),
        catalog =
            _rows(json['catalog']).map(RealmPermissionEntry.fromJson).toList(),
        features = json['features'] is Map
            ? Map.unmodifiable((json['features'] as Map)
                .map((key, value) => MapEntry(key.toString(), value == true)))
            : const {};
}

class RealmPermissionEntry {
  final String code, name, description;
  String get permission => code;
  final bool grantable;
  RealmPermissionEntry.fromJson(Map<String, dynamic> json)
      : code = (json['code'] ?? json['permission'] ?? '').toString(),
        name = [
          json['name'],
          json['description'],
          json['code'],
          json['permission']
        ]
            .map((value) => (value ?? '').toString())
            .firstWhere((value) => value.trim().isNotEmpty, orElse: () => ''),
        description = (json['description'] ?? '').toString(),
        grantable = json['grantable'] == true;
}

List<Map<String, dynamic>> _rows(dynamic json) => json is List
    ? json
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : const [];
