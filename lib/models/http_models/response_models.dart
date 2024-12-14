class LoginResponse {
  String usertoken;
  String authtoken;

  LoginResponse(this.usertoken, this.authtoken);

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      json['usertoken'],
      json['authtoken'],
    );
  }
}

class JWTCheckerResponse {
  String usertoken;

  JWTCheckerResponse(this.usertoken);

  factory JWTCheckerResponse.fromJson(Map<String, dynamic> json) {
    return JWTCheckerResponse(json['usertoken']);
  }
}
