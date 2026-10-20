import 'package:flutter/foundation.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';

/// A visit owns all unlocked keys. No key or plaintext is persisted.
class DiarySession extends ChangeNotifier {
  static final instance = DiarySession();
  Map<String, dynamic>? data;
  String? identity;
  int generation = 0;
  final Map<String, List<int>> _keys = {};
  Map<String, dynamic>? get group => data == null
      ? null
      : Map<String, dynamic>.from((data!['purposes'] as List)
          .firstWhere((g) => g['purpose'] == 'diary') as Map);
  List<Map<String, dynamic>> get configurations =>
      (group?['configurations'] as List? ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
  Map<String, dynamic>? configuration(String id) =>
      configurations.where((c) => c['id'] == id).firstOrNull;
  Map<String, dynamic>? get active => configurations
      .where((c) => c['id'] == group?['active_configuration_id'])
      .firstOrNull;
  bool get canEncrypt =>
      ((data?['consumer_capabilities'] as Map?)?['diary']
          as Map?)?['format_version'] ==
      1;
  bool get ready =>
      data != null && (active == null || _keys.containsKey(active!['id']));
  void install(Map<String, dynamic> value, String owner) {
    data = value;
    identity = owner;
  }

  void addKey(String id, List<int> key) {
    _keys.remove(id)?.fillRange(0, 32, 0);
    _keys[id] = key;
  }

  void clear() {
    generation++;
    for (final key in _keys.values) {
      key.fillRange(0, key.length, 0);
    }
    _keys.clear();
    data = null;
    identity = null;
    notifyListeners();
  }

  Future<DiaryEntry> openEntry(DiaryEntry entry) async {
    if (!entry.isEncrypted) return entry;
    final ticket = generation;
    try {
      final envelope = PassphraseCrypto.envelope(entry.encryptedTitle!);
      final id = envelope['configuration_id'] as String;
      final c = configuration(id), key = _keys[id];
      if (c == null || key == null) return entry;
      final plain = await PassphraseCrypto().decryptDiary(
          key,
          c['entity_id'] as String,
          c['user_id'] as String,
          entry.encryptedTitle!,
          entry.encryptedContent!);
      if (ticket != generation) return entry;
      return entry.unlocked(plain.$1, plain.$2);
    } catch (_) {
      return entry;
    }
  }

  Future<(String, String)> encryptNew(String title, String content,
      {List<int>? confirmedKey}) async {
    final c = active;
    if (!ready || c == null || !canEncrypt) {
      throw const FormatException(
          'Diary protection requires a server update. Try again later.');
    }
    final key = confirmedKey ?? _keys[c['id']];
    if (key == null) {
      throw const FormatException('Unlock Diary again before saving.');
    }
    final ticket = generation;
    final fields = await PassphraseCrypto().encryptDiary(
        key,
        c['entity_id'] as String,
        c['user_id'] as String,
        c['id'] as String,
        title,
        content);
    if (ticket != generation) {
      throw const FormatException('Diary session ended.');
    }
    return fields;
  }
}
