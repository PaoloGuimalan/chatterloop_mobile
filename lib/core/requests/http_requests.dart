import 'dart:convert';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/device_token.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/request_models.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/util_models/conversation_utils_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final dio = Dio(BaseOptions(
  headers: {'origin': Endpoints.origin},
));
final storage = FlutterSecureStorage();
Endpoints endpoints = Endpoints();
JwtTools jwt = JwtTools();

class APIRequests {
  static bool _interceptorInitialized = false;

  APIRequests() {
    if (_interceptorInitialized) return;
    _interceptorInitialized = true;
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers['origin'] = Endpoints.origin;
        options.headers['device-token'] = await resolveDeviceToken();
        handler.next(options);
      },
    ));
  }

  Future<LoginResponse?> loginRequest(String email, String password) async {
    ContentValidator().printer('${endpoints.userApiUrl}${endpoints.login}');
    // String token = jwt
    //     .createJwt({'email_username': email, 'password': password}, secretKey);

    try {
      final response = await dio.post(
          '${endpoints.userApiUrl}${endpoints.login}',
          data: {'email_username': email, 'password': password});

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

  /// Note: unlike loginRequest, the registration response is NOT nested
  /// under "result" - status/message/authtoken/usertoken/allowed_modules
  /// are all top-level fields (confirmed by reading
  /// UserAccountManagement.post in user_service/user/views.py).
  Future<LoginResponse?> signupRequest({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String gender,
    required bool agreedToTerms,
    required int birthday,
    required int birthmonth,
    required int birthyear,
  }) async {
    ContentValidator().printer('${endpoints.userApiUrl}${endpoints.signup}');

    try {
      final response =
          await dio.post('${endpoints.userApiUrl}${endpoints.signup}', data: {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'email': email,
        'password': password,
        'gender': gender,
        'agreedToTerms': agreedToTerms,
        'birthday': birthday,
        'birthmonth': birthmonth,
        'birthyear': birthyear,
      });

      if (response.data["status"] == false) {
        return null;
      }

      return LoginResponse.fromJson(response.data);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Requires the caller to already hold an authtoken (issued by signup or
  /// login) - CodeVerification is IsAuthenticated-gated on the Django side.
  Future<bool> verifyEmailRequest(String code) async {
    String? token = await storage.read(key: 'token');
    if (token == null) return false;

    try {
      final response = await dio.post(
          '${endpoints.userApiUrl}${endpoints.verifyEmail}',
          data: {'code': code},
          options: Options(headers: {'x-access-token': token}));

      return response.data["status"] == true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  Future<JWTCheckerResponse?> jwtCheckerRequest() async {
    ContentValidator().printer('${endpoints.apiUrl}${endpoints.jwtChecker}');
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
    ContentValidator().printer('${endpoints.apiUrl}${endpoints.getPosts}');
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
    ContentValidator().printer('${endpoints.apiUrl}${endpoints.getContacts}');
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
    ContentValidator()
        .printer('${endpoints.apiUrl}${endpoints.getConversationList}');
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

  Future<EncodedResponse?> getNotificationsListRequest() async {
    ContentValidator()
        .printer('${endpoints.apiUrl}${endpoints.getNotifications}');
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {'x-access-token': token};

    try {
      final response = await dio.get(
          '${endpoints.apiUrl}${endpoints.getNotifications}',
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
    ContentValidator().printer(
        '${endpoints.apiUrl}${endpoints.initConversation}$conversationID');
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
    ContentValidator().printer(
        '${endpoints.apiUrl}${endpoints.getConversationInfo}$conversationID/$conversationType');
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
    ContentValidator()
        .printer('${endpoints.apiUrl}${endpoints.seenNewMessages}');
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
          data: {"token": encodedPayload},
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> readNotificationsRequest() async {
    ContentValidator()
        .printer('${endpoints.apiUrl}${endpoints.readNotifications}');
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
    };

    try {
      final response = await dio.post(
          '${endpoints.apiUrl}${endpoints.readNotifications}',
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> isTypingRequest(IisTypingRequest payload) async {
    String url = '${endpoints.apiUrl}${endpoints.postIsTyping}';
    ContentValidator().printer(url);
    String? token = await storage.read(key: 'token');
    String encodedPayload = jwt.createJwt(payload.toJson(), secretKey);

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
    };

    try {
      final response = await dio.post(url,
          data: {"token": encodedPayload}, options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> sendMessageRequest(
      ISendMessagePayload payload) async {
    String url = '${endpoints.apiUrl}${endpoints.sendNewMessage}';
    ContentValidator().printer(url);
    String? token = await storage.read(key: 'token');
    String encodedPayload = jwt.createJwt(payload.toJson(), secretKey);

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
    };

    try {
      final response = await dio.post(url,
          data: {"token": encodedPayload}, options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return EncodedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<MessageBasedResponse?> postReplyAssistRequest(
      String conversationID, List<ReplyAssistContext> messageIDs) async {
    String url = '${endpoints.apiUrl}${endpoints.replyAssist}';
    ContentValidator().printer(url);
    String? token = await storage.read(key: 'token');

    if (token == null) {
      return null;
    }

    Map<String, String> headers = {
      'x-access-token': token,
      'Content-Type': 'application/json'
    };

    try {
      final response = await dio.post(url,
          data: jsonEncode({
            "conversationID": conversationID,
            "messageIDs": messageIDs.map((mp) => mp.toJson()).toList()
          }),
          options: Options(headers: headers));

      if (response.data["status"] == false) {
        return null;
      }

      return MessageBasedResponse(response.data["message"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }
}
