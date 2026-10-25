import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:dio/dio.dart';

/// Lifecycle transport only. Existing signed Dio interceptors remain authoritative.
/// Errors propagate with status/body so callers distinguish lost access from empty lists.
class CommunityApi {
  final Dio _dio;
  final _endpoints = Endpoints();
  CommunityApi({Dio? dio}) : _dio = dio ?? ApiClient.userService.dio;
  String _path(String id) =>
      '${_endpoints.communities}/${Uri.encodeComponent(id)}';
  Future<PagedResult<Community>> discover(
      {String search = '', bool joined = false, int page = 1}) async {
    final response = await _dio.get(_endpoints.communities, queryParameters: {
      'page': page,
      if (search.isNotEmpty) 'search': search,
      if (joined) 'joined': 'true'
    });
    return PagedResult.fromDrf(response.data, Community.fromJson);
  }

  Future<Community> detail(String id) async =>
      _community((await _dio.get(_path(id))).data);
  Future<Community> create(
          {required String name,
          String? slug,
          String description = '',
          bool isPrivate = false}) async =>
      _community((await _dio.post(_endpoints.communities, data: {
        'name': name,
        'description': description,
        'is_private': isPrivate,
        if (slug != null) 'slug': slug
      }))
          .data);
  Future<CommunityMembership> join(String realmId) async =>
      CommunityMembership.fromJson(Map<String, dynamic>.from(
          (await _dio.post('${_path(realmId)}/join')).data));
  Future<CommunityMembership> leave(String realmId) async =>
      CommunityMembership.fromJson(Map<String, dynamic>.from(
          (await _dio.post('${_path(realmId)}/leave')).data));
  Community _community(dynamic data) =>
      Community.fromJson(Map<String, dynamic>.from(data['result']));
}

class CommunityMembership {
  final bool? isMember;
  final bool requestPending;
  const CommunityMembership({this.isMember, this.requestPending = false});
  factory CommunityMembership.fromJson(Map<String, dynamic> json) =>
      CommunityMembership(
          isMember: json['is_member'] is bool
              ? json['is_member']
              : json['result'] is Map &&
                      json['result']['kind'] == 'request' &&
                      json['result']['status'] == 'pending'
                  ? false
                  : null,
          requestPending: json['request_pending'] == true ||
              json['pending'] == true ||
              json['result'] is Map &&
                  json['result']['kind'] == 'request' &&
                  json['result']['status'] == 'pending');
}
