// Own-profile update, avatar/cover upload, and other-user profile lookup.
// Split out from AuthApi since these aren't session/credential concerns.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/user_models/search_result_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ProfileApi {
  final _userDio = ApiClient.userService.dio;
  final _mainDio = ApiClient.instance.dio;
  final _endpoints = Endpoints();

  /// PUT (not signup's POST flow) - partial update, only send changed
  /// fields. Response envelope is `{status, message, data: account}`, not
  /// the usual {status, result} shape used elsewhere in this app.
  Future<Map<String, dynamic>?> updateProfileRequest(
      Map<String, dynamic> fieldsToUpdate) async {
    try {
      final response =
          await _userDio.put(_endpoints.updateProfile, data: fieldsToUpdate);
      if (response.data["status"] == false) return null;
      return response.data["data"] is Map
          ? Map<String, dynamic>.from(response.data["data"])
          : null;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Response is {"data": {...}} - not wrapped in {status, result} either.
  Future<PublicProfile?> getPublicProfileRequest(String username) async {
    try {
      final response =
          await _userDio.get('${_endpoints.publicProfile}$username/');
      final data = response.data["data"];
      if (data is! Map) return null;
      return PublicProfile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Step 1 of the avatar/cover upload flow - uploads the raw file, returns
  /// {url, mediaType, fileName} for the returned CDN reference (result[0]
  /// .fileDetails.data - confirmed by reading saveFileRecordToDatabase in
  /// server/reusables/hooks/firebaseupload.js).
  Future<({String url, String mediaType, String fileName})?> uploadMediaRequest(
      String filePath, String mediaType) async {
    try {
      final fileName = filePath.split(RegExp(r'[\\/]')).last;
      final form = FormData.fromMap({
        'media': await MultipartFile.fromFile(filePath, filename: fileName),
        'captions': '[""]',
        'referenceMediaTypes': '["$mediaType"]',
      });

      final response = await _mainDio.post('/posts/upload', data: form);

      if (response.data["status"] == false) return null;
      final result = response.data["result"];
      if (result is! List || result.isEmpty) return null;

      final first = Map<String, dynamic>.from(result[0]);
      final fileDetails = first["fileDetails"] is Map
          ? Map<String, dynamic>.from(first["fileDetails"])
          : const {};
      final url = fileDetails["data"]?.toString();
      if (url == null) return null;

      return (
        url: url,
        mediaType: (first["fileType"] ?? mediaType).toString(),
        fileName: (first["fileName"] ?? fileName).toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  /// Step 2 - also creates a visible feed post as a side effect (confirmed
  /// by reading server/routes/posts/index.js's /createpost handler: it both
  /// updates user_account.profile/coverphoto AND inserts into
  /// newsfeed_post when content_type is "profile"/"cover_photo").
  Future<bool> setProfileOrCoverMediaRequest({
    required String url,
    required String mediaType,
    required String fileName,
    required bool isCover,
  }) async {
    final payload = {
      'content': {
        'references': [
          {
            'name': fileName,
            'caption': '',
            'reference': url,
            'referenceMediaType': mediaType,
          }
        ],
        'isShared': false,
        'data': '',
      },
      'type': {
        'fileType': 'media',
        'contentType': isCover ? 'cover_photo' : 'profile',
      },
      'onfeed': true,
      'tagging': {'isTagged': false},
      'privacy': {'status': 'public'},
    };

    try {
      final response = await _mainDio
          .post('/posts/createpost', data: {'token': JwtCodec.sign(payload)});
      return response.data["status"] != false;
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return false;
    }
  }
}
