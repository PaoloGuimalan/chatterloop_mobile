import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// One native callback lifecycle per widget-test isolate. FFmpeg's static
/// callback registration belongs to the first widget test's async zone.
class PendingRenderHarness {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  static const native = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
  static const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
  late Directory directory;
  late File photo;
  int? activeSession;
  Map<String, dynamic>? session;
  bool cancelled = false;
  int encodes = 0;
  int nextSession = 0;
  Future<void> install() async {
    directory = await Directory.systemTemp.createTemp('moment-render-close-');
    photo = File('${directory.path}/photo.png');
    await photo.writeAsBytes(img.encodePng(img.Image(width: 8, height: 8)));
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (_) async => {
              'appName': 'Test',
              'packageName': 'test.app',
              'version': '1',
              'buildNumber': '1',
              'buildSignature': ''
            });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(native, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'getPlatform':
          return 'android';
        case 'getArch':
          return 'arm64';
        case 'getPackageName':
          return 'full';
        case 'isLTSBuild':
          return false;
        case 'ffmpegSession':
          encodes++;
          final command = (args!['arguments'] as List).cast<String>();
          await File(command.last).writeAsBytes([1, 2, 3]);
          return session = {
            'sessionId': ++nextSession,
            'type': 1,
            'createTime': 1,
            'startTime': 1,
            'command': command.join(' ')
          };
        case 'asyncFFmpegSessionExecute':
          activeSession = args!['sessionId'] as int;
          return null; // Work stays pending until the user closes the editor.
        case 'cancelSession':
          cancelled = true;
          await messenger.handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope({
                'FFmpegKitCompleteCallbackEvent': {'sessionId': activeSession},
              }),
              (_) {});
          return null;
        case 'abstractSessionGetReturnCode':
          return cancelled ? 255 : 0;
        case 'getSession':
          return session;
        default:
          return null;
      }
    });
  }

  Future<void> dispose() async {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'), null);
    await directory.delete(recursive: true);
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    final watch = Stopwatch()..start();
    while (!done() && watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    expect(done(), isTrue);
  }
}
