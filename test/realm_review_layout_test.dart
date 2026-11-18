import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/views/communities/community_approvals_view.dart';
import 'package:chatterloop_app/views/realm/realm_permissions_view.dart';
import 'package:chatterloop_app/views/moderation/community_review_detail_view.dart';
import 'package:chatterloop_app/views/realm/realm_text_dialog.dart';
import 'package:chatterloop_app/views/realm/realm_review_card.dart';
import 'package:chatterloop_app/views/profile/widgets/submissions_feed.dart';
import 'package:chatterloop_app/views/realm/community_archive_view.dart';
import 'package:chatterloop_app/core/design/app_dialog.dart';
import 'package:chatterloop_app/core/requests/community_api.dart';
import 'package:chatterloop_app/models/http_models/paged_result.dart';
import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:chatterloop_app/models/user_models/realm_approval_model.dart';
import 'community_approvals_test.dart' as approvals;
import 'realm_permissions_test.dart' as permissions;
import 'realm_approval_goldens_test.dart' as goldens;
import 'community_author_submissions_test.dart' as submissions;

class ArchiveLayoutFixture extends CommunityApi {
  final restored = <String>[];
  @override
  Future<PagedResult<PostPreview>> archive(String realmId,
          {int page = 1}) async =>
      PagedResult.fromDrf({
        'results': [goldens.postFixture()]
      }, PostPreview.fromJson);
  @override
  Future<void> archivePost(String realmId, String postId,
      {required bool archived}) async {
    expect(archived, isFalse);
    restored.add(postId);
  }
}

void main() {
  setUp(() {
    CLAlerts.clear();
    FlutterSecureStorage.setMockInitialValues({});
    appStore
        .dispatch(DispatchModel(setUserAuthT, submissions.identity('admin')));
  });
  tearDown(CLAlerts.clear);
  testWidgets(
      'permissions retry stays accessible while the global error is visible',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        builder: (context, child) => CLAlertHost(child: child!),
        home: RealmPermissionsView(
            realmId: 'club', api: goldens.FailingRoles())));
    await tester.pumpAndSettle();
    expect(find.text('Could not load permissions.'), findsOneWidget);
    expect(find.widgetWithText(CLBtn, 'Retry').hitTestable(), findsOneWidget);
    final notice = tester.getRect(find.byType(Dismissible));
    final retry = tester.getRect(find.widgetWithText(CLBtn, 'Retry'));
    expect(retry.top - notice.bottom, greaterThanOrEqualTo(12));
  });
  Future<void> mount(WidgetTester tester, Widget body, double width,
      {double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: body));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('invitation actions stay separated at $width / $scale',
          (tester) async {
        await mount(
            tester,
            CommunityApprovalsView(
                realmId: 'club', api: approvals.ApprovalFixture()),
            width,
            scale: scale);
        final first = tester.getRect(find.widgetWithText(CLBtn, 'Approve'));
        final second = tester.getRect(find.widgetWithText(CLBtn, 'Decline'));
        final horizontal =
            second.left >= first.right + 7 || first.left >= second.right + 7;
        final vertical =
            second.top >= first.bottom + 7 || first.top >= second.bottom + 7;
        expect(horizontal || vertical, isTrue,
            reason: 'Action touch targets need an 8px gap on either axis.');
        expect(first.left, greaterThanOrEqualTo(16));
        expect(second.right, lessThanOrEqualTo(width - 16));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('role creation is separated from the first role card',
      (tester) async {
    await mount(
        tester,
        RealmPermissionsView(realmId: 'club', api: permissions.RolesFixture()),
        390);
    final create = tester.getRect(find.widgetWithText(CLBtn, 'Create role'));
    final owner = tester.getRect(find
        .ancestor(of: find.text('Owner'), matching: find.byType(CLCard))
        .first);
    expect(owner.top - create.bottom, greaterThanOrEqualTo(12));
  });
  testWidgets('expanded role actions follow the permissions list',
      (tester) async {
    await mount(
        tester,
        RealmPermissionsView(realmId: 'club', api: permissions.RolesFixture()),
        390);
    await tester.tap(find.text('Writers'));
    await tester.pumpAndSettle();
    final permission = tester.getRect(find.byType(CheckboxListTile));
    expect(tester.getRect(find.widgetWithText(TextButton, 'Rename')).top,
        greaterThanOrEqualTo(permission.bottom + 8));
    expect(tester.getRect(find.widgetWithText(TextButton, 'Delete')).top,
        greaterThanOrEqualTo(permission.bottom + 8));
  });
  testWidgets('private submission cards have matching left and right margins',
      (tester) async {
    appStore
        .dispatch(DispatchModel(setUserAuthT, submissions.identity('author')));
    final api = submissions.SubmissionsFixture();
    api.wait.complete(PagedResult.fromDrf({
      'results': [
        {'post': goldens.postFixture(), 'approval': 2}
      ]
    }, CommunitySubmission.fromJson));
    await mount(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: SubmissionsFeed(ownerEntityId: 'author', api: api))),
        390);
    final card = tester.getRect(find.byType(RealmReviewCard));
    expect(card.left, 16);
    expect(card.right, 374);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'approval filters fill each row and use web selections at $width',
        (tester) async {
      final font = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await font.load();
      await mount(
          tester,
          CommunityApprovalsView(
              realmId: 'club', api: goldens.GoldenApprovals()),
          width);
      final label = find.text('Not approved');
      expect(label, findsOneWidget);
      final pending = tester.getRect(find
          .ancestor(of: find.text('Pending'), matching: find.byType(TextButton))
          .first);
      final rejected = tester.getRect(
          find.ancestor(of: label, matching: find.byType(TextButton)).first);
      expect(pending.top, rejected.top);
      expect(pending.left, 19);
      expect(rejected.right, width - 19);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'restore uses the shared app dialog and only restores after confirmation',
      (tester) async {
    final api = ArchiveLayoutFixture();
    await mount(tester, CommunityArchiveView(realmId: 'club', api: api), 390);
    await tester.tap(find.text('Restore post'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AppDialogAction), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.restored, isEmpty);
    await tester.tap(find.text('Restore post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(api.restored, ['post']);
  });
  testWidgets('human review separates and formats the decision time',
      (tester) async {
    await mount(
        tester,
        CommunityReviewDetailView(
            decisionId: 'decision', api: goldens.GoldenDetail()),
        320);
    final reason = tester
        .getRect(find.text('Please keep posts relevant to the community.'));
    final timestamp = find
        .byType(Text)
        .evaluate()
        .map((e) => e.widget as Text)
        .where((w) => w.data?.contains('2026') == true)
        .single;
    expect(timestamp.data, isNot(contains('.000')));
    final dateRect = tester.getRect(find.byWidget(timestamp));
    expect(dateRect.top - reason.bottom, greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'reason dialog remains scrollable above the keyboard at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const RealmTextDialog(
                            title: 'Reject this post?',
                            label: 'Reason for the author',
                            initialValue:
                                'Please keep posts relevant to the community. This explanation can be several lines long.')),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        isTrue);
    expect(find.text('Save').hitTestable(), findsOneWidget);
  });
}
