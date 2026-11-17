import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/core/requests/roles_api.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/views/realm/realm_permissions_view.dart';
import 'package:chatterloop_app/views/communities/community_approvals_view.dart';
import 'package:chatterloop_app/views/profile/widgets/submissions_feed.dart';
import 'package:chatterloop_app/views/moderation/community_review_detail_view.dart';
import 'realm_permissions_test.dart' as permissions;
import 'community_author_submissions_test.dart' as submissions;

Map<String, dynamic> postFixture() => {
      'post_id': 'post',
      'caption':
          'A proposed trail clean-up this Saturday. Who would like to help?',
      'date_posted': '2020-01-01T01:00:00Z',
      'entity': {
        'id': 'author',
        'type': 'user',
        'details': {
          'first_name': 'Alex',
          'last_name': 'Rivera',
          'username': 'alex',
          'is_badged': true
        }
      },
      'community': {
        'realm_id': 'club',
        'entity_id': 'club-entity',
        'name': 'Garden Club',
        'is_member': true
      }
    };

class GoldenApprovals extends CommunityApi {
  final bool empty;
  GoldenApprovals({this.empty = false});
  @override
  Future<Community> detail(String id) async => Community.fromJson({
        'realm_id': id,
        'capabilities': {
          'can_review_posts': true,
          'can_review_invites': true,
          'can_review_join_requests': true,
          'can_decline_join_requests': true
        }
      });
  @override
  Future<CommunityApprovalsPage> approvals(String id,
          {ApprovalKind kind = ApprovalKind.posts,
          String state = 'pending',
          int page = 1,
          String? targetId}) async =>
      CommunityApprovalsPage.fromJson({
        'counts': {
          'posts': empty ? 0 : 1,
          'invites': empty ? 0 : 1,
          'joins': empty ? 0 : 1
        },
        'results': empty
            ? []
            : kind == ApprovalKind.posts
                ? [
                    {
                      'post': postFixture(),
                      'approval': state == 'pending' ? 0 : 2,
                      'content_version': '2026-11-18T01:00:00Z',
                      if (state != 'pending')
                        'decision': {
                          'id': 'decision',
                          'reason':
                              'Please keep posts relevant to the community.'
                        }
                    }
                  ]
                : [
                    {
                      'id': 'invite',
                      'realm_id': id,
                      'realm_type': 'community',
                      'realm_name': 'Garden Club',
                      'kind': kind == ApprovalKind.joins ? 'request' : 'invite',
                      'status': kind == ApprovalKind.joins
                          ? 'pending'
                          : 'for_approval',
                      'purpose': 'join',
                      'target_entity': {
                        'id': 'maya',
                        'type': 'user',
                        'details': {'first_name': 'Maya', 'last_name': 'Reyes'}
                      },
                      'inviter': {
                        'id': 'alex',
                        'type': 'user',
                        'details': {'first_name': 'Alex', 'last_name': 'Rivera'}
                      }
                    }
                  ]
      }, kind);
}

class GoldenDetail extends NewsfeedApi {
  @override
  Future<RealmReviewDetail> reviewDecision(String id) async =>
      RealmReviewDetail.fromJson({
        'decision': {
          'id': id,
          'action': 'takedown',
          'reason': 'Please keep posts relevant to the community.',
          'created_at': '2026-11-18T01:00:00Z'
        },
        'content': postFixture(),
        'matches_reviewed_version': false
      });
}

class WaitingRoles extends RolesApi {
  @override
  Future<RealmPermissionSettings> permissions(String id) =>
      Completer<RealmPermissionSettings>().future;
}

class FailingRoles extends RolesApi {
  @override
  Future<RealmPermissionSettings> permissions(String id) =>
      Future.error(StateError('Offline fixture'));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    CLAlerts.clear();
    appStore
        .dispatch(DispatchModel(setUserAuthT, submissions.identity('author')));
  });
  tearDown(CLAlerts.clear);
  for (final brightness in Brightness.values) {
    for (final screen in [
      'permissions',
      'approvals',
      'submissions',
      'decision',
      'empty',
      'loading',
      'error'
    ]) {
      testWidgets('actual realm $screen ${brightness.name} at narrow width',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = FontLoader('Inter');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
        }
        await font.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        final key = GlobalKey();
        if (screen != 'submissions') {
          appStore.dispatch(
              DispatchModel(setUserAuthT, submissions.identity('admin')));
        }
        Widget body;
        switch (screen) {
          case 'permissions':
            body = RealmPermissionsView(
                realmId: 'club', api: permissions.RolesFixture());
          case 'approvals':
            body =
                CommunityApprovalsView(realmId: 'club', api: GoldenApprovals());
          case 'empty':
            body = CommunityApprovalsView(
                realmId: 'club', api: GoldenApprovals(empty: true));
          case 'loading':
            body = RealmPermissionsView(realmId: 'club', api: WaitingRoles());
          case 'error':
            body = RealmPermissionsView(realmId: 'club', api: FailingRoles());
          case 'decision':
            body = CommunityReviewDetailView(
                decisionId: 'decision', api: GoldenDetail());
          default:
            final api = submissions.SubmissionsFixture();
            api.wait.complete(PagedResult.fromDrf({
              'results': [
                {
                  'post': postFixture(),
                  'approval': 2,
                  'decision': {
                    'id': 'decision',
                    'reason': 'Please keep posts relevant to the community.'
                  }
                }
              ]
            }, CommunitySubmission.fromJson));
            body = Scaffold(
                appBar: AppBar(title: const Text('Submissions')),
                body: SingleChildScrollView(
                    child: SubmissionsFeed(ownerEntityId: 'author', api: api)));
        }
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildCLTheme(brightness),
                builder: (context, child) => CLAlertHost(child: child!),
                initialRoute: '/preview',
                routes: {
                  '/': (_) => const Scaffold(),
                  '/preview': (_) => body
                })));
        if (screen == 'loading') {
          await tester.pump(const Duration(milliseconds: 300));
        } else {
          await tester.pumpAndSettle();
        }
        if (screen == 'permissions') {
          await tester.tap(find.text('Writers'));
          await tester.pumpAndSettle();
        }
        await expectLater(
            find.byKey(key),
            matchesGoldenFile(
                'goldens/realm_approval_${screen}_${brightness.name}.png'));
      });
    }
  }
}
