class JWTCheckerResponse {
  String usertoken;

  JWTCheckerResponse(this.usertoken);

  factory JWTCheckerResponse.fromJson(Map<String, dynamic> json) {
    return JWTCheckerResponse(json['usertoken']);
  }
}

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

class PostsResponse {
  String result;

  PostsResponse(this.result);

  factory PostsResponse.fromJson(Map<String, dynamic> json) {
    return PostsResponse(
      json['result'],
    );
  }
}
