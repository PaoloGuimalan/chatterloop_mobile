// Feed/posts endpoints (Node backend). Feed itself is out of scope for the
// current realignment pass, but kept as its own file - not folded into a
// catch-all - so it's a one-file addition when that work picks up.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/content_validator.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class FeedApi {
  final _dio = ApiClient.instance.dio;

  /// The preview endpoint lives on Django, not Node - hence the second client.
  final _userDio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// One post in full, for the read-only preview opened from an Explore
  /// content card. Plain serializer body, no {status, result} envelope.
  Future<PostPreview?> getPostPreviewRequest(String postId) async {
    try {
      final response = await _userDio.get('${_endpoints.postPreview}$postId/');
      if (response.data is! Map) return null;
      return PostPreview.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } catch (e) {
      if (kDebugMode) {
        print("ERROR");
        print(e);
      }
      return null;
    }
  }

  Future<EncodedResponse?> getPostsRequest(String range) async {
    ContentValidator().printer('${_endpoints.apiUrl}${_endpoints.getPosts}');
    try {
      final response = await _dio.get(_endpoints.getPosts,
          options: Options(headers: {'range': range}));
      if (response.data["status"] == false) return null;
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
