import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';

class CommunityNotificationsPage extends PagedResult<CommunityNotification> {
  final int? activityRevision;
  const CommunityNotificationsPage({
    required super.count,
    required super.hasNext,
    required super.results,
    this.activityRevision,
  });

  factory CommunityNotificationsPage.fromJson(dynamic json) {
    final page = PagedResult.fromDrf(json, CommunityNotification.fromJson);
    return CommunityNotificationsPage(
        count: page.count,
        hasNext: page.hasNext,
        results: page.results,
        activityRevision: json is Map && json['activity_revision'] is num
            ? (json['activity_revision'] as num).toInt()
            : null);
  }
}

/// Community management activity, separate from the personal bell.
class CommunityNotification {
  final String id;
  final String type;
  final String description;
  final RealmPerson? actor;
  final bool isAnonymous;
  final DateTime? createdAt;
  final String? requestId;
  final String? requestStatus;
  final String? postId;
  final String? anchor;

  const CommunityNotification({
    required this.id,
    required this.type,
    required this.description,
    this.actor,
    this.isAnonymous = false,
    this.createdAt,
    this.requestId,
    this.requestStatus,
    this.postId,
    this.anchor,
  });

  bool get canReview =>
      type == 'community_join_request' &&
      requestId != null &&
      requestStatus == 'pending';

  String? get postRoute => const [
            'community_post_created',
            'post_comment',
            'post_reaction',
            'comment_reaction'
          ].contains(type) &&
          postId != null
      ? '/post/${Uri.encodeComponent(postId!)}${anchor == null ? '' : '?${Uri(queryParameters: {
              'anchor': anchor!
            }).query}'}'
      : null;

  factory CommunityNotification.fromJson(Map<String, dynamic> json) {
    String? optional(String key) {
      final value = json[key]?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    final anonymous = json['is_anonymous'] == true;
    return CommunityNotification(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      actor: !anonymous && json['actor'] is Map
          ? RealmPerson.fromMemberJson({'entity': json['actor']})
          : null,
      isAnonymous: anonymous,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      requestId: optional('request_id'),
      requestStatus: optional('request_status'),
      postId: optional('post_id'),
      anchor: optional('anchor'),
    );
  }
}
