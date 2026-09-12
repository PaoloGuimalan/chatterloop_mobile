// A message bubble's accent follows the thread it is in - brand blue in a
// conversation, gold in a server channel.
//
// conversation_view wraps the whole thread in one CLAccent so this is decided
// in a single place, and every bubble reads it from there. Two things have
// broken that:
//
//   1. a bubble reading cl(context).brand directly instead of the inherited
//      accent (VoiceMessagePlayer did, which left your own voice message the
//      one blue bubble in a gold channel)
//   2. the long-press preview, which is a PUSHED ROUTE - it builds under the
//      Navigator, so the thread's CLAccent is not an ancestor of anything in
//      it, and any child resolving the accent from where it is mounted fell
//      back to brand blue again
//
// The second is the subtle one: messageTypeSwitch resolves colours against the
// State's context, so the bubble itself looked right and only its child
// widgets were wrong.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_content_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/message_reactions_dialog.dart';
import 'package:chatterloop_app/models/messages_models/message_content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_test/flutter_test.dart';

/// What _accentFor hands a channel - conversation_view reads it off the
/// palette the same way.
Color _channelGold(WidgetTester tester) =>
    cl(tester.element(find.byType(MessageContentWidget))).gold;

MessageContent _ownMessage() => MessageContent.fromJson({
      "messageID": "m1",
      "conversationID": "c1",
      "sender": "me",
      "content": "hello",
      "messageType": "text",
      "messageDate": "2026-01-01T00:00:00.000Z",
    });

void main() {
  /// The thread as a CHANNEL renders it: the bubble under a gold CLAccent,
  /// exactly as conversation_view wraps it.
  Future<void> pumpChannelThread(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StoreProvider<AppState>(
      store: appStore,
      child: MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: Builder(
          builder: (context) => CLAccent(
            color: cl(context).gold,
            child: Scaffold(
              body: SingleChildScrollView(
                child: MessageContentWidget(
                  messageContent: _ownMessage(),
                  previousContentUserID: "end",
                  currentUserID: "me",
                  onPressed: (_, __) {},
                  resolveSenderName: (id) => id,
                  isSingleConversation: false,
                  conversationID: "c1",
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the accent flies with the hero', (tester) async {
    await pumpChannelThread(tester);
    final gold = _channelGold(tester);

    // INSIDE the Hero, not around it. A hero's child is re-parented into the
    // Navigator's overlay for the flight, which is under neither route, so
    // anything left outside is not inherited while the animation runs. The
    // default flight renders the DESTINATION hero's child - this one, on a pop
    // - which is why the bubble flashed brand blue on the way back from the
    // long-press preview and never on the way in.
    final flying = tester.widget<CLAccent>(find.descendant(
      of: find.byType(Hero),
      matching: find.byType(CLAccent),
    ));
    expect(flying.color, gold);
  });

  testWidgets('the long-press preview keeps the thread accent', (tester) async {
    await pumpChannelThread(tester);
    final gold = _channelGold(tester);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    // The dialog is a route of its own, so it has to carry the accent with it
    // - without this the preview's children resolve brand blue.
    final preview = tester.widget<CLAccent>(find.descendant(
      of: find.byType(CLMessageReactionsDialog),
      matching: find.byType(CLAccent),
    ));
    expect(preview.color, gold);
    expect(preview.color, isNot(cl(tester.element(find.text('hello'))).brand));
  });
}
