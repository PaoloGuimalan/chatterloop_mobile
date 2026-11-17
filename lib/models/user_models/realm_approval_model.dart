import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_invite_model.dart';
export 'package:chatterloop_app/models/user_models/realm_policy_model.dart';

enum ApprovalKind { posts, invites, joins }

List<Map<String, dynamic>> _rows(dynamic json) => json is List
    ? json
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : const [];

class ReviewDecision {
  final String id, action, targetKind, targetId, reason;
  final String? contentVersion;
  final DateTime? createdAt;
  final Map<String, dynamic> previousState, newState;
  ReviewDecision.fromJson(Map<String, dynamic> json)
      : id = (json['id'] ?? '').toString(),
        action = (json['action'] ?? '').toString(),
        targetKind = (json['target_kind'] ?? '').toString(),
        targetId = (json['target_id'] ?? '').toString(),
        reason = (json['reason'] ?? '').toString(),
        contentVersion = json['content_version']?.toString(),
        createdAt = DateTime.tryParse((json['created_at'] ?? '').toString()),
        previousState = json['previous_state'] is Map
            ? Map<String, dynamic>.from(json['previous_state'])
            : const {},
        newState = json['new_state'] is Map
            ? Map<String, dynamic>.from(json['new_state'])
            : const {};
}

class CommunitySubmission {
  final PostPreview post;
  final int approval;
  final String contentVersion;
  final ReviewDecision? decision;
  CommunitySubmission.fromJson(Map<String, dynamic> json)
      : post = PostPreview.fromJson(
                Map<String, dynamic>.from(json['post'] as Map? ?? {}))
            .copyWith(
                readOnly: true, approval: parsePostApproval(json['approval'])),
        approval = parsePostApproval(json['approval']),
        contentVersion = (json['content_version'] ?? '').toString(),
        decision = json['decision'] is Map
            ? ReviewDecision.fromJson(
                Map<String, dynamic>.from(json['decision']))
            : null;
}

class CommunityApprovalsPage {
  final int count;
  final bool hasNext;
  final Map<String, int> counts;
  final List<CommunitySubmission> posts;
  final List<RealmInvite> invitations;
  CommunityApprovalsPage.fromJson(dynamic json, ApprovalKind kind)
      : count = json['count'] is num ? (json['count'] as num).toInt() : 0,
        hasNext = json['next'] != null,
        counts = json['counts'] is Map
            ? Map.unmodifiable((json['counts'] as Map).map((key, value) =>
                MapEntry(key.toString(), value is num ? value.toInt() : 0)))
            : const {},
        posts = kind == ApprovalKind.posts
            ? _rows(json['results']).map(CommunitySubmission.fromJson).toList()
            : const [],
        invitations = kind != ApprovalKind.posts
            ? _rows(json['results']).map(RealmInvite.fromJson).toList()
            : const [];
}

/// Human decisions carry their real reason; no classifier scores are invented.
class RealmReviewDetail {
  final ReviewDecision decision;
  final Community? community;
  final PostPreview? content;
  final bool viewerIsOwner, matchesReviewedVersion;
  final String? currentContentVersion;
  RealmReviewDetail.fromJson(Map<String, dynamic> json)
      : decision = ReviewDecision.fromJson(
            Map<String, dynamic>.from(json['decision'] as Map? ?? {})),
        community = Community.parse(json['community']),
        content = json['content'] is Map
            ? PostPreview.fromJson(Map<String, dynamic>.from(json['content']))
            : null,
        viewerIsOwner = json['viewer_is_owner'] == true,
        matchesReviewedVersion = json['matches_reviewed_version'] == true,
        currentContentVersion = json['current_content_version']?.toString();
}

String? communityPublicationMessage(dynamic response) => response is Map &&
        response["status"] == true &&
        response["approval"] == 0
    ? "Your post was submitted for approval. View it under Submissions on your profile."
    : null;
