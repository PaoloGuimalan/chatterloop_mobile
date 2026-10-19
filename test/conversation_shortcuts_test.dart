import 'dart:async';

import 'package:chatterloop_app/core/notifications/conversation_shortcuts.dart';
import 'package:chatterloop_app/models/messages_models/messages_list_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chatterloop/conversation_shortcuts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MessageItem chat(String name) => MessageItem.fromJson({
        'conversationID': 'c1',
        'details': {'display_name': name},
      });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'concurrent and unchanged shortcut syncs publish only once; logout resets them',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final gate = Completer<bool>();
    var syncs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'sync') {
        syncs++;
        return gate.future;
      }
      return true;
    });
    await ConversationShortcuts.clearAll();
    final first = ConversationShortcuts.sync([chat('Alice')]);
    final concurrent = ConversationShortcuts.sync([chat('Alice')]);
    gate.complete(true);
    await Future.wait([first, concurrent]);
    await ConversationShortcuts.sync([chat('Alice')]);
    expect(syncs, 1);
    await ConversationShortcuts.sync([chat('Alice updated')]);
    expect(syncs, 2);
    await ConversationShortcuts.clearAll();
    await ConversationShortcuts.sync([chat('Alice updated')]);
    expect(syncs, 3);
  });

  test('failed native publishing can be retried', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var syncs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'sync') return true;
      syncs++;
      return syncs > 1;
    });
    await ConversationShortcuts.clearAll();
    await ConversationShortcuts.sync([chat('Bob')]);
    await ConversationShortcuts.sync([chat('Bob')]);
    expect(syncs, 2);
  });
}
