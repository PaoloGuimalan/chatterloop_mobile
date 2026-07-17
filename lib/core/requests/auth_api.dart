// Session/account endpoints: login, signup, email verification, session
// restore. Mirrors chatterloop_mobile/lib/services/auth_api.dart's role.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthApi {
  final _dio = ApiClient.userService.dio;
  final _mainApi = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  Future<LoginResponse?> loginRequest(String email, String password) async {
    ContentValidator().printer('${_endpoints.userApiUrl}${_endpoints.login}');

    try {
      final response = await _dio.post(_endpoints.login,
          data: {'email_username': email, 'password': password});

      if (response.data["status"] == false) return null;
      return LoginResponse.fromJson(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
        if (e is DioException) print("Response body: ${e.response?.data}");
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
    ContentValidator().printer('${_endpoints.userApiUrl}${_endpoints.signup}');

    try {
      final response = await _dio.post(_endpoints.signup, data: {
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

      if (response.data["status"] == false) return null;
      return LoginResponse.fromJson(response.data);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Third-party (Google) sign-in / auto-signup. Takes the Google ID token
  /// obtained natively (GoogleAuthService) and hands it to Django's
  /// /api/user/tp_auth, which verifies it and either logs in an existing
  /// account or creates one on the spot - then returns the same
  /// {authtoken, usertoken, allowed_modules, active_entity,
  /// personal_entity_id} result as a normal login. Payload is exactly
  /// `{token}`, matching webapp's ThirdPartyAuthenticationRequest.
  Future<LoginResponse?> thirdPartyAuthRequest(String idToken) async {
    ContentValidator().printer('${_endpoints.userApiUrl}${_endpoints.tpAuth}');

    try {
      final response =
          await _dio.post(_endpoints.tpAuth, data: {'token': idToken});

      if (response.data["status"] == false) return null;
      return LoginResponse.fromJson(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
        if (e is DioException) print("Response body: ${e.response?.data}");
      }
      return null;
    }
  }

  /// Requires the caller to already hold an authtoken (issued by signup or
  /// login) - CodeVerification is IsAuthenticated-gated on the Django side.
  /// The token is attached automatically by ApiClient's interceptor.
  Future<bool> verifyEmailRequest(String code) async {
    try {
      final response =
          await _dio.post(_endpoints.verifyEmail, data: {'code': code});
      return response.data["status"] == true;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }

  /// Current terms/privacy documents (public endpoint). Each entry is
  /// {document_type, version, content, document_url, effective_date} -
  /// the Setup screen uses document_url to link out. Mirrors webapp's
  /// GetCurrentPoliciesRequest.
  Future<List<Map<String, dynamic>>> getPoliciesRequest() async {
    try {
      final response = await _dio.get(_endpoints.policies);
      final data = response.data?["data"];
      if (data is! List) return const [];
      return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (e) {
      if (kDebugMode) print("ERROR getPolicies: $e");
      return const [];
    }
  }

  /// PUT /api/user/me - fills in the missing profile fields (birthdate and/or
  /// gender) so Account.is_profile_complete() passes. Only sends the keys it
  /// was given. Mirrors webapp's CompleteProfileRequest.
  Future<bool> completeProfileRequest({String? birthdate, String? gender}) async {
    try {
      final payload = <String, dynamic>{};
      if (birthdate != null) payload['birthdate'] = birthdate;
      if (gender != null) payload['gender'] = gender;
      final response = await _dio.put(_endpoints.updateProfile, data: payload);
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR completeProfile: $e");
        if (e is DioException) print("Response body: ${e.response?.data}");
      }
      return false;
    }
  }

  /// POST /api/user/policies/accept with an empty body - the server records
  /// acceptance of every consent it still has pending for this account.
  /// Mirrors webapp's AcceptPoliciesRequest.
  Future<bool> acceptPoliciesRequest() async {
    try {
      final response = await _dio.post(_endpoints.acceptPolicies, data: {});
      return response.data?["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR acceptPolicies: $e");
        if (e is DioException) print("Response body: ${e.response?.data}");
      }
      return false;
    }
  }

  /// Session restore - hits the Node backend's unified jwtchecker, which
  /// merges usertoken/allowed_modules/active_entity/personal_entity_id.
  Future<JWTCheckerResponse?> jwtCheckerRequest() async {
    ContentValidator().printer('${_endpoints.apiUrl}${_endpoints.jwtChecker}');

    try {
      final response = await _mainApi.get(_endpoints.jwtChecker);
      if (response.data["status"] == false) return null;
      return JWTCheckerResponse.fromJson(response.data["result"]);
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<void> logout() async {
    await ApiClient.instance.clearToken();
  }
}
