// A received voice note is tinted with its conversation's accent - brand blue,
// or a channel's gold - in both themes, rather than the plain surface it used
// to be, which is the chat's own background (the clip showed as an outline
// only). A channel's info and shared-files screens follow the same gold.
//
// The player opens a real audioplayers player when built, so its platform
// channels are stubbed: `create` names the player, and its event channel is
// answered under that name.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/models/messages_models/conversation_files_model.dart';
import 'package:chatterloop_app/views/messages/conversation_files_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _src = 'https://media.example.invalid/uploads/messages/c1/m1/voice.m4a';

void _stubAudioPlayers() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // Each player's event sink, so setting a source can answer "prepared" as
  // the real plugin does - the player waits for it.
  final sinks = <String, MockStreamHandlerEventSink>{};
  messenger.setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers.global/events'),
      MockStreamHandler.inline(onListen: (_, __) {}));
  messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null);
  messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'), (call) async {
    final id = (call.arguments as Map?)?['playerId'] as String?;
    if (call.method == 'create' && id != null) {
      messenger.setMockStreamHandler(
          EventChannel('xyz.luan/audioplayers/events/$id'),
          MockStreamHandler.inline(onListen: (_, sink) {
        sinks[id] = sink;
      }));
    } else if (call.method == 'setSourceUrl' && id != null) {
      sinks[id]?.success({'event': 'audio.onPrepared', 'value': true});
    }
    return null;
  });
}

/// The player's own box - the one carrying its fill and outline.
BoxDecoration _box(WidgetTester tester) {
  final box = find
      .descendant(
          of: find.byType(VoiceMessagePlayer), matching: find.byType(Container))
      .first;
  return tester.widget<Container>(box).decoration as BoxDecoration;
}

Future<CLPalette> _pumpNote(WidgetTester tester,
    {required Brightness brightness,
    bool isSender = false,
    Color? accent}) async {
  Widget note = const VoiceMessagePlayer(src: _src, isSender: false);
  if (isSender) note = const VoiceMessagePlayer(src: _src, isSender: true);
  await tester.pumpWidget(MaterialApp(
    theme: buildCLTheme(brightness),
    home: Scaffold(
      body: Center(
        child: accent == null ? note : CLAccent(color: accent, child: note),
      ),
    ),
  ));
  await tester.pump();
  return cl(tester.element(find.byType(VoiceMessagePlayer)));
}

void main() {
  setUp(_stubAudioPlayers);

  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      testWidgets('a received note in a DM is tinted blue, not the background',
          (tester) async {
        final p = await _pumpNote(tester, brightness: brightness);
        final box = _box(tester);
        expect(box.color, VoiceMessagePlayer.receivedFill(p, p.brand));
        expect(box.color, isNot(p.surface));
        expect((box.border as Border).top.color,
            VoiceMessagePlayer.receivedOutline(p, p.brand));
      });

      testWidgets("a received note in a channel takes the channel's gold",
          (tester) async {
        final p = await _pumpNote(tester,
            brightness: brightness, accent: CLPalette.light.gold);
        expect(_box(tester).color, VoiceMessagePlayer.receivedFill(p, p.gold));
      });

      testWidgets('your own note is unchanged: the accent itself',
          (tester) async {
        final p = await _pumpNote(tester,
            brightness: brightness,
            isSender: true,
            accent: CLPalette.light.gold);
        expect(_box(tester).color, p.gold);
      });
    });
  }

  group("a channel's shared files", () {
    Future<CLPalette> pumpFiles(WidgetTester tester, String type) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(Brightness.light),
        home: ConversationFilesScreen(
          conversationId: 'conv-1',
          conversationType: type,
          title: '#general',
          initialKind: ConversationFileKind.audio,
          fetch: (kinds, cursor, limit) async => ConversationFilesPage(
            items: [
              ConversationFileItem(
                messageID: 'a1',
                sender: 'them',
                kind: ConversationFileKind.audio,
                mimeType: 'audio/mpeg',
                content: _src,
                sentAt: DateTime.now(),
              ),
            ],
            nextCursor: null,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return cl(tester.element(find.byType(ConversationFilesScreen)));
    }

    testWidgets('are gold: the tab underline and every clip', (tester) async {
      final p = await pumpFiles(tester, 'channel');
      expect(tester.widget<TabBar>(find.byType(TabBar)).indicatorColor, p.gold);
      expect(_box(tester).color, VoiceMessagePlayer.receivedFill(p, p.gold));
    });

    testWidgets("anyone else's stay blue", (tester) async {
      final p = await pumpFiles(tester, 'single');
      expect(
          tester.widget<TabBar>(find.byType(TabBar)).indicatorColor, p.brand);
      expect(_box(tester).color, VoiceMessagePlayer.receivedFill(p, p.brand));
    });
  });

  testWidgets("a channel's See all is drawn in the gold made for text",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: Scaffold(
        body: ConversationAccentScope(
          conversationType: 'server',
          child: ConversationMediaPreview(
            conversationId: 'conv-1',
            conversationType: 'server',
            title: '#general',
            fetch: (kinds, cursor, limit) async =>
                const ConversationFilesPage(items: []),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    final p = cl(tester.element(find.text('See all')));
    expect(tester.widget<Text>(find.text('See all')).style?.color, p.goldText);
  });
}
