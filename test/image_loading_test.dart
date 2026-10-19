import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/display_image.dart';
import 'package:chatterloop_app/core/media/image_byte_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StallingClient extends http.BaseClient {
  int active = 0;
  int peak = 0;
  int aborted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    active++;
    if (active > peak) peak = active;
    if (request is http.Abortable) {
      await request.abortTrigger;
      active--;
      aborted++;
      throw http.RequestAbortedException(request.url);
    }
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  test(
      'decode targets preserve aspect ratio, cover the tile, and cap long edges',
      () {
    const chat = DisplayImage(source: 'chat', width: 810);
    expect(chat.targetSize(4000, 3000), const Size(810, 608));
    const tile = DisplayImage(source: 'tile', width: 360, height: 360);
    expect(tile.targetSize(4000, 2000), const Size(720, 360));
    expect(tile.targetSize(2000, 4000), const Size(360, 720));
    const contain = DisplayImage(
        source: 'tile', width: 360, height: 360, fit: BoxFit.contain);
    expect(contain.targetSize(4000, 2000), const Size(360, 180));
    expect(chat.targetSize(100, 200), const Size(100, 200));
    expect(chat.targetSize(1000, 20000).longestSide, lessThanOrEqualTo(4096));
  });

  testWidgets(
      'chat-sized images decode for parent constraints and use no progress animation',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildCLTheme(Brightness.light),
      home: const Scaffold(
          body: Center(
              child: SizedBox(
                  width: 270,
                  child: CLNetworkImage(
                      src: 'https://example.invalid/photo.jpg')))),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as DisplayImage;
    expect(provider.width, 810);
    expect(image.loadingBuilder, isNull);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  group('original image byte cache', () {
    late Directory dir;
    setUp(() async =>
        dir = await Directory.systemTemp.createTemp('image-cache-test-'));
    tearDown(() async => dir.delete(recursive: true));

    test('decode-error eviction cannot be undone by a pending disk write', () async {
      var requests = 0;
      final cache = ImageByteCache(directory: () async => dir,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes([1, 2, 3], 200);
        }));
      await cache.bytes('https://cdn.test/broken');
      await cache.evict('https://cdn.test/broken');
      await cache.bytes('https://cdn.test/broken');
      expect(requests, 2);
      await cache.flush();
    });

    test(
        'deduplicates requests and reuses the original bytes across cache instances',
        () async {
      var requests = 0;
      final response = Completer<http.Response>();
      final client = MockClient((_) {
        requests++;
        return response.future;
      });
      final cache = ImageByteCache(directory: () async => dir, client: client);
      final first = cache.bytes('https://cdn.test/a.jpg');
      final second = cache.bytes('https://cdn.test/a.jpg');
      response.complete(http.Response.bytes([1, 2, 3], 200));
      expect(await first, Uint8List.fromList([1, 2, 3]));
      expect(await second, Uint8List.fromList([1, 2, 3]));
      await cache.flush();
      final reopened =
          ImageByteCache(directory: () async => dir, client: client);
      expect(await reopened.bytes('https://cdn.test/a.jpg'), [1, 2, 3]);
      expect(requests, 1);
      expect(await dir.list().where((e) => e.path.endsWith('.img')).length, 1);
    });

    test('bounds concurrent downloads and retries failures', () async {
      var active = 0;
      var peak = 0;
      var fail = true;
      final cache = ImageByteCache(
          directory: () async => dir,
          maxConcurrent: 2,
          client: MockClient((request) async {
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            active--;
            if (request.url.path == '/bad' && fail) {
              return http.Response('', 503);
            }
            return http.Response.bytes([1], 200);
          }));
      await Future.wait(
          List.generate(8, (i) => cache.bytes('https://cdn.test/$i')));
      expect(peak, 2);
      await expectLater(
          cache.bytes('https://cdn.test/bad'), throwsA(isA<Exception>()));
      fail = false;
      expect(await cache.bytes('https://cdn.test/bad'), [1]);
      await cache.flush();
    });

    test('prunes disk usage and refreshes expired entries', () async {
      var requests = 0;
      final cache = ImageByteCache(
          directory: () async => dir,
          maxBytes: 6,
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes([1, 2, 3, 4], 200);
          }));
      await cache.bytes('https://cdn.test/one');
      await cache.bytes('https://cdn.test/two');
      await cache.flush();
      final files = await dir
          .list()
          .where((e) => e.path.endsWith('.img'))
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      await files.single
          .setLastModified(DateTime.now().subtract(const Duration(days: 8)));
      await cache.bytes('https://cdn.test/two');
      expect(requests, 3);
      await cache.flush();
    });

    test('disk failure does not prevent displaying a downloaded image',
        () async {
      final cache = ImageByteCache(
          directory: () async => throw const FileSystemException('unavailable'),
          client: MockClient((_) async => http.Response.bytes([7], 200)));
      expect(await cache.bytes('https://cdn.test/a'), [7]);
      await cache.flush();
    });

    test(
        'logout invalidates pending bytes and allows a fresh request for the same URL',
        () async {
      final started = Completer<void>();
      final oldResponse = Completer<http.Response>();
      var requests = 0;
      final cache = ImageByteCache(
          directory: () async => dir,
          client: MockClient((_) {
            if (++requests == 1) {
              started.complete();
              return oldResponse.future;
            }
            return Future.value(http.Response.bytes([2], 200));
          }));
      final old = cache.bytes('https://cdn.test/private');
      final rejected =
          expectLater(old, throwsA(isA<http.RequestAbortedException>()));
      await started.future;
      await cache.clear();
      expect(await cache.bytes('https://cdn.test/private'), [2]);
      oldResponse.complete(http.Response.bytes([1], 200));
      await rejected;
      await cache.flush();
      final reopened = ImageByteCache(
          directory: () async => dir,
          client:
              MockClient((_) async => throw StateError('should be cached')));
      expect(await reopened.bytes('https://cdn.test/private'), [2]);
    });

    test('timeouts abort the actual request before releasing its download slot',
        () async {
      final client = _StallingClient();
      final cache = ImageByteCache(
          directory: () async => dir,
          client: client,
          maxConcurrent: 2,
          requestTimeout: const Duration(milliseconds: 10));
      await Future.wait(List.generate(
          4,
          (i) => expectLater(cache.bytes('https://cdn.test/stall$i'),
              throwsA(isA<http.RequestAbortedException>()))));
      expect(client.peak, 2);
      expect(client.active, 0);
      expect(client.aborted, 4);
    });
  });
}
