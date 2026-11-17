import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/utils/sse_events.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'role creation and editing never send a caller-controlled code and review errors remain intact',
      () async {
    final calls = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        calls.add(request);
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'status': true,
          'result': {'id': 3, 'name': 'Post Reviewer', 'realm_id': 'club'}
        }));
      }));
    final roles = RolesApi(client: dio, authToken: 'page');
    await roles
        .create('club', 'Post Reviewer', permissions: ['realm.post.review']);
    await roles.update('club', 3, name: 'Review team');
    await roles.delete('club', 3);
    expect(calls.map((r) => r.method), ['POST', 'PUT', 'DELETE']);
    expect(calls[0].data, {
      'realm_id': 'club',
      'name': 'Post Reviewer',
      'permissions': ['realm.post.review']
    });
    expect(calls[1].data, {'realm_id': 'club', 'name': 'Review team'});
    expect(calls[2].queryParameters['realm_id'], 'club');
    final refused = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.reject(DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response(
                requestOptions: request,
                statusCode: 409,
                data: {'detail': 'This submission has changed.'})));
      }));
    await expectLater(
        CommunityApi(dio: refused).reviewPost('club', 'post',
            action: 'approve',
            expectedApproval: 0,
            expectedVersion: '2026-11-16T00:00:00+00:00'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 409)));
  });
  test(
      'community post invalidations carry only current-identity state and ignore malformed signals',
      () async {
    FlutterSecureStorage.setMockInitialValues({'token': 'acting-page-token'});
    final event = SSEModel(
        event: 'community_posts_changed',
        data:
            '{"auth":true,"status":true,"result":{"realm_id":"club","target_id":"post","approval":2}}');
    await SseEvents().listen(event, true, token: 'acting-page-token');
    final accepted = communityPostChanges.value;
    expect(accepted?.postId, 'post');
    expect(accepted?.realmId, 'club');
    FlutterSecureStorage.setMockInitialValues(
        {'token': 'different-page-token'});
    await SseEvents().listen(event, true, token: 'acting-page-token');
    expect(identical(communityPostChanges.value, accepted), isTrue);
    await SseEvents()
        .listen(SSEModel(event: 'community_posts_changed', data: '{}'), true);
    expect(identical(communityPostChanges.value, accepted), isTrue);
  });
  test(
      'approval contracts reuse signed clients and keep state/version and page identity',
      () async {
    final calls = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        calls.add(request);
        final result = {
          'post': {'post_id': 'post'},
          'approval': 0,
          'content_version': '2026-11-16T00:00:00+00:00'
        };
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'status': true,
          'result': result,
          'data': {},
          'results': [],
          'count': 0,
          'next': null,
        }));
      }));
    final api = CommunityApi(dio: dio, authToken: 'acting-page-token');
    await api.approvals('club',
        kind: ApprovalKind.posts, state: 'not_approved', page: 2);
    await api.reviewPost('club', 'post/one',
        action: 'reject',
        expectedApproval: 0,
        expectedVersion: '2026-11-16T00:00:00+00:00',
        reason: 'Outside our topic');
    await api.reviewInvitation('club', 'invite',
        kind: ApprovalKind.invites,
        action: 'approve',
        expectedStatus: 'for_approval');
    final roles = RolesApi(client: dio, authToken: 'acting-page-token');
    await roles.permissions('club');
    await roles.savePermissions('club', {
      2: ['realm.post.submit']
    });
    final feed = NewsfeedApi(client: dio, authToken: 'acting-page-token');
    await feed.submissions(page: 2);
    await feed.submission('post/one');
    await feed.reviewDecision('cb48b3df-bd09-44b5-b218-b47f1afce820');
    await api.archive('club');
    await api.archivePost('club', 'post/one', archived: true);
    expect(calls.map((r) => '${r.method} ${r.path}'), [
      'GET /api/realm/communities/club/approvals',
      'POST /api/realm/communities/club/approvals/posts/post%2Fone',
      'POST /api/realm/communities/club/approvals/invites/invite',
      'GET /api/realm/realms/club/permissions',
      'PUT /api/realm/realms/club/permissions',
      'GET /api/newsfeed/submissions',
      'GET /api/newsfeed/submissions/post%2Fone',
      'GET /api/entity/realm-review/cb48b3df-bd09-44b5-b218-b47f1afce820/',
      'GET /api/realm/communities/club/archive',
      'POST /api/realm/communities/club/archive/post%2Fone',
    ]);
    expect(calls.every((r) => r.extra['authToken'] == 'acting-page-token'),
        isTrue);
    expect(calls[1].data['expected_version'], '2026-11-16T00:00:00+00:00');
    expect(calls[2].data['expected_status'], 'for_approval');
    expect(calls[4].data, {
      'roles': [
        {
          'role_id': 2,
          'permissions': ['realm.post.submit']
        }
      ]
    });
  });

  test(
      'post approval and read-only flags survive existing patches and ordinary posts ignore approval',
      () {
    final post = PostPreview.fromJson({
      'post_id': 'post',
      'approval': 0,
      'read_only': true,
      'can_archive': true,
      'community': {
        'realm_id': 'club',
        'entity_id': 'community',
        'name': 'Garden',
        'is_member': true
      }
    });
    expect(post.approval, 0);
    expect(post.readOnly, isTrue);
    expect(post.copyWith(caption: 'Same').approval, 0);
    expect(post.applyPatch({'approval': 2}).approval, 2);
    expect(post.applyPatch({'caption': 'Same'}).canArchive, isTrue);
    expect(PostPreview.fromJson({'post_id': 'legacy'}).approval, 1);
    expect(
        PostPreview.fromJson({'post_id': 'ordinary', 'approval': 2})
            .isHiddenCommunityPost,
        isFalse);
    final submission = CommunitySubmission.fromJson({
      'post': {'post_id': 'post'},
      'approval': 2,
      'content_version': '2026-11-16T00:00:00+00:00',
      'decision': {'id': 'review', 'reason': 'Outside our topic'}
    });
    expect(submission.decision?.reason, 'Outside our topic');
    expect(submission.post.readOnly, isTrue);
    expect(submission.post.approval, 2);
    expect(submission.contentVersion, '2026-11-16T00:00:00+00:00');
  });
}
