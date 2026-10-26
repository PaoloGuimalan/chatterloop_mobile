import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_card.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_reactions.dart';
import 'package:chatterloop_app/models/post_models/newsfeed_models.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/views/communities/communities_view.dart';
import 'package:chatterloop_app/views/communities/community_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'community_flows_test.dart' show FixtureCommunityApi;

void main() {
  testWidgets(
      'community directory fits a shorter card without clipping actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: CommunitiesView(api: FixtureCommunityApi()),
    ));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(CommunityDirectoryCard));
    expect(card.height, lessThanOrEqualTo(220));
    expect(card.contains(tester.getCenter(find.text('Open'))), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anonymous reaction heading has space above it', (tester) async {
    ReactionPalette.seed([
      Emoji(
          emojiId: 'like',
          content: '👍',
          title: 'Like',
          theme: '',
          priority: 1),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommunityReactionPicker(context,
                currentEmojiId: null, currentIsAnonymous: false),
            child: const Text('Open reactions'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open reactions'));
    await tester.pumpAndSettle();
    expect(
        tester.getRect(find.text('React anonymously')).top -
            tester.getRect(find.byType(BottomSheet)).top,
        greaterThanOrEqualTo(16));
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('long destination keeps badges with its name at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await font.load();
      final fixtures = jsonDecode(
          File('test/fixtures/community_stage1.json').readAsStringSync());
      final json = Map<String, dynamic>.from(fixtures['anonymous_owner']);
      const name =
          'Photography and creative neighborhood weekend makers community';
      json['community'] = {
        ...Map<String, dynamic>.from(json['community']),
        'name': name,
        'is_verified': true,
      };
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: PostCard(post: PostPreview.fromJson(json))),
      ));
      final label =
          tester.getRect(find.textContaining(name, findRichText: true));
      final verified = tester.getRect(find.byIcon(Icons.verified));
      final groups = tester.getRect(find.byIcon(Icons.groups_outlined));
      expect((verified.center.dy - label.center.dy).abs(), lessThan(4));
      expect((groups.center.dy - label.center.dy).abs(), lessThan(4));
      expect(groups.left, greaterThan(verified.right));
      expect(groups.right, lessThanOrEqualTo(width - 12));
      expect(tester.takeException(), isNull);
    });
  }
}
