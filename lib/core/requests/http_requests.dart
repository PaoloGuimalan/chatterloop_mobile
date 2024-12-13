import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

final dio = Dio();

class APIRequests {
  Future<LoginResponse?> loginRequest(String email, String password) async {
    Endpoints endpoints = Endpoints();
    JwtTools jwt = JwtTools();

    String token = jwt
        .createJwt({'email_username': email, 'password': password}, secretKey);

    try {
      final response = await dio.post('${endpoints.apiUrl}${endpoints.login}',
          data: {'token': token});

      if (response.data["status"] == false) {
        return null;
      }

      return LoginResponse.fromJson(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
