import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

/// allowed_modules/active_entity/personal_entity_id are siblings of
/// usertoken in the response body, not part of the JWT payload - both
/// Node's /auth/jwtchecker and Django's /api/user/auth return this shape.
class JWTCheckerResponse {
  String usertoken;
  List<String> allowedModules;
  ActiveEntity? activeEntity;
  String? personalEntityId;

  JWTCheckerResponse(this.usertoken,
      {this.allowedModules = const [],
      this.activeEntity,
      this.personalEntityId});

  factory JWTCheckerResponse.fromJson(Map<String, dynamic> json) {
    return JWTCheckerResponse(
      json['usertoken'],
      allowedModules: (json['allowed_modules'] as List<dynamic>?)
              ?.map((m) => m.toString())
              .toList() ??
          const [],
      activeEntity: json['active_entity'] is Map
          ? ActiveEntity.fromJson(
              Map<String, dynamic>.from(json['active_entity']))
          : null,
      personalEntityId: json['personal_entity_id']?.toString(),
    );
  }
}

class LoginResponse {
  String usertoken;
  String authtoken;
  List<String> allowedModules;
  ActiveEntity? activeEntity;
  String? personalEntityId;

  LoginResponse(this.usertoken, this.authtoken,
      {this.allowedModules = const [],
      this.activeEntity,
      this.personalEntityId});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      json['usertoken'],
      json['authtoken'],
      allowedModules: (json['allowed_modules'] as List<dynamic>?)
              ?.map((m) => m.toString())
              .toList() ??
          const [],
      activeEntity: json['active_entity'] is Map
          ? ActiveEntity.fromJson(
              Map<String, dynamic>.from(json['active_entity']))
          : null,
      personalEntityId: json['personal_entity_id']?.toString(),
    );
  }
}

class EncodedResponse {
  String result;

  EncodedResponse(this.result);

  factory EncodedResponse.fromJson(Map<String, dynamic> json) {
    return EncodedResponse(
      json['result'],
    );
  }
}

class MessageBasedResponse {
  String message;

  MessageBasedResponse(this.message);

  factory MessageBasedResponse.fromJson(Map<String, dynamic> json) {
    return MessageBasedResponse(
      json['message'],
    );
  }
}
