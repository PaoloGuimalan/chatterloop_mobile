import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'private review cards have no engagement or options while ordinary hidden community posts stay hidden',
      (tester) async {
    final post = PostPreview(
        postId: 'p',
        caption: 'Hidden caption',
        datePosted: DateTime.utc(2026),
        references: const [],
        reactions: const [],
        author: const PostPreviewAuthor(
            entityId: 'a',
            type: 'user',
            displayName: 'Maya',
            handle: 'maya',
            isVerified: false),
        likesCount: 0,
        commentsCount: 0,
        isShared: false,
        approval: 0,
        community: const Community(realmId: 'r', entityId: 'e', name: 'Club'));
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: PostCard(post: post))));
    await tester.pump();
    expect(find.text('Hidden caption'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PostCard(
                key: const ValueKey('readonly'),
                post: post.copyWith(readOnly: true)))));
    await tester.pump();
    expect(find.text('Hidden caption'), findsOneWidget);
    expect(find.byType(PopupMenuButton), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });
}
