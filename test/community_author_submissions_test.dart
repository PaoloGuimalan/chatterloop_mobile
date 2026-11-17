import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/newsfeed_api.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/views/profile/widgets/submissions_feed.dart';

UserAuth identity(String entity) => UserAuth(
    true,
    UserAccount('a', 'alex', 'Alex', '', 'Rivera', null, true, true, null, null,
        null, null,
        personalEntityId: entity));

class SubmissionsFixture extends NewsfeedApi {
  final wait = Completer<PagedResult<CommunitySubmission>>();
  int loads = 0;
  @override
  Future<PagedResult<CommunitySubmission>> submissions({int page = 1}) {
    loads++;
    return wait.future;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    appStore.dispatch(DispatchModel(setUserAuthT, identity('author')));
  });
  testWidgets(
      'late author-only submissions disappear across an identity switch',
      (tester) async {
    final api = SubmissionsFixture();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SubmissionsFeed(ownerEntityId: 'author', api: api))));
    await tester.pump();
    appStore.dispatch(DispatchModel(setUserAuthT, identity('page')));
    await tester.pump();
    api.wait.complete(PagedResult.fromDrf({
      'results': [
        {
          'approval': 2,
          'post': {
            'post_id': 'p',
            'caption': 'old secret',
            'date_posted': '2026-11-17T00:00:00Z'
          },
          'decision': {'reason': 'Off topic', 'id': 'd'}
        }
      ]
    }, CommunitySubmission.fromJson));
    await tester.pumpAndSettle();
    expect(find.text('old secret'), findsNothing);
    expect(api.loads, 1);
  });
  testWidgets('a private submission shows its rejection label and human reason',
      (tester) async {
    final api = SubmissionsFixture();
    api.wait.complete(PagedResult.fromDrf({
      'results': [
        {
          'approval': 2,
          'post': {
            'post_id': 'p',
            'caption': 'Review me',
            'date_posted': '2026-11-17T00:00:00Z'
          },
          'decision': {'reason': 'Off topic', 'id': 'd'}
        }
      ]
    }, CommunitySubmission.fromJson));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SubmissionsFeed(ownerEntityId: 'author', api: api))));
    await tester.pumpAndSettle();
    expect(find.text('Unapproved'), findsOneWidget);
    expect(find.text('Off topic'), findsOneWidget);
    expect(find.text('React'), findsNothing);
  });
}
