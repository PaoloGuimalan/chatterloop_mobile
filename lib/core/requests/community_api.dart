import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/notifications_models/community_notification_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';

final communityChanges = ValueNotifier<int>(0);

/// Only management activity changed; directory/profile lists need no refetch.
final communityNotificationsChanges = ValueNotifier<int>(0);

class CommunityPostChange {
  final String realmId, postId;
  const CommunityPostChange(this.realmId, this.postId);
}

final communityPostChanges = ValueNotifier<CommunityPostChange?>(null);

/// Lifecycle transport only. Existing signed Dio interceptors remain authoritative.
/// Errors propagate with status/body so callers distinguish lost access from empty lists.
class CommunityApi {
  final Dio _dio;
  final String? _authToken;
  Options? get _options =>
      _authToken == null ? null : Options(extra: {'authToken': _authToken});
  final _endpoints = Endpoints();
  CommunityApi({Dio? dio, String? authToken})
      : _dio = dio ?? ApiClient.userService.dio,
        _authToken = authToken;
  String _path(String id) =>
      '${_endpoints.communities}/${Uri.encodeComponent(id)}';

  Future<CommunityApprovalsPage> approvals(String realmId,
      {ApprovalKind kind = ApprovalKind.posts,
      String state = 'pending',
      int page = 1, String? targetId}) async {
    final response = await _dio.get('${_path(realmId)}/approvals',
        options: _options,
        queryParameters: {'kind': kind.name, 'state': state, 'page': page, if(targetId!=null)'target_id':targetId});
    return CommunityApprovalsPage.fromJson(response.data, kind);
  }

  Future<void> reviewPost(String realmId, String postId,
      {required String action,
      required int expectedApproval,
      required String expectedVersion,
      String reason = ''}) async {
    await _dio.post(
        '${_path(realmId)}/approvals/posts/${Uri.encodeComponent(postId)}',
        options: _options,
        data: {
          'action': action,
          'expected_approval': expectedApproval,
          'expected_version': expectedVersion,
          'reason': reason,
        });
  }

  Future<void> reviewInvitation(String realmId, String inviteId,
      {required ApprovalKind kind,
      required String action,
      required String expectedStatus}) async {
    if (kind == ApprovalKind.posts) {
      throw ArgumentError('Choose invitations or join requests.');
    }
    await _dio.post(
        '${_path(realmId)}/approvals/${kind.name}/${Uri.encodeComponent(inviteId)}',
        options: _options,
        data: {'action': action, 'expected_status': expectedStatus});
  }

  Future<PagedResult<PostPreview>> archive(String realmId,
          {int page = 1}) async =>
      PagedResult.fromDrf(
          (await _dio.get('${_path(realmId)}/archive',
                  options: _options, queryParameters: {'page': page}))
              .data,
          PostPreview.fromJson);

  Future<void> archivePost(String realmId, String postId,
      {required bool archived}) async {
    await _dio.post('${_path(realmId)}/archive/${Uri.encodeComponent(postId)}',
        options: _options, data: {'is_archived': archived});
  }

  Future<CommunityNotificationsPage> notifications(String realmId,
      {int page = 1}) async {
    final response = await _dio.get('${_path(realmId)}/notifications',
        options: _options, queryParameters: {'page': page});
    return CommunityNotificationsPage.fromJson(response.data);
  }

  Future<void> acknowledgeNotifications(String realmId,
      {required int activityRevision,
      List<String> notificationIds = const []}) async {
    await _dio
        .post('${_path(realmId)}/notifications/read', options: _options, data: {
      'activity_revision': activityRevision,
      'notification_ids': notificationIds,
    });
  }

  Future<PagedResult<Community>> discover(
      {String search = '',
      bool joined = false,
      int page = 1,
      List<String> taggedEntityIds = const []}) async {
    final response = await _dio
        .get(_endpoints.communities, options: _options, queryParameters: {
      'page': page,
      if (search.isNotEmpty) 'search': search,
      if (joined) 'joined': 'true',
      if (taggedEntityIds.isNotEmpty)
        'tagged_entities': taggedEntityIds.join(','),
    });
    return PagedResult.fromDrf(response.data, Community.fromJson);
  }

  Future<PagedResult<PostPreview>> posts(String id, {int page = 1}) async {
    final response = await _dio.post(
        '${_endpoints.newsfeedProfile}${Uri.encodeComponent(id)}/',
        options: _options,
        data: {'viewcache': []},
        queryParameters: {'page': page, 'page_size': 10});
    return PagedResult.fromDrf(response.data, PostPreview.fromJson);
  }

  Future<PagedResult<RealmPerson>> members(String id, {int page = 1}) async {
    try {
      final response = await _dio.get(_endpoints.realmMembers,
          options: _options, queryParameters: {'realm_id': id, 'page': page});
      return PagedResult.fromDrf(response.data, RealmPerson.fromMemberJson);
    } on DioException catch (e) {
      if ([401, 403].contains(e.response?.statusCode)) {
        return PagedResult.empty();
      }
      rethrow;
    }
  }

  Future<Community> detail(String id) async =>
      _community((await _dio.get(_path(id), options: _options)).data);
  Future<Community> create(
      {required String name,
      required String slug,
      String description = '',
      bool isPrivate = false}) async {
    final profileSlug = slug.trim();
    if (profileSlug.isEmpty) {
      throw ArgumentError.value(slug, 'slug', 'Enter a community slug');
    }
    return _community(
        (await _dio.post(_endpoints.communities, options: _options, data: {
      'name': name,
      'description': description,
      'is_private': isPrivate,
      'slug': profileSlug
    }))
            .data);
  }

  Future<CommunityMembership> join(String realmId) async =>
      CommunityMembership.fromJson(Map<String, dynamic>.from(
          (await _dio.post('${_path(realmId)}/join', options: _options)).data));
  Future<CommunityMembership> leave(String realmId,
          {bool cancelRequestOnly = false}) async =>
      CommunityMembership.fromJson(Map<String, dynamic>.from((await _dio.post(
              '${_path(realmId)}/leave',
              options: _options,
              data: cancelRequestOnly ? {'cancel_request': true} : null))
          .data));
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
