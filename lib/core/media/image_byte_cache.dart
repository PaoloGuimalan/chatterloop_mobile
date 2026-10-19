import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One disk copy of the original bytes per URL, shared by display images and
/// notification icons. Decode sizes never become additional files or uploads.
class ImageByteCache {
  ImageByteCache({
    Future<Directory> Function()? directory,
    http.Client? client,
    this.maxBytes = 128 * 1024 * 1024,
    this.maxConcurrent = 4,
    this.maxAge = const Duration(days: 7),
    this.maxEntries = 512,
    this.requestTimeout = const Duration(seconds: 20),
  })  : assert(maxConcurrent > 0),
        _directory = directory ?? _defaultDirectory,
        _client = client ?? http.Client();

  static final instance = ImageByteCache();
  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/display_images_v1');

  final Future<Directory> Function() _directory;
  final http.Client _client;
  final int maxBytes;
  final int maxConcurrent;
  final Duration maxAge;
  final int maxEntries;
  final Duration requestTimeout;
  final _pending = <String, Future<Uint8List>>{};
  final _persisting = <String, Uint8List>{};
  final _aborts = <Completer<void>>{};
  final _entries = <String, ({int bytes, DateTime modified})>{};
  bool _indexed = false;
  int _queuedBytes = 0;
  final _waiting = <Completer<void>>[];
  int _active = 0;
  int _generation = 0;
  int get generation => _generation;
  Future<void> _writes = Future<void>.value();

  String _key(String url) => sha256.convert(utf8.encode(url)).toString();

  Future<Uint8List> bytes(String url) {
    final generation = _generation;
    final requestKey = '$generation:$url';
    final saving = _persisting[requestKey];
    if (saving != null) return Future.value(saving);
    return _pending.putIfAbsent(requestKey, () async {
      try {
        final cached = await _read(url);
        _checkGeneration(generation, url);
        if (cached != null) return cached;
        await _acquire();
        try {
          _checkGeneration(generation, url);
          final abort = Completer<void>();
          _aborts.add(abort);
          final timer = Timer(requestTimeout, () {
            if (!abort.isCompleted) abort.complete();
          });
          late http.Response response;
          try {
            final request = http.AbortableRequest('GET', Uri.parse(url),
                abortTrigger: abort.future);
            response =
                await http.Response.fromStream(await _client.send(request));
          } finally {
            timer.cancel();
            _aborts.remove(abort);
          }
          _checkGeneration(generation, url);
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            throw HttpException('Image request failed (${response.statusCode})',
                uri: Uri.tryParse(url));
          }
          final data = response.bodyBytes;
          final control =
              (response.headers['cache-control'] ?? '').toLowerCase();
          final seconds = int.tryParse(
              RegExp(r'max-age\s*=\s*"?(\d+)').firstMatch(control)?.group(1) ??
                  '');
          final lifetime = seconds == null
              ? maxAge
              : Duration(seconds: math.min(seconds, maxAge.inSeconds));
          if (!control.contains('no-store') &&
              !control.contains('no-cache') &&
              lifetime > Duration.zero &&
              data.length <= maxBytes &&
              _queuedBytes + data.length <= 32 * 1024 * 1024) {
            _queuedBytes += data.length;
            _persisting[requestKey] = data;
            // Decode immediately. Background writes are serialized and their
            // retained byte buffers have their own bound, independent of disk.
            _writes = _writes
                .then((_) => _store(url, data, generation, lifetime))
                .whenComplete(() {
              _persisting.remove(requestKey);
              _queuedBytes -= data.length;
            });
          }
          return data;
        } finally {
          _release();
        }
      } finally {
        _pending.remove(requestKey);
      }
    });
  }

  void _checkGeneration(int generation, String url) {
    if (generation != _generation) {
      throw http.RequestAbortedException(Uri.tryParse(url));
    }
  }

  /// Useful for shutdown/tests; image display never waits for persistence.
  Future<void> flush() => _writes;

  Future<Uint8List?> _read(String url) async {
    try {
      final file = File('${(await _directory()).path}/${_key(url)}.img');
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file &&
          stat.size > 0 &&
          DateTime.now().difference(stat.modified) < maxAge) {
        return await file.readAsBytes();
      }
      if (stat.type == FileSystemEntityType.file) await file.delete();
    } catch (_) {
      // Disk caching is optional, including when the OS clears its temp files.
    }
    return null;
  }

  Future<void> _store(
      String url, Uint8List data, int generation, Duration lifetime) async {
    if (data.length > maxBytes || generation != _generation) return;
    File? temp;
    try {
      final dir = await _directory();
      await dir.create(recursive: true);
      if (!_indexed) {
        await for (final entry in dir.list()) {
          if (entry is File && entry.path.endsWith('.img')) {
            final stat = await entry.stat();
            _entries[entry.path] = (bytes: stat.size, modified: stat.modified);
          }
        }
        _indexed = true;
      }
      final file = File('${dir.path}/${_key(url)}.img');
      temp = File('${file.path}.${math.Random().nextInt(1 << 32)}.tmp');
      await temp.writeAsBytes(data);
      if (generation != _generation) return;
      await temp.rename(file.path);
      final modified = DateTime.now().subtract(maxAge - lifetime);
      await file.setLastModified(modified);
      _entries[file.path] = (bytes: data.length, modified: modified);
      final entries = _entries.entries.toList()
        ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
      var total = entries.fold<int>(0, (sum, entry) => sum + entry.value.bytes);
      for (final entry in entries) {
        if (total <= maxBytes && _entries.length <= maxEntries) break;
        try {
          await File(entry.key).delete();
        } catch (_) {}
        total -= entry.value.bytes;
        _entries.remove(entry.key);
      }
    } catch (_) {
      // Still return the downloaded bytes if disk is full or unavailable.
    } finally {
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  Future<void> evict(String url) async {
    final generation = _generation;
    _writes = _writes.then((_) async {
      if (generation != _generation) return;
      try {
        final file = File('${(await _directory()).path}/${_key(url)}.img');
        _entries.remove(file.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    });
    await _writes;
  }

  /// Prevents an in-flight download from repopulating disk after logout.
  Future<void> clear() async {
    _generation++;
    for (final abort in _aborts) {
      if (!abort.isCompleted) abort.complete();
    }
    _writes = _writes.then((_) async {
      try {
        final dir = await _directory();
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
      _entries.clear();
      _indexed = false;
    });
    await _writes;
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}
