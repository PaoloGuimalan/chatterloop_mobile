import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_options.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';

class OptionsFixture extends CommunityApi {
  int reads = 0;
  final versions = <String>[];
  @override
  Future<Community> detail(String id) async {
    reads++;
    return Community.fromJson({
      'realm_id': 'r',
      'capabilities': {'can_take_down_posts': true}
    });
  }

  @override
  Future<void> reviewPost(String realm, String post,
      {required String action,
      required int expectedApproval,
      required String expectedVersion,
      String reason = ''}) async {
    versions.add(expectedVersion);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('community takedown is loaded on demand and requires a reason',
      (tester) async {
    final api = OptionsFixture();
    final post = PostPreview(
        postId: 'p',
        caption: 'Post',
        datePosted: DateTime.utc(2026),
        references: const [],
        reactions: const [],
        author: const PostPreviewAuthor(
            entityId: 'other',
            type: 'user',
            displayName: 'Maya',
            handle: 'maya',
            isVerified: false),
        likesCount: 0,
        commentsCount: 0,
        isShared: false,
        community: const Community(realmId: 'r', entityId: 'e', name: 'Club'));
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: PostOptionsButton(post: post, communityApi: api))));
    expect(api.reads, 0);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(api.reads, 1);
    await tester.tap(find.text('Take down post'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Take down'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'Off topic');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Take down'));
    await tester.pumpAndSettle();
    expect(api.versions, [DateTime.utc(2026).toIso8601String()]);
  });
}
