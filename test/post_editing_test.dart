import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_edit.dart';
import 'package:chatterloop_app/core/utils/post_updates.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const author = PostPreviewAuthor(
    entityId: 'owner',
    type: 'user',
    displayName: 'Alex',
    handle: 'alex',
    isVerified: false);
final original = PostPreview(
    postId: 'post',
    caption: 'Before',
    datePosted: DateTime.utc(2026, 1, 1),
    references: const [
      PostReference(
          referenceId: 'kept',
          reference: 'https://example.com/photo.jpg',
          mediaType: 'image/jpeg')
    ],
    reactions: const [PostReactionCount(emoji: 'like', count: 4)],
    author: author,
    likesCount: 4,
    commentsCount: 9,
    isShared: false,
    isSaved: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => PostUpdates.instance.clear());
  test('canonical content patches preserve identity and engagement', () {
    final updated = original.applyPatch({
      'post_id': 'post',
      'caption': 'After',
      'updated_at': '2026-10-16T02:00:00Z',
      'is_edited': true,
      'references': [
        {
          'reference_id': 'kept',
          'reference': 'https://example.com/photo.jpg',
          'reference_media_type': 'image/jpeg'
        }
      ],
      'link_preview': null,
    });
    expect(updated.caption, 'After');
    expect(updated.isEdited, isTrue);
    expect(updated.updatedAt, DateTime.utc(2026, 10, 16, 2));
    expect(updated.datePosted, original.datePosted);
    expect(updated.author, same(author));
    expect(updated.reactions, same(original.reactions));
    expect(updated.commentsCount, 9);
    expect(updated.likesCount, 4);
    expect(updated.isSaved, isTrue);
    expect(updated.references.single.referenceId, 'kept');
  });

  test('audience patches never invent an edit timestamp', () {
    final updated =
        original.applyPatch({'post_id': 'post', 'privacy_status': 'private'});
    expect(updated.privacyStatus, 'private');
    expect(updated.updatedAt, isNull);
    expect(updated.isEdited, isFalse);
    expect(updated.caption, original.caption);
    expect(updated.references, same(original.references));
  });

  test('shared patches keep live engagement and archive toggles', () {
    PostUpdates.instance
        .apply({'post_id': 'post', 'caption': 'After', 'is_archived': false});
    final live = original.copyWith(commentsCount: 12, isArchived: true);
    final updated = PostUpdates.instance.resolve(live);
    expect(updated.caption, 'After');
    expect(updated.commentsCount, 12);
    expect(updated.isArchived, true);
  });

  test('changing the active identity clears cached edits', () {
    final session = PostUpdates.instance.session;
    PostUpdates.instance.apply({'post_id': 'post', 'caption': 'Private edit'});
    appStore.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount('other-account', 'other', 'Other', '', '', null, true,
                true, null, null, null, null,
                personalEntityId: 'other-entity'))));
    expect(PostUpdates.instance.resolve(original).caption, 'Before');
    PostUpdates.instance.apply({'post_id': 'post', 'caption': 'Late result'},
        forSession: session);
    expect(PostUpdates.instance.resolve(original).caption, 'Before');
  });

  test('a fresh newer server revision wins over the cached edit', () {
    PostUpdates.instance.apply({
      'post_id': 'post',
      'caption': 'Old local edit',
      'updated_at': '2026-10-16T02:00:00Z',
      'is_edited': true
    });
    final fresh = original.copyWith(
        caption: 'New server revision',
        updatedAt: DateTime.utc(2026, 10, 16, 3),
        isEdited: true);
    expect(PostUpdates.instance.resolve(fresh).caption, 'New server revision');
  });

  Future<void> open(WidgetTester tester, PostPreview post) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
            builder: (ctx) => Scaffold(
                body: TextButton(
                    onPressed: () => openPostEditor(ctx, post),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  CLBtn saveButton(WidgetTester tester) =>
      tester.widget<CLBtn>(find.widgetWithText(CLBtn, 'Save changes'));

  testWidgets(
      'only dirty, nonempty content can save; dirty back asks to discard',
      (tester) async {
    await open(tester, original.copyWith(references: []));
    expect(saveButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' ');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), original.caption);
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(PostEditScreen), findsNothing);
  });

  testWidgets(
      'profile and cover keep plain original media without attachment controls',
      (tester) async {
    for (final kind in ['profile', 'cover_photo']) {
      await open(tester, original.copyWith(contentType: kind));
      expect(find.byType(PageView), findsNothing);
      expect(find.byTooltip('Remove attachment'), findsNothing);
      expect(find.text('Add media'), findsNothing);
      expect(find.byType(CLNetworkImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'saving a removal keeps retained IDs and only applies canonical content',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 'post-edit-session'});
    appStore.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount('account', 'alex', 'Alex', '', '', null, true, true,
                null, null, null, null,
                personalEntityId: 'owner'))));
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.of(dio.interceptors);
    final requests = <RequestOptions>[];
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'status': true,
        'changed': true,
        'post': {
          'post_id': 'post',
          'caption': 'Canonical caption',
          'is_edited': true,
          'updated_at': '2026-10-16T02:00:00Z',
          'references': [
            {
              'reference_id': 'second',
              'reference': 'https://example.com/second.jpg',
              'reference_media_type': 'image/jpeg'
            }
          ],
        },
      }));
    }));
    addTearDown(() {
      dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
      dio.interceptors.addAll(previous);
    });
    await open(
        tester,
        original.copyWith(references: [
          ...original.references,
          const PostReference(
              referenceId: 'second',
              reference: 'https://example.com/second.jpg',
              mediaType: 'image/jpeg')
        ]));
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(requests.single.method, 'PUT');
    expect(requests.single.extra['authToken'], 'post-edit-session');
    expect(requests.single.path, '/api/newsfeed/default');
    expect(requests.single.data, {
      'post_id': 'post',
      'fields': {
        'caption': 'Before',
        'references': [
          {'reference_id': 'second'}
        ]
      }
    });
    final resolved = PostUpdates.instance.resolve(original);
    expect(resolved.caption, 'Canonical caption');
    expect(resolved.references.single.referenceId, 'second');
    expect(resolved.commentsCount, 9);
    expect(find.byType(PostEditScreen), findsNothing);
  });

  testWidgets('an in-flight save never publishes into a switched identity',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 'original-session'});
    appStore.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount('account', 'alex', 'Alex', '', '', null, true, true,
                null, null, null, null,
                personalEntityId: 'owner'))));
    final dio = ApiClient.userService.dio;
    final previous = List<Interceptor>.of(dio.interceptors);
    final requests = <RequestOptions>[];
    dio.interceptors.clear();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      FlutterSecureStorage.setMockInitialValues({'token': 'other-session'});
      appStore.dispatch(DispatchModel(
          setUserAuthT,
          UserAuth(
              true,
              UserAccount('other-account', 'other', 'Other', '', '', null, true,
                  true, null, null, null, null,
                  personalEntityId: 'other-entity'))));
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'status': true,
        'post': {
          'post_id': 'post',
          'caption': 'Late saved caption',
          'is_edited': true
        }
      }));
    }));
    addTearDown(() {
      dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
      dio.interceptors.addAll(previous);
    });
    await open(tester, original.copyWith(references: []));
    await tester.enterText(find.byType(TextField), 'New caption');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(requests.single.extra['authToken'], 'original-session');
    expect(PostUpdates.instance.resolve(original).caption, 'Before');
    expect(find.byType(PostEditScreen), findsOneWidget);
  });

  testWidgets(
      'audience is separate and changing its selection never changes content',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.dark),
        home: Scaffold(body: PostAudienceSheet(post: original))));
    final save = find.widgetWithText(CLBtn, 'Save audience');
    expect(tester.widget<CLBtn>(save).onPressed, isNull);
    await tester.tap(find.text('Contacts only'));
    await tester.pump();
    expect(tester.widget<CLBtn>(save).onPressed, isNotNull);
    expect(find.byType(TextField), findsNothing);
    expect(original.isEdited, false);
    expect(tester.takeException(), isNull);
  });
}
