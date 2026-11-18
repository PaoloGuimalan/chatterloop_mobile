import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_item.dart';
import 'package:chatterloop_app/models/user_models/community_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'package:chatterloop_app/views/communities/community_approvals_view.dart';
import 'package:chatterloop_app/views/realm/realm_review_card.dart';

class WaitingApprovals extends CommunityApi {
  final detailResult = Completer<Community>();
  final result = Completer<CommunityApprovalsPage>();
  ApprovalKind? requestedKind;
  @override
  Future<Community> detail(String id) => detailResult.future;
  @override
  Future<CommunityApprovalsPage> approvals(String id,
      {ApprovalKind kind = ApprovalKind.posts,
      String state = 'pending',
      int page = 1,
      String? targetId}) {
    requestedKind = kind;
    return result.future;
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets('navigation skeleton pulse color matches ${brightness.name}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(brightness),
          home: Scaffold(
              body: RealmReviewTabs<String>(
                  value: 'posts',
                  loading: true,
                  onChanged: null,
                  tabs: const [(value: 'posts', label: 'Posts')]))));
      final skeleton = find.byType(CLSkeleton);
      final palette = cl(tester.element(skeleton));
      Color paintedColor() => (tester
              .widget<Container>(find.descendant(
                  of: skeleton, matching: find.byType(Container)))
              .decoration as BoxDecoration)
          .color!;
      expect(paintedColor(),
          brightness == Brightness.light ? palette.surface : palette.surface3);
      for (var phase = 0; phase < 4; phase++) {
        await tester.pump(const Duration(milliseconds: 450));
        if (brightness == Brightness.light) {
          expect(paintedColor().computeLuminance(),
              greaterThan(palette.bg.computeLuminance()),
              reason:
                  'The entire light-mode navigation pulse must stay lighter than the page.');
        }
        if (phase == 1) {
          expect(
              paintedColor(),
              brightness == Brightness.light
                  ? palette.surface2
                  : palette.border2);
        }
      }
    });
  }
  for (final scale in [1.0, 1.6, 3.0]) {
    testWidgets(
        'whole navigation skeleton preserves wrapped size at text scale $scale',
        (tester) async {
      Widget page(bool loading) => MaterialApp(
          theme: buildCLTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 288,
                      child: RealmReviewTabs<String>(
                          value: 'posts',
                          loading: loading,
                          onChanged: (_) {},
                          tabs: const [
                            (value: 'posts', label: 'Posts'),
                            (value: 'invitations', label: 'Invitations'),
                            (value: 'joins', label: 'Join requests')
                          ])))));
      await tester.pumpWidget(page(false));
      final loaded = tester.getSize(find.byType(RealmReviewTabs<String>));
      await tester.pumpWidget(page(true));
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(CLSkeleton), findsOneWidget);
      expect(tester.getSize(find.byType(CLSkeleton)), loaded);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'default Approvals entry shows post navigation and content skeletons',
      (tester) async {
    final api = WaitingApprovals();
    await tester.pumpWidget(
        MaterialApp(home: CommunityApprovalsView(realmId: 'club', api: api)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RealmReviewTabs<String>), findsOneWidget);
    expect(find.byType(PostItemSkeleton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final brightness in Brightness.values) {
    for (final kind in ApprovalKind.values) {
      testWidgets(
          'approval skeleton matches ${kind.name} in ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = WaitingApprovals();
        await tester.pumpWidget(MaterialApp(
            theme: buildCLTheme(brightness),
            home: CommunityApprovalsView(
                realmId: 'club', initialKind: kind, api: api)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(RealmReviewTabs<ApprovalKind>), findsOneWidget);
        expect(find.byType(CLSkeleton), findsWidgets);
        expect(find.text('Approve'), findsNothing);
        api.detailResult.complete(Community.fromJson({
          'realm_id': 'club',
          'capabilities': {
            'can_review_posts': true,
            'can_review_invites': true,
            'can_review_join_requests': true
          }
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final navigation = find.byType(RealmReviewTabs<ApprovalKind>);
        expect(
            find.descendant(of: navigation, matching: find.byType(TextButton)),
            findsNothing);
        final placeholder =
            find.descendant(of: navigation, matching: find.byType(CLSkeleton));
        expect(placeholder, findsOneWidget);
        expect(tester.getSize(placeholder).width,
            tester.getSize(navigation).width);
        if (kind == ApprovalKind.posts) {
          final status = find.byType(RealmReviewTabs<String>);
          expect(find.descendant(of: status, matching: find.byType(TextButton)),
              findsNothing);
          expect(find.descendant(of: status, matching: find.byType(CLSkeleton)),
              findsOneWidget);
        }
        await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
                'goldens/realm_approvals_loading_${kind.name}_${brightness.name}.png'));
        expect(api.requestedKind, kind);
        expect(find.byType(PostItemSkeleton),
            kind == ApprovalKind.posts ? findsOneWidget : findsNothing);
        expect(find.byType(RealmReviewTabs<String>),
            kind == ApprovalKind.posts ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        api.result.complete(CommunityApprovalsPage.fromJson(
            {'results': [], 'counts': {}}, kind));
        await tester.pumpAndSettle();
        expect(find.byType(CLSkeleton), findsNothing);
        expect(find.text('No submissions to review.'), findsOneWidget);
      });
    }
  }
}
