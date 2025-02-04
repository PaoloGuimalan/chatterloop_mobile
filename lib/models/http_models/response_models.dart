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
