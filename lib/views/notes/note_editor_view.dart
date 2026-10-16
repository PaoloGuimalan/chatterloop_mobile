import 'dart:async';
import 'dart:convert';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/media_uploader.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/notes_api.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:chatterloop_app/models/notes_models/note.dart';
import 'package:chatterloop_app/views/notes/note_autosave.dart';
import 'package:chatterloop_app/views/notes/writing_widgets.dart';
import 'package:chatterloop_app/views/notes/writing_skeletons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:chatterloop_app/views/notes/note_html.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_attachment.dart';

class _RetainedDraft {
  const _RetainedDraft(this.draft, this.saved);
  final NoteDraft draft;
  final Note? saved;
}

// Failed drafts remain scoped to their original account/entity during navigation.
final _retained = <String, _RetainedDraft>{};

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.api});
  final String? noteId;
  final NotesApi? api;
  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _title = TextEditingController();
  final _focus = FocusNode();
  final FleatherController _editor = FleatherController();
  NotesApi? _api;
  NoteAutosave? _save;
  String? _key;
  String? _error;
  bool _restoring = false;
  bool _uploading = false;
  bool _leaving = false;
  bool _deleting = false;
  bool _allowPop = false;
  List<DiaryAttachment> _attachments = [];
  final List<({String document, String html})> _history = [];
  int _historyIndex = -1;
  String _lastDocument = '';
  String _lastHtml = '';
  StreamSubscription? _accountSubscription;
  StreamSubscription? _documentSubscription;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize({bool reload = false}) async {
    try {
      final api = widget.api ?? await NotesApi.open();
      final key = '${api.accountId}/${api.entityId}/${widget.noteId ?? 'new'}';
      final retained = reload ? null : _retained[key];
      final noteId = reload ? _save?.saved?.id : widget.noteId;
      final initial =
          retained?.saved ?? (noteId == null ? null : await api.get(noteId));
      if (!mounted || !api.isCurrent) return;
      if (reload) {
        _title.removeListener(_changed);
        _editor.removeListener(_changed);
        _documentSubscription?.cancel();
        _save?.removeListener(_savedChanged);
        _save?.dispose();
        _accountSubscription?.cancel();
        _history.clear();
        _retained.remove(key);
        _error = null;
      }
      _api = api;
      _key = key;
      final draft = retained?.draft ??
          (initial == null ? const NoteDraft() : NoteDraft.fromNote(initial));
      _replaceEditor(draft);
      _save = NoteAutosave(
          write: (snapshot, previous) async {
            final result = await api.save(snapshot, previous);
            final latest = _save?.draft ?? snapshot;
            if (latest.fingerprint == snapshot.fingerprint) {
              _retained.remove(key);
            } else {
              _retained[key] = _RetainedDraft(latest, result);
            }
            return result;
          },
          isCurrentEntity: () => api.isCurrent,
          initial: initial)
        ..addListener(_savedChanged);
      _accountSubscription = appStore.onChange.listen((_) {
        if (!mounted) return;
        _savedChanged();
        setState(() {});
      });
      // Preserve original HTML on opening; normalization only becomes a change
      // when the author actually types or formats something.
      _history.add((document: _lastDocument, html: _lastHtml));
      _historyIndex = 0;
      if (retained != null) _save!.update(draft);
      _title.addListener(_changed);
      _editor.addListener(_changed);
      // Checklist taps intentionally skip controller notifications. Observe
      // the document too so every actual edit reaches autosave and history.
      _documentSubscription = _editor.document.changes.listen((_) {
        if (mounted) _changed();
      });
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't open note. Go back and try again.");
      }
    }
  }

  void _replaceEditor(NoteDraft draft) {
    _restoring = true;
    _title.text = draft.title;
    final target = decodeNoteHtml(draft.content);
    _editor.compose(_editor.document.toDelta().diff(target.toDelta()),
        selection: const TextSelection.collapsed(offset: 0),
        source: ChangeSource.history);
    target.close();
    _attachments = List.of(draft.attachments);
    _lastDocument = jsonEncode(_editor.document.toJson());
    _lastHtml = draft.content;
    _restoring = false;
  }

  NoteDraft _snapshot() {
    final document = jsonEncode(_editor.document.toJson());
    if (document != _lastDocument) {
      _lastHtml = encodeNoteHtml(_editor.document);
      _lastDocument = document;
    }
    return NoteDraft(
        title: _title.text,
        content: _lastHtml,
        attachments: List.of(_attachments));
  }

  void _changed() {
    if (_restoring || _save == null) return;
    final draft = _snapshot();
    if (draft.fingerprint == _save!.draft.fingerprint) return;
    if (_historyIndex >= 0 &&
        _history[_historyIndex].document != _lastDocument) {
      _history.removeRange(_historyIndex + 1, _history.length);
      _history.add((document: _lastDocument, html: _lastHtml));
      _historyIndex++;
    }
    _save!.update(draft);
    setState(() {});
  }

  void _undo(int direction) {
    final index = _historyIndex + direction;
    if (index < 0 || index >= _history.length) return;
    FocusScope.of(context).unfocus();
    _historyIndex = index;
    final entry = _history[index];
    _restoring = true;
    final target =
        ParchmentDocument.fromJson(jsonDecode(entry.document) as List);
    var offset = 0, formatCaret = 0;
    int? textCaret;
    final change = _editor.document.toDelta().diff(target.toDelta());
    for (final operation in change.toList()) {
      if (operation.isRetain) {
        offset += operation.length;
        if (operation.attributes?.isNotEmpty ?? false) formatCaret = offset;
      }
      if (operation.isInsert) {
        offset += operation.length;
        textCaret = offset;
      }
      if (operation.isDelete) textCaret = offset;
    }
    // Keep Fleather's live document, render tree, and keyboard connection in
    // sync. Disposing/replacing its controller leaves focused child state
    // holding the previous document during undo/redo.
    _editor.compose(change,
        source: ChangeSource.history,
        selection: TextSelection.collapsed(
            offset: (textCaret ?? formatCaret).clamp(0, target.length - 1)));
    target.close();
    _lastDocument = entry.document;
    _lastHtml = entry.html;
    _restoring = false;
    _save!.update(_snapshot());
    setState(() {});
  }

  void _savedChanged() {
    final save = _save;
    if (save == null || _key == null) return;
    _attachments = List.of(save.draft.attachments);
    if (save.dirty) {
      _retained[_key!] = _RetainedDraft(save.draft, save.saved);
    } else {
      _retained.remove(_key);
    }
    if (mounted) setState(() {});
  }

  Future<void> _attach() async {
    final api = _api!;
    if (!api.isCurrent) return;
    final chosen = await FilePicker.pickFiles(allowMultiple: true);
    if (chosen == null || !mounted || !api.isCurrent) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final files =
          await MediaUploader(api: ApiClient.instance.forToken(api.token))
              .upload(
                  purpose: UploadFeature.notes,
                  paths: chosen.files
                      .where((f) => f.path != null)
                      .map((f) => f.path!)
                      .toList());
      if (!mounted) return;
      _attachments.addAll(files.map((f) => DiaryAttachment(
          url: f.fileUrl,
          fileId: f.uploadId,
          fileName: f.name,
          fileType: f.mime)));
      _changed();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is UploadFailure
            ? error.message
            : "Couldn't upload. Try again.");
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving || _uploading || _deleting) return;
    _leaving = true;
    final save = _save;
    if (save != null) {
      await save.flush();
      // A writer already in flight may have acknowledged an older snapshot.
      if (save.dirty && !save.conflict && save.status == 'Unsaved changes') {
        await save.flush();
      }
      if (!mounted) return;
      if (save.dirty) {
        final leave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Keep this draft?'),
                    content: const Text(
                        'Your changes have not been saved. Keep the draft here to return to it later.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Stay')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Keep draft and leave'))
                    ]));
        if (leave != true) {
          _leaving = false;
          return;
        }
      }
    }
    if (mounted) {
      setState(() => _allowPop = true);
      context.pop(true);
    }
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _documentSubscription?.cancel();
    _title.dispose();
    _editor.dispose();
    _focus.dispose();
    _save?.removeListener(_savedChanged);
    _save?.dispose();
    super.dispose();
  }

  Future<void> _copyEdits() async {
    final draft = _save!.draft;
    await Clipboard.setData(ClipboardData(
        text: [
      draft.title,
      notePlainText(draft.content),
      ...draft.attachments.map((a) => '${a.fileName ?? 'Attachment'}: ${a.url}')
    ].where((part) => part.isNotEmpty).join('\n\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Edits copied')));
    }
  }

  Future<void> _reloadLatest() async {
    final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Reload latest note?'),
                content: const Text(
                    'This replaces the draft with the latest saved note. Copy your edits first if you want to keep them.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reload latest'))
                ]));
    if (discard == true && mounted) await _initialize(reload: true);
  }

  Future<void> _delete() async {
    if (_deleting || _uploading) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete note?'),
                content: const Text(
                    'The saved note and any unsaved changes will be deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final save = _save!;
    await save.pause();
    try {
      await _api!.delete(save.saved!);
      _retained.remove(_key);
      if (mounted) {
        setState(() => _allowPop = true);
        context.pop(true);
      }
    } catch (error) {
      if (error is NoteConflict) save.recordConflict();
      if (mounted) {
        setState(() => _error = error is NoteConflict
            ? 'The note changed elsewhere. Copy your edits or reload the latest note.'
            : "Couldn't delete the note. Your draft is retained. Try again from More options.");
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final save = _save;
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: CLScreen(
            backgroundColor: p.surface,
            appBar: AppBar(
                centerTitle: false,
                leadingWidth: 48,
                titleSpacing: 4,
                backgroundColor: p.surface,
                leading: IconButton(
                    tooltip: 'Back to notes',
                    onPressed: _leave,
                    icon: const Icon(Icons.arrow_back)),
                title: const Text('Notes',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                actions: [
                  if (save != null)
                    Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Center(
                            child: save.status == "Couldn't save. Retry"
                                ? TextButton(
                                    onPressed: () => save.flush(),
                                    child: Text(save.status,
                                        style: TextStyle(
                                            fontSize: 11, color: p.text3)))
                                : Text(save.status,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: save.status == 'Saved'
                                            ? Colors.green
                                            : p.text3)))),
                  if (save != null)
                    PopupMenuButton<String>(
                        tooltip: 'More options',
                        enabled: !_deleting && !_uploading,
                        onSelected: (action) {
                          if (action == 'save') {
                            FocusManager.instance.primaryFocus?.unfocus();
                            _changed();
                            save.flush();
                          } else if (action == 'copy') {
                            _copyEdits();
                          } else if (action == 'reload') {
                            _reloadLatest();
                          } else if (action == 'delete') {
                            _delete();
                          }
                        },
                        itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'save',
                                  enabled: save.draft.hasValue &&
                                      save.dirty &&
                                      !save.conflict,
                                  child: const Text('Save')),
                              const PopupMenuItem(
                                  value: 'copy', child: Text('Copy edits')),
                              if (save.saved != null)
                                const PopupMenuItem(
                                    value: 'reload',
                                    child: Text('Reload latest')),
                              if (save.saved != null)
                                const PopupMenuItem(
                                    value: 'delete', child: Text('Delete note'))
                            ]),
                ]),
            body: _deleting
                ? const Center(child: CircularProgressIndicator())
                : save == null
                    ? _error == null
                        ? const WritingDocumentSkeleton(
                            editor: true,
                            key: ValueKey('writing-editor-skeleton'))
                        : Center(child: Text(_error!))
                    : !_api!.isCurrent
                        ? const Center(
                            child: Text(
                                'Account changed.\nYour draft is retained for the original account.',
                                textAlign: TextAlign.center))
                        : Column(children: [
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(_error!,
                                      style: TextStyle(color: p.text2))),
                            if (!_api!.isCurrent)
                              Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                      'Account changed. This draft belongs to your previous account.',
                                      style: TextStyle(color: p.text2))),
                            Expanded(
                                child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                        19, 18, 19, 24),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          TextField(
                                              controller: _title,
                                              maxLines: null,
                                              style: TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w600,
                                                  color: p.text),
                                              decoration:
                                                  writingInput('Untitled note')
                                                      .copyWith(
                                                          contentPadding:
                                                              EdgeInsets.zero)),
                                          const SizedBox(height: 16),
                                          Row(children: [
                                            Icon(Icons.lock_outline,
                                                size: 13, color: p.text3),
                                            const SizedBox(width: 5),
                                            Text('Private notebook',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: p.text3))
                                          ]),
                                          const SizedBox(height: 24),
                                          ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  minHeight: 285),
                                              child: FleatherEditor(
                                                  controller: _editor,
                                                  focusNode: _focus,
                                                  padding: EdgeInsets.zero,
                                                  expands: false)),
                                          const SizedBox(height: 16),
                                          for (final attachment in _attachments)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 14),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Row(children: [
                                                      Expanded(
                                                          child: Text(
                                                              attachment
                                                                      .fileName ??
                                                                  'Attachment',
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: p
                                                                      .text2))),
                                                      IconButton(
                                                          tooltip:
                                                              'Remove attachment',
                                                          icon: const Icon(
                                                              Icons.close,
                                                              size: 18),
                                                          onPressed: () {
                                                            _attachments.remove(
                                                                attachment);
                                                            _changed();
                                                          }),
                                                    ]),
                                                    WritingAttachment(
                                                        attachment: attachment),
                                                  ]),
                                            ),
                                        ]))),
                            SafeArea(
                                top: false,
                                child: Container(
                                    decoration: BoxDecoration(
                                        border: Border(
                                            top: BorderSide(color: p.border))),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(children: [
                                            IconButton(
                                                tooltip: 'Undo',
                                                onPressed: _historyIndex > 0
                                                    ? () => _undo(-1)
                                                    : null,
                                                icon: const Icon(Icons.undo,
                                                    size: 20)),
                                            IconButton(
                                                tooltip: 'Redo',
                                                onPressed: _historyIndex <
                                                        _history.length - 1
                                                    ? () => _undo(1)
                                                    : null,
                                                icon: const Icon(Icons.redo,
                                                    size: 20)),
                                            const Spacer(),
                                            IconButton(
                                                tooltip: 'Attach file',
                                                onPressed:
                                                    _uploading ? null : _attach,
                                                icon: _uploading
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2))
                                                    : const Icon(
                                                        Icons.attach_file,
                                                        size: 20))
                                          ]),
                                          FleatherToolbar.basic(
                                              controller: _editor,
                                              hideBackgroundColor: true,
                                              hideForegroundColor: true,
                                              hideInlineCode: true,
                                              hideCodeBlock: true,
                                              hideDirection: true,
                                              hideUndoRedo: true,
                                              hideAlignment: true),
                                        ]))),
                          ])));
  }
}
