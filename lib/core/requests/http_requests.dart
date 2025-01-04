import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final dio = Dio();
final storage = FlutterSecureStorage();
Endpoints endpoints = Endpoints();
JwtTools jwt = JwtTools();

class APIRequests {
  Future<LoginResponse?> loginRequest(String email, String password) async {
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

  Future<JWTCheckerResponse?> jwtCheckerRequest() async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token};

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.jwtChecker}',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return JWTCheckerResponse.fromJson(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> getPostsRequest(String range) async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token, 'range': range};

    try {
      final response = await dio.get('${endpoints.apiUrl}${endpoints.getPosts}',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> getContactsRequest() async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token};

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.getContacts}',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> getConversationListRequest() async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token};

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.getConversationList}',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> initConversationRequest(
      String conversationID, int range) async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
      'range': range.toString()
    };

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.initConversation}$conversationID',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> getConversationInfoRequest(
      String conversationID, String conversationType) async {
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token};

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.getConversationInfo}$conversationID/$conversationType',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> seenNewMessagesRequest(
      ISeenNewMessagesRequest payload, int range) async {
    String? token = await storage.read(key: 'token');
    String encodedPayload = jwt.createJwt(payload.toJson(), secretKey);

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
      'range': range.toString()
    };

    try {
      final response = await dio.post(
          '${endpoints.apiUrl}${endpoints.seenNewMessages}',
          data: {token: encodedPayload},
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
