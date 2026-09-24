// Replies to things that are not messages (a post sent into a chat, a reply to
// a moment or a thought), and the Share -> "Send in message" flow.
//
// The wire contract is the part worth pinning: the server STORES replyingTo as
// {type, id} but keeps SENDING it as the bare message id (or ""), so every
// installed build keeps reading replies as it always has. These tests hold
// the parsing to both shapes and the new card to the 360px layout rule.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/post/post_send.dart';
import 'package:chatterloop_app/core/reusables/widgets/reply_target_card.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:chatterloop_app/models/messages_models/reply_target_model.dart';
import 'package:chatterloop_app/models/messages_models/send_post_targets_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

const _longName = 'Bartholomew Maximilian Villaverde-Santos de la Cruz';
const _longCaption =
    'A very long caption that goes on well past what two lines of a reply card '
    'can hold, because people write paragraphs under their photos and the card '
    'must clip them instead of growing without end.';

Map<String, dynamic> _target({
  String type = 'post',
  String status = 'active',
  Map<String, dynamic>? content,
  String authorId = 'author-1',
  String authorName = _longName,
}) =>
    {
      'type': type,
      'id': '$type-1',
      'status': status,
      'author': {
        'entity_id': authorId,
        'type': 'user',
        'display_name': authorName,
        'handle': 'bart',
        'profile': 'none',
      },
      if (content != null) 'content': content,
    };

MessageContent _message({
  required dynamic replyingTo,
  Map<String, dynamic>? replyedtarget,
  List<Map<String, dynamic>> replyedmessage = const [],
  String sender = 'me',
  String content = '',
}) =>
    MessageContent.fromJson({
      'messageID': 'm1',
      'conversationID': 'c1',
      'sender': sender,
      'content': content,
      'messageType': 'text',
      'isReply': true,
      'replyingTo': replyingTo,
      'replyedmessage': replyedmessage,
      if (replyedtarget != null) 'replyedtarget': replyedtarget,
      'messageDate': '2026-09-24T08:00:00.000Z',
    });

void main() {
  group('replyingTo on the wire', () {
    test('a bare string is the replied-to message id (what the server sends)',
        () {
      expect(replyingToMessageId('abc123'), 'abc123');
      expect(replyingToMessageId(''), '');
      expect(replyingToMessageId(null), '');
    });

    test('a stored object still reads as a message id, never as a map dump',
        () {
      expect(replyingToMessageId({'type': 'message', 'id': 'abc'}), 'abc');
      expect(replyingToMessageId({'type': 'post', 'id': 'p1'}), '');
    });

    test('MessageContent and MessageItem parse either shape', () {
      expect(_message(replyingTo: 'm0').replyingTo, 'm0');
      expect(
          _message(replyingTo: {'type': 'message', 'id': 'm0'}).replyingTo,
          'm0');
      expect(_message(replyingTo: {'type': 'moment', 'id': 'x'}).replyingTo,
          '');

      final item = MessageItem.fromJson({
        'conversationID': 'c1',
        'replyingTo': {'type': 'message', 'id': 'm9'},
      });
      expect(item.replyingTo, 'm9');
    });
  });

  group('ReplyTarget', () {
    test('parses a live post card', () {
      final target = ReplyTarget.tryParse(_target(content: {
        'caption': 'hello',
        'thumbnail': 'https://cdn.example/p.jpg',
        'media_type': 'image/jpeg',
        'file_type': 'media',
      }))!;
      expect(target.type, 'post');
      expect(target.caption, 'hello');
      expect(target.thumbnail, 'https://cdn.example/p.jpg');
      expect(target.author!.profile, isNull, reason: '"none" is no photo');
      expect(target.isLiveAt(DateTime.now()), isTrue);
    });

    test('a moment expires by the clock, not only by the server', () {
      final soon = DateTime.now().add(const Duration(minutes: 5));
      final target = ReplyTarget.tryParse(_target(
        type: 'moment',
        content: {'expires_at': soon.toUtc().toIso8601String()},
      ))!;
      expect(target.isExpiredAt(DateTime.now()), isFalse);
      expect(target.isExpiredAt(soon.add(const Duration(seconds: 1))), isTrue);
    });

    test('expired and unavailable are not live', () {
      expect(
          ReplyTarget.tryParse(_target(type: 'moment', status: 'expired'))!
              .isLiveAt(DateTime.now()),
          isFalse);
      expect(
          ReplyTarget.tryParse(_target(status: 'unavailable'))!
              .isLiveAt(DateTime.now()),
          isFalse);
    });

    test('anything malformed is no card, not a crash', () {
      expect(ReplyTarget.tryParse(null), isNull);
      expect(ReplyTarget.tryParse('post'), isNull);
      expect(ReplyTarget.tryParse({'type': 'post'}), isNull);
    });

    test('labels', () {
      final post = ReplyTarget.tryParse(_target())!;
      final myMoment =
          ReplyTarget.tryParse(_target(type: 'moment', authorId: 'me'))!;
      final hisThought = ReplyTarget.tryParse(
          _target(type: 'thought', authorName: 'Ana'))!;
      expect(replyTargetLabel(post, currentEntityId: 'me'), 'sent a post');
      expect(replyTargetLabel(myMoment, currentEntityId: 'me'),
          'replied to your moment');
      expect(replyTargetLabel(hisThought, currentEntityId: 'me'),
          "replied to Ana's thought");
    });
  });

  group('layout at 360px', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ));
      await tester.pump();
    }

    final cards = <String, Map<String, dynamic>>{
      'post with a long caption':
          _target(content: {'caption': _longCaption, 'file_type': 'text'}),
      'shared post': _target(content: {
        'caption': 'look',
        'file_type': 'shared_post',
        'shared_post_id': 'orig-1'
      }),
      'video moment': _target(type: 'moment', content: {
        'thumbnail': 'https://cdn.example/m.mp4',
        'media_type': 'video/mp4',
        'caption': _longCaption,
        'expires_at':
            DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
      }),
      'expired moment': _target(type: 'moment', status: 'expired'),
      'thought':
          _target(type: 'thought', content: {'text': 'sixty characters of thought right here ok'}),
      'unavailable post': _target(status: 'unavailable'),
    };

    for (final entry in cards.entries) {
      for (final alignEnd in [false, true]) {
        testWidgets('${entry.key} (${alignEnd ? "mine" : "theirs"})',
            (tester) async {
          await pump(
            tester,
            ReplyTargetCard(
              target: ReplyTarget.tryParse(entry.value)!,
              alignEnd: alignEnd,
            ),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a post with no attachment gets no thumbnail placeholder',
        (tester) async {
      await pump(
        tester,
        ReplyTargetCard(
          target: ReplyTarget.tryParse(
              _target(content: {'caption': 'Hello World!', 'file_type': 'text'}))!,
        ),
      );
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      expect(find.byType(CLNetworkImage), findsNothing);
      expect(find.text('Hello World!'), findsOneWidget);
    });

    testWidgets('a post with an image shows it', (tester) async {
      await pump(
        tester,
        ReplyTargetCard(
          target: ReplyTarget.tryParse(_target(content: {
            'caption': 'look',
            'thumbnail': 'https://cdn.example/p.jpg',
            'media_type': 'image/jpeg',
          }))!,
        ),
      );
      expect(find.byType(CLNetworkImage), findsOneWidget);
    });

    testWidgets('a gone card says why and keeps its author', (tester) async {
      await pump(
        tester,
        ReplyTargetCard(
          target: ReplyTarget.tryParse(
              _target(type: 'moment', status: 'expired', authorName: 'Ana'))!,
        ),
      );
      expect(find.text('Moment expired'), findsOneWidget);
      expect(find.text('Moment · Ana'), findsOneWidget);
    });

    testWidgets('every kind of send destination lays out', (tester) async {
      final targets = SendPostTargets.fromJson({
        'direct': [
          {'entity_id': 'u1', 'type': 'user', 'display_name': _longName, 'handle': 'bart_the_long_handle', 'profile': 'none'},
          {'entity_id': 'p1', 'type': 'realm', 'display_name': 'Manila Runners Club Official Page', 'handle': 'manilarunners', 'profile': null},
        ],
        'groups': [
          {'conversation_id': 'g1', 'display_name': _longName, 'profile': null},
        ],
        'channels': [
          {'conversation_id': 'c1', 'display_name': 'announcements-and-very-long-channel', 'server_name': 'Dev Loop Server With A Long Name', 'server_profile': null},
        ],
      });
      expect(targets.direct.first.target, const SendPostTarget.entity('u1'));
      expect(targets.direct[1].subtitle, 'Page · @manilarunners');
      expect(targets.channels.first.subtitle, 'Server · Dev Loop Server With A Long Name');
      for (final option in [...targets.direct, ...targets.groups, ...targets.channels]) {
        for (final selected in [false, true]) {
          await pump(
            tester,
            SendPostOptionRow(
              option: option,
              selected: selected,
              enabled: !selected,
              onTap: () {},
            ),
          );
          expect(tester.takeException(), isNull, reason: option.title);
        }
      }
    });
  });

  group('in a conversation', () {
    Future<void> pumpBubble(WidgetTester tester, MessageContent content) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreProvider<AppState>(
        store: appStore,
        child: MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageContentWidget(
                messageContent: content,
                previousContentUserID: 'end',
                currentUserID: 'me',
                onPressed: (_, __) {},
                resolveSenderName: (id) => id == 'them' ? 'Theo' : id,
                isSingleConversation: true,
                conversationID: 'c1',
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a sent post draws its card and label', (tester) async {
      await pumpBubble(
        tester,
        _message(
          replyingTo: '',
          replyedtarget: _target(content: {'caption': 'hello there'}),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ReplyTargetCard), findsOneWidget);
      expect(find.text('sent a post'), findsOneWidget);
      expect(find.text('hello there'), findsOneWidget);
    });

    testWidgets('a message reply keeps its quote and gets no card',
        (tester) async {
      await pumpBubble(
        tester,
        _message(
          replyingTo: 'm0',
          content: 'agreed',
          replyedtarget: {
            'type': 'message',
            'id': 'm0',
            'status': 'active',
            'content': {'message_type': 'text', 'text': 'lunch?'},
          },
          replyedmessage: [
            {
              'messageID': 'm0',
              'conversationID': 'c1',
              'sender': 'them',
              'content': 'lunch?',
              'messageType': 'text',
              'messageDate': '2026-09-24T07:00:00.000Z',
            }
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ReplyTargetCard), findsNothing);
      expect(find.text('replied to Theo'), findsOneWidget);
    });

    testWidgets(
        'a reply whose target could not be resolved still renders (old server)',
        (tester) async {
      // No replyedtarget and an empty replyedmessage: what an older server
      // sends for a reply whose original is gone. Nothing to quote - and
      // nothing may throw.
      await pumpBubble(tester, _message(replyingTo: 'gone', content: 'hm'));
      expect(tester.takeException(), isNull);
      expect(find.byType(ReplyTargetCard), findsNothing);
    });
  });

  group('the Share sheet', () {
    testWidgets('offers both ways to share and returns the choice',
        (tester) async {
      ShareChoice? chosen;
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  chosen = await showShareOptionsSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Share to feed'), findsOneWidget);
      expect(find.text('Send in message'), findsOneWidget);

      await tester.tap(find.text('Send in message'));
      await tester.pumpAndSettle();
      expect(chosen, ShareChoice.inMessage);
    });
  });
}
