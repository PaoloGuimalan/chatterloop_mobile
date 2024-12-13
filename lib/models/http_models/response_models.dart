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
