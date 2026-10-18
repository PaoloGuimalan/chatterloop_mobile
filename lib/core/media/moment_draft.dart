import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'composition.dart';

/// An editor snapshot. Media is made durable by [MomentDraftStore.save].
class MomentDraft {
  final Composition edit;
  final String caption;
  final String audience;
  final bool allowReplies;
  final Duration position;

  const MomentDraft({
    required this.edit,
    required this.caption,
    required this.audience,
    required this.allowReplies,
    required this.position,
  });
}

/// One account/entity's draft, outside the renderer's temporary directory.
///
/// Operations are serialized, including across store instances. Assets are kept
/// until discard: an autosave already queued may still refer to an older asset.
/// Saves never modify or remove the editor's original media files.
class MomentDraftStore {
  static final _queues = <String, Future<void>>{};
  static final _assetName = RegExp(r'^[a-f0-9]{64}\.[a-z0-9]{1,10}$');

  final String _ownerKey;
  final Future<Directory> Function() _directoryProvider;

  MomentDraftStore({
    required String ownerId,
    Future<Directory> Function()? directoryProvider,
  })  : _ownerKey = sha256.convert(utf8.encode(ownerId)).toString(),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory {
    if (ownerId.trim().isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result =
        (_queues[_ownerKey] ?? Future<void>.value()).then((_) => action());
    // A failed write must not poison later saves, loads, or discard.
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _queues[_ownerKey] = tail;
    tail.then((_) {
      if (identical(_queues[_ownerKey], tail)) _queues.remove(_ownerKey);
    });
    return result;
  }

  Future<Directory> _directory({bool create = false}) async {
    final support = await _directoryProvider();
    final namespace = Directory('${support.path}/moment_drafts');
    final owner = Directory('${namespace.path}/$_ownerKey');
    for (final directory in [namespace, owner]) {
      final type =
          await FileSystemEntity.type(directory.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException(
            'Draft directory is not a directory', directory.path);
      }
      if (create) await directory.create(recursive: true);
    }
    return owner;
  }

  Future<Directory> _assets(Directory owner, {bool create = false}) async {
    final directory = Directory('${owner.path}/assets');
    final type =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
          'Draft assets are not a directory', directory.path);
    }
    if (create) await directory.create();
    return directory;
  }

  Future<Map<String, dynamic>?> _readManifest(Directory owner) async {
    try {
      final manifest = File('${owner.path}/draft.json');
      if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final json = Map<String, dynamic>.from(
          jsonDecode(await manifest.readAsString()) as Map);
      if (json['v'] != 1 || json['owner'] != _ownerKey) return null;
      return json;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Returns null for absent, incomplete, corrupt, or unsupported drafts.
  Future<MomentDraft?> load() => _enqueue(() async {
        try {
          final owner = await _directory();
          final json = await _readManifest(owner);
          if (json == null) return null;
          final assets = await _assets(owner);
          final edit = Map<String, dynamic>.from(json['edit'] as Map);
          if ((edit['v'] as num).toInt() > Composition.currentVersion) {
            return null;
          }
          for (final field in _mediaFields(edit)) {
            final name = field['path'] as String;
            if (!_assetName.hasMatch(name)) return null;
            final file = File('${assets.path}/$name');
            if (!await _isFile(file)) return null;
            field['path'] = file.path;
          }
          final composition = Composition.fromJson(edit);
          final milliseconds = (json['position_ms'] as num).toInt();
          return MomentDraft(
            edit: composition,
            caption: json['caption'] as String,
            audience: json['audience'] as String,
            allowReplies: json['allow_replies'] as bool,
            position: Duration(
                milliseconds: milliseconds.clamp(
                    0, composition.naturalDuration.inMilliseconds)),
          );
        } on FileSystemException {
          return null;
        } on FormatException {
          return null;
        } on TypeError {
          return null;
        } on ArgumentError {
          return null;
        }
      });

  /// Commits the manifest only after all its assets have durable copies.
  /// Write failures are reported to the caller; the previous draft survives.
  Future<void> save(MomentDraft draft) {
    // Capture JSON before queueing so later editor list mutations cannot change
    // the snapshot that this operation was asked to save.
    final edit = draft.edit.toJson();
    return _enqueue(() async {
      final owner = await _directory(create: true);
      final assets = await _assets(owner, create: true);
      final previous = await _readManifest(owner);
      final sources = <String, dynamic>{};
      final oldSources = previous?['sources'];
      if (oldSources is Map) {
        for (final entry in oldSources.entries) {
          if (entry.key is String &&
              entry.value is Map &&
              entry.value['asset'] is String &&
              _assetName.hasMatch(entry.value['asset'] as String)) {
            sources[entry.key as String] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
      for (final field in _mediaFields(edit)) {
        field['path'] =
            await _copyAsset(field['path'] as String, assets, sources);
      }
      final pending = File('${owner.path}/draft.next');
      await pending.writeAsString(
          jsonEncode({
            'v': 1,
            'owner': _ownerKey,
            'edit': edit,
            'caption': draft.caption,
            'audience': draft.audience,
            'allow_replies': draft.allowReplies,
            'position_ms': draft.position.inMilliseconds,
            'sources': sources,
          }),
          flush: true);
      await pending.rename('${owner.path}/draft.json');
    });
  }

  Future<String> _copyAsset(
      String path, Directory assets, Map<String, dynamic> sources) async {
    final source = File(path);
    final basename = path.replaceAll('\\', '/').split('/').last;
    final owned = File('${assets.path}/$basename');
    if (_assetName.hasMatch(basename) &&
        source.absolute.uri == owned.absolute.uri &&
        await _isFile(owned)) {
      return basename;
    }

    final stat = await source.stat();
    final previous = sources[path];
    if (stat.type != FileSystemEntityType.file) {
      // The editor may still hold its original picker path after cache cleanup.
      if (previous is Map &&
          await _isFile(File('${assets.path}/${previous['asset']}'))) {
        return previous['asset'] as String;
      }
      throw FileSystemException('Draft media is missing', path);
    }
    final fingerprint = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    final extension = RegExp(r'\.([a-zA-Z0-9]{1,10})$')
            .firstMatch(path)
            ?.group(1)
            ?.toLowerCase() ??
        'bin';
    final name =
        '${sha256.convert(utf8.encode('$path:$fingerprint'))}.$extension';
    final destination = File('${assets.path}/$name');
    if (!await _isFile(destination)) {
      final pending = await source.copy('${destination.path}.part');
      final handle = await pending.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await pending.rename(destination.path);
    }
    sources[path] = {'asset': name, 'fingerprint': fingerprint};
    return name;
  }

  static Future<bool> _isFile(File file) async =>
      await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.file;

  // Only media-bearing fields are rewritten. Captions, text-card words, and
  // audio labels may themselves contain a path and must remain untouched.
  static Iterable<Map<String, dynamic>> _mediaFields(
      Map<String, dynamic> edit) sync* {
    for (final clip in edit['clips'] as List) {
      yield (clip as Map)['source'] as Map<String, dynamic>;
    }
    for (final overlay in edit['overlays'] as List) {
      final clip = (overlay as Map)['clip'] as Map;
      yield clip['source'] as Map<String, dynamic>;
    }
    for (final track in edit['audio'] as List) {
      yield track as Map<String, dynamic>;
    }
  }

  /// Runs after preceding autosaves and removes only this owner's storage.
  /// Callers should stop scheduling further autosaves when discarding.
  Future<void> discard() => _enqueue(() async {
        final owner = await _directory();
        if (await owner.exists()) await owner.delete(recursive: true);
      });
}
