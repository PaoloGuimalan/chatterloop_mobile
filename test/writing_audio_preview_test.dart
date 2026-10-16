// The audio package's existing platform interface supplies native test doubles.
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_attachment.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const audio = DiaryAttachment(
    url: 'https://media.test/reflection.wav',
    fileName: 'Morning reflection.wav',
    fileType: 'audio/wav');

class _GlobalAudio extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  Future<void> setGlobalAudioContext(AudioContext context) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sinks = <String, MockStreamHandlerEventSink>{};
  final calls = <MethodCall>[];
  final pendingPrepared = <String>{};
  var failPlayback = false;
  setUp(() {
    // Each widget test owns a fresh FakeAsync initialization scope.
    GlobalAudioplayersPlatformInterface.instance = _GlobalAudio();
    sinks.clear();
    calls.clear();
    pendingPrepared.clear();
    failPlayback = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      calls.add(call);
      final id = (call.arguments as Map?)?['playerId'] as String?;
      if (call.method == 'create' && id != null) {
        messenger.setMockStreamHandler(
            EventChannel('xyz.luan/audioplayers/events/$id'),
            MockStreamHandler.inline(onListen: (_, sink) {
          sinks[id] = sink;
          if (pendingPrepared.remove(id)) {
            sink.success({'event': 'audio.onPrepared', 'value': true});
          }
        }));
      } else if (call.method == 'setSourceUrl' && id != null) {
        if (sinks[id] == null) {
          pendingPrepared.add(id);
        } else {
          sinks[id]!.success({'event': 'audio.onPrepared', 'value': true});
        }
      } else if (call.method == 'seek' && id != null) {
        sinks[id]?.success({'event': 'audio.onSeekComplete'});
      } else if (call.method == 'getDuration') {
        return 42000;
      } else if (call.method == 'getCurrentPosition') {
        return 0;
      } else if (call.method == 'resume' && failPlayback) {
        throw PlatformException(code: 'offline');
      }
      return null;
    });
  });
  Future<void> tick(WidgetTester tester) async {
    // The plugin polls playback position every frame while playing.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester,
      {Brightness brightness = Brightness.light,
      DiaryAttachment attachment = audio}) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildCLTheme(brightness),
        home: Scaffold(
            body: Center(child: WritingAttachment(attachment: attachment)))));
    await tick(tester);
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'writing audio uses the web card rather than the message waveform (${brightness.name})',
        (tester) async {
      await show(tester, brightness: brightness);
      expect(find.byType(VoiceMessagePlayer), findsNothing);
      final card = find.byKey(const ValueKey('writing-audio-preview'));
      expect(tester.getSize(card), const Size(150, 150));
      final box = tester.widget<Container>(card).decoration as BoxDecoration;
      expect(box.color, cl(tester.element(card)).surface2);
      expect(find.text('Morning reflection.wav'), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      expect(find.byTooltip('Play audio'), findsOneWidget);
      expect(find.byTooltip('Download'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tick(tester);
    });
  }
  testWidgets('writing audio plays, pauses, completes and replays',
      (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Play audio'));
    await tick(tester);
    expect(find.byTooltip('Pause audio'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause audio'));
    await tick(tester);
    expect(calls.any((call) => call.method == 'pause'), isTrue);
    await tester.tap(find.byTooltip('Play audio'));
    await tick(tester);
    sinks.values.single.success({'event': 'audio.onComplete'});
    await tick(tester);
    expect(find.byTooltip('Play audio'), findsOneWidget);
    await tester.tap(find.byTooltip('Play audio'));
    await tick(tester);
    expect(
        calls.any(
            (call) => call.method == 'seek' && call.arguments['position'] == 0),
        isTrue);
    expect(find.byTooltip('Pause audio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tick(tester);
    expect(calls.any((call) => call.method == 'stop'), isTrue);
    expect(calls.any((call) => call.method == 'release'), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'writing audio can retry a failed play without breaking the screen',
      (tester) async {
    await show(tester);
    failPlayback = true;
    await tester.tap(find.byTooltip('Play audio'));
    await tick(tester);
    expect(find.byTooltip('Retry audio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    failPlayback = false;
    await tester.tap(find.byTooltip('Retry audio'));
    await tick(tester);
    expect(find.byTooltip('Pause audio'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tick(tester);
  });
  testWidgets('replacing an audio attachment disposes the previous player',
      (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Play audio'));
    await tick(tester);
    await show(tester,
        attachment: const DiaryAttachment(
            url: 'https://media.test/new.wav',
            fileName: 'New clip.wav',
            fileType: 'audio/wav'));
    expect(find.byTooltip('Play audio'), findsOneWidget);
    expect(find.text('New clip.wav'), findsOneWidget);
    expect(calls.where((call) => call.method == 'create').length, 2);
    expect(calls.any((call) => call.method == 'stop'), isTrue);
    expect(calls.any((call) => call.method == 'release'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tick(tester);
  });
}
