import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chatterloop_app/models/notes_models/note.dart';

class NoteConflict implements Exception {}

/// One writer per editor. A response acknowledges only its captured snapshot;
/// text typed while it was in flight remains dirty and uses its new version.
class NoteAutosave extends ChangeNotifier {
  NoteAutosave(
      {required this.write, required this.isCurrentEntity, Note? initial})
      : saved = initial,
        draft =
            initial == null ? const NoteDraft() : NoteDraft.fromNote(initial) {
    _baseline = draft.fingerprint;
    status = initial == null ? 'Draft' : 'Saved';
  }
  final Future<Note> Function(NoteDraft draft, Note? previous) write;
  final bool Function() isCurrentEntity;
  Note? saved;
  NoteDraft draft;
  late String _baseline;
  late String status;
  bool conflict = false;
  Object? lastError;
  bool _disposed = false;
  bool _ready = false;
  Timer? _timer;
  Future<bool>? _flight;
  bool get dirty => draft.fingerprint != _baseline;

  void update(NoteDraft value) {
    draft = value;
    _timer?.cancel();
    _ready = false;
    if (conflict) {
      _notify();
      return;
    }
    status = dirty
        ? (draft.hasValue ? 'Unsaved changes' : 'Draft')
        : (saved == null ? 'Draft' : 'Saved');
    _notify();
    if (dirty && draft.hasValue) {
      _timer = Timer(const Duration(milliseconds: 2000), () {
        _ready = true;
        _scheduled();
      });
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    while (dirty && draft.hasValue && !conflict && !_disposed) {
      final flight = _flight;
      if (flight != null) {
        if (!await flight) return;
      } else {
        if (!await _writeOnce()) return;
      }
    }
  }

  Future<void> _scheduled() async {
    if (_flight != null) return;
    final success = await _writeOnce();
    if (success && _ready && dirty && !_disposed) await _scheduled();
  }

  Future<void> pause() async {
    _timer?.cancel();
    _ready = false;
    await _flight;
  }

  void recordConflict() {
    conflict = true;
    lastError = NoteConflict();
    status = 'Conflict. Your draft is retained';
    _timer?.cancel();
    _ready = false;
    _notify();
  }

  Future<bool> _writeOnce() async {
    if (!dirty || !draft.hasValue || conflict || _disposed) return false;
    if (!isCurrentEntity()) {
      status = 'Account changed. Draft retained';
      _notify();
      return false;
    }
    final snapshot = draft;
    status = 'Saving…';
    _ready = false;
    _notify();
    final completer = Completer<bool>();
    _flight = completer.future;
    var success = false;
    try {
      lastError = null;
      final result = await write(snapshot, saved);
      saved = result;
      final resolved = {
        for (final attachment in result.attachments) attachment.url: attachment
      };
      draft = NoteDraft(
          title: draft.title,
          content: draft.content,
          attachments:
              draft.attachments.map((a) => resolved[a.url] ?? a).toList());
      _baseline = snapshot.fingerprint;
      status = dirty ? 'Unsaved changes' : 'Saved';
      success = true;
    } catch (error) {
      lastError = error;
      conflict = error is NoteConflict;
      status = conflict
          ? 'Conflict. Your draft is retained'
          : "Couldn't save. Retry";
      _ready = false;
    } finally {
      _flight = null;
      completer.complete(success);
      _notify();
    }
    return success;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
