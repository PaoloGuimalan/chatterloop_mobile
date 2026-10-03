// Direct uploads: the bytes go straight from the phone to storage, never
// through our server.
//
//   1. ask   POST /media/uploads - one signed link, or one per part for big
//            files (server/routes/media/index.js)
//   2. send  PUT each link - several parts at once, each retried on its own
//   3. done  POST /media/uploads/complete - the server checks what arrived
//
// The links point at the storage provider, not at us, so they're sent with a
// bare Dio: none of ApiClient's headers (token, nonce, device) ever reach it.

import 'dart:async';
import 'dart:io';

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// What storage now holds, as the server confirmed it.
class UploadedFile {
  const UploadedFile({
    required this.uploadId,
    required this.fileUrl,
    required this.name,
    required this.mime,
    required this.kind,
    required this.size,
    this.messageId,
  });

  final String uploadId;

  /// The file's public link.
  final String fileUrl;
  final String name;
  final String mime;

  /// image | video | audio | file
  final String kind;
  final int size;

  /// For message uploads: the id the message will be created under.
  final String? messageId;

  factory UploadedFile.fromJson(Map<String, dynamic> json) => UploadedFile(
        uploadId: json['uploadID'].toString(),
        fileUrl: json['fileUrl'].toString(),
        name: (json['name'] ?? '').toString(),
        mime: (json['mime'] ?? 'application/octet-stream').toString(),
        kind: (json['kind'] ?? 'file').toString(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        messageId: json['messageID']?.toString(),
      );
}

class UploadFailure implements Exception {
  const UploadFailure(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Each file's progress (0..1) while it uploads, by a key the caller chose -
/// a pending message's id - so its bubble can show it. Absent = not uploading.
class UploadProgress {
  UploadProgress._();

  static final Map<String, ValueNotifier<double?>> _byKey = {};

  static ValueListenable<double?> of(String key) =>
      _byKey.putIfAbsent(key, () => ValueNotifier<double?>(null));

  static void _set(String? key, double? fraction) {
    if (key == null) return;
    final notifier = _byKey.putIfAbsent(key, () => ValueNotifier<double?>(null));
    notifier.value = fraction;
    if (fraction == null) _byKey.remove(key);
  }
}

const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

/// The type to declare for [path] - from its extension; the server checks
/// the real bytes when the upload finishes.
@visibleForTesting
String mimeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return _mimeByExtension[ext] ?? 'application/octet-stream';
}

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

class MediaUploader {
  MediaUploader({Dio? api, Dio? storage})
      : _api = api ?? ApiClient.instance.dio,
        _storage = storage ?? Dio();

  final Dio _api;
  final Dio _storage;

  static const _partAttempts = 3;

  /// Uploads [paths] for [purpose] and resolves what was stored, in order.
  ///
  /// [context] says where they belong: {'conversationID': ...} for message
  /// files, {'realmID': ...} for a realm's avatar or cover. [progressKeys]
  /// (one per file, e.g. pending message ids) publish each file's progress
  /// through [UploadProgress]; [onProgress] gets the overall fraction.
  /// [types] overrides the declared type per file (otherwise from the
  /// extension).
  Future<List<UploadedFile>> upload({
    required UploadFeature purpose,
    required List<String> paths,
    Map<String, String>? context,
    List<String?> progressKeys = const [],
    List<String?> types = const [],
    void Function(double fraction)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final limit = UploadLimits.of(purpose);
    final sizes = <int>[];
    final mimes = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final size = await File(paths[i]).length();
      final mime = (i < types.length ? types[i] : null) ?? mimeForPath(paths[i]);
      if (size > limit.maxBytes) {
        throw UploadFailure('Files here can be at most ${limit.label}', 413);
      }
      if (!limit.allows(mime)) {
        throw const UploadFailure("This type of file can't be uploaded here", 415);
      }
      sizes.add(size);
      mimes.add(mime);
    }

    List<Map<String, dynamic>> asked;
    try {
      final response = await _api.post('/media/uploads', data: {
        'purpose': purpose.key,
        if (context != null) 'context': context,
        'files': [
          for (var i = 0; i < paths.length; i++)
            {'name': fileNameOf(paths[i]), 'size': sizes[i], 'type': mimes[i]},
        ],
      });
      asked = (response.data['uploads'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _failure(e, "Couldn't start the upload");
    }

    final total = sizes.fold<int>(0, (a, b) => a + b);
    final sent = List<int>.filled(paths.length, 0);
    void tick(int i, int loaded) {
      sent[i] = loaded.clamp(0, sizes[i]);
      UploadProgress._set(
        i < progressKeys.length ? progressKeys[i] : null,
        sizes[i] == 0 ? 1 : sent[i] / sizes[i],
      );
      if (total > 0) onProgress?.call(sent.fold<int>(0, (a, b) => a + b) / total);
    }

    try {
      final finished = await Future.wait([
        for (var i = 0; i < asked.length; i++)
          _sendFile(asked[i], paths[i], sizes[i], (n) => tick(i, n), cancelToken)
              .then((parts) => {
                    'uploadID': asked[i]['uploadID'],
                    if (parts != null) 'parts': parts,
                  }),
      ]);

      final List results;
      try {
        final response =
            await _api.post('/media/uploads/complete', data: {'uploads': finished});
        results = response.data['results'] as List;
      } on DioException catch (e) {
        throw _failure(e, "Couldn't finish the upload");
      }
      final failed = results.cast<Map>().where((r) => r['ok'] != true);
      if (failed.isNotEmpty) {
        throw UploadFailure(
          (failed.first['message'] ?? "Couldn't finish the upload").toString(),
          (failed.first['status'] as num?)?.toInt(),
        );
      }
      return [
        for (final r in results) UploadedFile.fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (_) {
      // Drop what never finished, so it doesn't wait for the cleanup job.
      for (final upload in asked) {
        unawaited(_api
            .delete('/media/uploads/${upload['uploadID']}')
            .then((_) {}, onError: (_) {}));
      }
      rethrow;
    } finally {
      for (final key in progressKeys) {
        UploadProgress._set(key, null);
      }
    }
  }

  UploadFailure _failure(DioException e, String fallback) {
    final data = e.response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : fallback;
    return UploadFailure(message, e.response?.statusCode);
  }

  /// One PUT of [length] bytes starting at [start]; resolves the ETag.
  Future<String> _put(
    Map target,
    String path,
    int start,
    int length,
    void Function(int loaded) onBytes,
    CancelToken? cancelToken,
  ) async {
    final headers = <String, dynamic>{
      ...Map<String, dynamic>.from(target['headers'] ?? const {}),
      Headers.contentLengthHeader: length,
    };
    try {
      final response = await _storage.request(
        target['url'] as String,
        data: File(path).openRead(start, start + length),
        options: Options(method: (target['method'] ?? 'PUT') as String, headers: headers),
        onSendProgress: (sent, _) => onBytes(sent),
        cancelToken: cancelToken,
      );
      return response.headers.value('etag') ?? '';
    } on DioException catch (e) {
      throw UploadFailure('Upload failed', e.response?.statusCode);
    }
  }

  /// Sends one file; resolves the parts' ETags for a multipart upload.
  Future<List<Map<String, dynamic>>?> _sendFile(
    Map<String, dynamic> asked,
    String path,
    int size,
    void Function(int loaded) onBytes,
    CancelToken? cancelToken,
  ) async {
    if (asked['mode'] != 'multipart') {
      await _put(asked, path, 0, size, onBytes, cancelToken);
      return null;
    }

    final partSize = (asked['partSize'] as num).toInt();
    final queue = [...(asked['parts'] as List).cast<Map>()];
    final loaded = <int, int>{};
    void report() => onBytes(loaded.values.fold(0, (a, b) => a + b));
    final etags = <Map<String, dynamic>>[];

    Future<void> sendPart(Map part) async {
      final n = (part['n'] as num).toInt();
      final length = (part['size'] as num).toInt();
      var target = part;
      for (var attempt = 1;; attempt++) {
        try {
          final etag = await _put(target, path, (n - 1) * partSize, length, (b) {
            loaded[n] = b;
            report();
          }, cancelToken);
          etags.add({'n': n, 'etag': etag});
          return;
        } on UploadFailure catch (e) {
          if (cancelToken?.isCancelled == true || attempt >= _partAttempts) rethrow;
          loaded[n] = 0;
          report();
          // A refused link has usually expired: ask for a fresh one.
          if (e.status == 403) {
            final fresh = await _api.post(
              '/media/uploads/${asked['uploadID']}/parts',
              data: {
                'parts': [n],
              },
            );
            final parts = fresh.data['parts'];
            if (parts is List && parts.isNotEmpty) target = parts.first as Map;
          }
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    // A few parts at a time; each worker takes the next part when it's done.
    final workers = UploadLimits.transfer.concurrency.clamp(1, queue.length);
    await Future.wait(List.generate(workers, (_) async {
      while (queue.isNotEmpty) {
        await sendPart(queue.removeAt(0));
      }
    }));
    return etags;
  }
}
