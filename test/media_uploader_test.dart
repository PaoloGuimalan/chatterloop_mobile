// The direct-upload client: limits from /media/config, the attachment model,
// and MediaUploader against fake API and storage servers (no network).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatterloop_app/core/media/media_uploader.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/messages_models/message_attachment_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers requests from a handler and records each one, body included.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options, Uint8List body)
      handler;
  final List<({RequestOptions options, Uint8List body})> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final body = Uint8List.fromList(bytes);
    requests.add((options: options, body: body));
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Dio _dio(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.invalid'))..httpClientAdapter = adapter;

Future<String> _tempFile(String name, int size) async {
  final dir = await Directory.systemTemp.createTemp('uploader_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(List.generate(size, (i) => i % 251));
  return file.path;
}

Map<String, dynamic> _bodyOf(RequestOptions o) =>
    o.data is Map ? Map<String, dynamic>.from(o.data) : jsonDecode(o.data);

void main() {
  setUp(UploadLimits.reset);

  group('limits', () {
    test('stored values override defaults; a broken entry keeps its own', () {
      UploadLimits.applyJson({
        'limits': {
          'message': {'maxMB': 50, 'types': ['*']},
          'avatar': {'maxMB': 'lots'},
        },
        'transfer': {'partSizeMB': 1, 'concurrency': 99},
      });
      expect(UploadLimits.of(UploadFeature.message).maxMB, 50);
      expect(UploadLimits.of(UploadFeature.avatar).maxMB, 10);
      expect(UploadLimits.of(UploadFeature.voiceNote).label, '25MB');
      expect(UploadLimits.transfer.partSizeMB, 5); // storage's floor
      expect(UploadLimits.transfer.concurrency, 8);
    });

    test('type patterns match exactly, by family, or anything', () {
      const limit = UploadLimit(10, ['image/*', 'video/mp4']);
      expect(limit.allows('image/png'), isTrue);
      expect(limit.allows('video/mp4'), isTrue);
      expect(limit.allows('video/webm'), isFalse);
      expect(const UploadLimit(1, ['*']).allows('application/zip'), isTrue);
    });

    test('the declared type comes from the extension', () {
      expect(mimeForPath('/a/b/clip.MP4'), 'video/mp4');
      expect(mimeForPath('voice.m4a'), 'audio/mp4');
      expect(mimeForPath('noext'), 'application/octet-stream');
    });
  });

  group('attachment', () {
    test('parses the server shape; a gone file is unavailable', () {
      final a = MessageAttachment.tryParse({
        'url': 'https://m.invalid/x.pdf',
        'name': 'Report Q3.pdf',
        'size': 2516582,
        'status': 'unavailable',
      })!;
      expect(a.name, 'Report Q3.pdf');
      expect(a.sizeLabel, '2.4 MB');
      expect(a.available, isFalse);
      expect(MessageAttachment.tryParse(null), isNull);
      expect(MessageAttachment.tryParse({'name': 'no url'}), isNull);
    });

    test('sizes read naturally', () {
      expect(formatFileSize(830 * 1024), '830 KB');
      expect(formatFileSize(12), '12 B');
      expect(formatFileSize(25 * 1024 * 1024), '25 MB');
      expect(formatFileSize(null), '');
    });
  });

  group('MediaUploader', () {
    test('a small file: one signed PUT with its headers, then complete',
        () async {
      final path = await _tempFile('photo.png', 3000);
      final storage = _FakeAdapter((o, body) =>
          ResponseBody.fromString('', 200, headers: {'etag': ['"e1"']}));
      final api = _FakeAdapter((o, body) {
        if (o.path == '/media/uploads') {
          return _json({
            'uploads': [
              {
                'uploadID': 'FILE_1',
                'name': 'photo.png',
                'fileUrl': 'https://media.invalid/photo.png',
                'mode': 'single',
                'method': 'PUT',
                'url': 'https://storage.invalid/put?sig=1',
                'headers': {'Content-Type': 'image/png'},
              }
            ]
          });
        }
        return _json({
          'results': [
            {
              'ok': true,
              'uploadID': 'FILE_1',
              'fileUrl': 'https://media.invalid/photo.png',
              'name': 'photo.png',
              'mime': 'image/png',
              'kind': 'image',
              'size': 3000,
            }
          ]
        });
      });

      final progress = <double>[];
      final result = await MediaUploader(api: _dio(api), storage: _dio(storage))
          .upload(
        purpose: UploadFeature.postMedia,
        paths: [path],
        onProgress: progress.add,
      );

      expect(result.single.fileUrl, 'https://media.invalid/photo.png');
      expect(result.single.kind, 'image');
      final asked = _bodyOf(api.requests.first.options);
      expect(asked['purpose'], 'post_media');
      expect((asked['files'] as List).single,
          {'name': 'photo.png', 'size': 3000, 'type': 'image/png'});
      final put = storage.requests.single;
      expect(put.options.method, 'PUT');
      expect(put.options.headers['Content-Type'], 'image/png');
      expect(put.body.length, 3000);
      // No app credentials ever reach storage.
      expect(put.options.headers.containsKey('x-access-token'), isFalse);
      expect(progress.last, 1.0);
    });

    test('a big file goes up in parts with the right byte ranges', () async {
      final path = await _tempFile('clip.mp4', 25);
      final storage = _FakeAdapter((o, body) {
        final n = Uri.parse(o.uri.toString()).queryParameters['part'];
        return ResponseBody.fromString('', 200, headers: {'etag': ['"etag$n"']});
      });
      Map<String, dynamic>? completed;
      final api = _FakeAdapter((o, body) {
        if (o.path == '/media/uploads') {
          return _json({
            'uploads': [
              {
                'uploadID': 'FILE_2',
                'name': 'clip.mp4',
                'fileUrl': 'https://media.invalid/clip.mp4',
                'mode': 'multipart',
                'partSize': 10,
                'parts': [
                  for (final n in [1, 2, 3])
                    {
                      'n': n,
                      'size': n < 3 ? 10 : 5,
                      'method': 'PUT',
                      'url': 'https://storage.invalid/part?part=$n',
                      'headers': {},
                    }
                ],
              }
            ]
          });
        }
        completed = _bodyOf(o);
        return _json({
          'results': [
            {
              'ok': true,
              'uploadID': 'FILE_2',
              'fileUrl': 'https://media.invalid/clip.mp4',
              'name': 'clip.mp4',
              'mime': 'video/mp4',
              'kind': 'video',
              'size': 25,
            }
          ]
        });
      });

      await MediaUploader(api: _dio(api), storage: _dio(storage)).upload(
        purpose: UploadFeature.postMedia,
        paths: [path],
      );

      final bytes = await File(path).readAsBytes();
      for (final r in storage.requests) {
        final n = int.parse(r.options.uri.queryParameters['part']!);
        expect(r.body, bytes.sublist((n - 1) * 10, (n - 1) * 10 + (n < 3 ? 10 : 5)));
      }
      final parts = ((completed!['uploads'] as List).single['parts'] as List)
          .map((p) => (p['n'], p['etag']))
          .toSet();
      expect(parts, {(1, '"etag1"'), (2, '"etag2"'), (3, '"etag3"')});
    });

    test('an expired part link is refreshed and retried', () async {
      final path = await _tempFile('clip.mp4', 20);
      var refused = false;
      final storage = _FakeAdapter((o, body) {
        if (o.uri.toString().contains('stale') && !refused) {
          refused = true;
          return ResponseBody.fromString('', 403);
        }
        return ResponseBody.fromString('', 200, headers: {'etag': ['"ok"']});
      });
      final api = _FakeAdapter((o, body) {
        if (o.path == '/media/uploads') {
          return _json({
            'uploads': [
              {
                'uploadID': 'FILE_3',
                'name': 'clip.mp4',
                'fileUrl': 'https://media.invalid/clip.mp4',
                'mode': 'multipart',
                'partSize': 10,
                'parts': [
                  {'n': 1, 'size': 10, 'method': 'PUT', 'url': 'https://storage.invalid/stale', 'headers': {}},
                  {'n': 2, 'size': 10, 'method': 'PUT', 'url': 'https://storage.invalid/p2', 'headers': {}},
                ],
              }
            ]
          });
        }
        if (o.path.endsWith('/parts')) {
          return _json({
            'parts': [
              {'n': 1, 'size': 10, 'method': 'PUT', 'url': 'https://storage.invalid/fresh', 'headers': {}}
            ]
          });
        }
        return _json({
          'results': [
            {'ok': true, 'uploadID': 'FILE_3', 'fileUrl': 'u', 'name': 'clip.mp4', 'mime': 'video/mp4', 'kind': 'video', 'size': 20}
          ]
        });
      });

      await MediaUploader(api: _dio(api), storage: _dio(storage)).upload(
        purpose: UploadFeature.postMedia,
        paths: [path],
      );
      expect(api.requests.any((r) => r.options.path == '/media/uploads/FILE_3/parts'), isTrue);
      expect(storage.requests.any((r) => r.options.uri.toString().contains('fresh')), isTrue);
    });

    test('too big is refused before anything is sent', () async {
      UploadLimits.applyJson({
        'limits': {
          'avatar': {'maxMB': 0.001, 'types': ['image/*']}
        }
      });
      final path = await _tempFile('big.png', 5000);
      final api = _FakeAdapter((o, body) => _json({}));
      await expectLater(
        MediaUploader(api: _dio(api), storage: _dio(api)).upload(
          purpose: UploadFeature.avatar,
          paths: [path],
        ),
        throwsA(isA<UploadFailure>().having((e) => e.status, 'status', 413)),
      );
      expect(api.requests, isEmpty);
    });

    test('a failed upload is cancelled on the server and its progress cleared',
        () async {
      final path = await _tempFile('doc.pdf', 100);
      final storage = _FakeAdapter((o, body) => ResponseBody.fromString('', 500));
      final api = _FakeAdapter((o, body) => o.path == '/media/uploads'
          ? _json({
              'uploads': [
                {
                  'uploadID': 'FILE_4',
                  'name': 'doc.pdf',
                  'fileUrl': 'u',
                  'mode': 'single',
                  'method': 'PUT',
                  'url': 'https://storage.invalid/x',
                  'headers': {},
                }
              ]
            })
          : _json({}));

      await expectLater(
        MediaUploader(api: _dio(api), storage: _dio(storage)).upload(
          purpose: UploadFeature.message,
          paths: [path],
          context: {'conversationID': 'c1'},
          progressKeys: ['pending-1'],
        ),
        throwsA(isA<UploadFailure>()),
      );
      // The cancel is fire-and-forget; let it go out.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        api.requests.any((r) =>
            r.options.method == 'DELETE' && r.options.path == '/media/uploads/FILE_4'),
        isTrue,
      );
      expect(UploadProgress.of('pending-1').value, isNull);
      expect(_bodyOf(api.requests.first.options)['context'], {'conversationID': 'c1'});
    });
  });
}
