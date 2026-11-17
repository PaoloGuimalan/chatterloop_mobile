import 'package:chatterloop_app/views/communities/community_profile_view.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/views/communities/community_approvals_view.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'community_author_submissions_test.dart' as author;

class SelfReviewFixture extends CommunityApi {
  final bool publish, anonymous;
  final actions = <String>[];
  SelfReviewFixture({required this.publish, required this.anonymous});
  @override
  Future<Community> detail(String id) async => Community.fromJson({
        'realm_id': id,
        'capabilities': {'can_review_posts': true, 'can_publish_posts': publish}
      });
  @override
  Future<CommunityApprovalsPage> approvals(String id,
          {ApprovalKind kind = ApprovalKind.posts,
          String state = 'pending',
          int page = 1,
          String? targetId}) async =>
      CommunityApprovalsPage.fromJson({
        'counts': {'posts': 1},
        'results': [
          {
            'approval': 0,
            'content_version': 'v1',
            'post': {
              'post_id': 'own',
              'caption': 'My submission',
              'date_posted': '2020-01-01T01:00:00Z',
              'is_owner': true,
              'is_anonymous': anonymous,
              'entity': anonymous
                  ? null
                  : {
                      'id': 'me',
                      'type': 'user',
                      'details': {'first_name': 'Maya', 'username': 'maya'}
                    },
              'community': {'realm_id': id, 'name': 'Club', 'is_member': true}
            }
          }
        ]
      }, kind);
  @override
  Future<void> reviewPost(String id, String post,
      {required String action,
      required int expectedApproval,
      required String expectedVersion,
      String reason = ''}) async {
    actions.add(action);
  }
}

class ApprovalFixture extends CommunityApi {
  @override
  Future<Community> detail(String id) async => Community.fromJson({
        'realm_id': id,
        'name': 'Club',
        'capabilities': {'can_review_invites': true}
      });
  final actions = <String>[];
  @override
  Future<CommunityApprovalsPage> approvals(String id,
          {ApprovalKind kind = ApprovalKind.posts,
          String state = 'pending',
          int page = 1,
          String? targetId}) async =>
      CommunityApprovalsPage.fromJson({
        'results': [
          {
            'id': 'invite',
            'realm_id': id,
            'realm_name': 'Club',
            'realm_type': 'community',
            'kind': 'invite',
            'status': 'for_approval',
            'purpose': 'join',
            'invite_token': 't',
            'target_entity': {
              'id': 'person',
              'type': 'user',
              'details': {'first_name': 'Maya'}
            }
          }
        ],
        'counts': {'invites': 1}
      }, kind);
  @override
  Future<void> reviewInvitation(String id, String invite,
      {required ApprovalKind kind,
      required String action,
      required String expectedStatus}) async {
    actions.add('$action:$expectedStatus');
  }
}

class ProfileReviewerFixture extends CommunityApi {
  @override
  Future<Community> detail(String id) async => Community.fromJson({
        'realm_id': id,
        'entity_id': 'e',
        'name': 'Club',
        'is_member': true,
        'my_role': 'curator',
        'capabilities': {
          'can_manage': true,
          'can_review_posts': true,
          'can_submit_posts': false
        }
      });
  @override
  Future<PagedResult<PostPreview>> posts(String id, {int page = 1}) async =>
      PagedResult.empty();
  @override
  Future<PagedResult<RealmPerson>> members(String id, {int page = 1}) async =>
      PagedResult.empty();
}

void main() {
  for (final anonymous in [false, true]) {
    for (final publish in [false, true]) {
      testWidgets(
          'self-review follows current publication permission (anonymous=$anonymous publish=$publish)',
          (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        appStore.dispatch(DispatchModel(setUserAuthT, author.identity('me')));
        final api = SelfReviewFixture(publish: publish, anonymous: anonymous);
        await tester.pumpWidget(MaterialApp(
            home: CommunityApprovalsView(realmId: 'club', api: api)));
        await tester.pumpAndSettle();
        final approve = find.widgetWithText(CLBtn, 'Approve');
        final reject = find.widgetWithText(CLBtn, 'Reject');
        expect(tester.widget<CLBtn>(approve).onPressed != null, publish);
        expect(tester.widget<CLBtn>(reject).onPressed != null, publish);
        if (publish) {
          await tester.tap(approve);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();
          expect(api.actions, ['approve']);
        } else {
          expect(api.actions, isEmpty);
        }
      });
    }
  }
  testWidgets(
      'custom community reviewers can open Manage Realm from the profile menu',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        home: CommunityProfileView(id: 'club', api: ProfileReviewerFixture())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Community options'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Realm'), findsOneWidget);
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'an invite-only reviewer sees invitations and confirms an exact-state decision',
      (tester) async {
    final api = ApprovalFixture();
    await tester.pumpWidget(
        MaterialApp(home: CommunityApprovalsView(realmId: 'club', api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Posts'), findsNothing);
    expect(find.text('Maya'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(api.actions, ['approve:for_approval']);
  });
}
