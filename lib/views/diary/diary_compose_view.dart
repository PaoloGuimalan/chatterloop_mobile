// New diary entry - mirrors webapp's app/tabs/profile/diary/NewEntry.tsx.
//
// Content is authored in Quill and converted to HTML before sending, because
// that is what the server stores and what webapp renders. The conversion is
// deliberately ONE-WAY: there is no edit endpoint anywhere (diary/urls.py maps
// only GET and POST), so HTML never has to be parsed back into a Delta. That
// avoids the lossy round-trip that normally makes Quill-plus-HTML painful.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'dart:convert';
import 'dart:async';
import 'package:chatterloop_app/core/utils/writing_html.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_body.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/media/media_uploader.dart';
import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:chatterloop_app/views/diary/widgets/mood_picker_sheet.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A file chosen but not yet uploaded.
class _PendingAttachment {
  _PendingAttachment(
      {required this.path, required this.name, required this.size});
  final String path;
  final String name;
  final int size;
}

class DiaryComposeScreen extends StatefulWidget {
  const DiaryComposeScreen({super.key});

  @override
  State<DiaryComposeScreen> createState() => _DiaryComposeScreenState();
}

class _DiaryComposeScreenState extends State<DiaryComposeScreen> {
  FleatherController _editor = FleatherController();
  final FocusNode _editorFocus = FocusNode();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _tagInput = TextEditingController();

  DateTime _entryDate = DateTime.now();
  bool _isPrivate = true;
  bool _isSaving = false;

  Mood? _selectedMood;

  final List<DiaryTag> _selectedTags = [];
  List<DiaryTag> _tagSuggestions = [];
  bool _isSearchingTags = false;

  /// Server's verdict that the typed text matches no existing interest. Drives
  /// the "Add Tag" row, mirroring webapp's CustomTagItem.
  bool _typedTagIsNew = false;

  final List<_PendingAttachment> _attachments = [];

  late final String _accountKey;
  late final Future<String?> _token;
  final List<Map<String, dynamic>> _history = [];
  int _historyIndex = 0;
  bool _restoring = false;
  bool _allowPop = false;
  bool _confirming = false;
  StreamSubscription? _documentSubscription;
  void _observeEditor() {
    _editor.addListener(_record);
    // Fleather checkbox taps deliberately use notify:false on the controller.
    _documentSubscription = _editor.document.changes.listen((_) {
      if (mounted) _record();
    });
  }

  String get _currentAccount =>
      '${appStore.state.userAuth.user.id}/${appStore.state.userAuth.user.entityId}';
  Map<String, dynamic> _snapshot() => {
        'title': _title.text,
        'html': _contentAsHtml(),
        'document': jsonDecode(jsonEncode(_editor.document.toJson())),
        'date': _entryDateForApi(),
        'private': _isPrivate,
        'mood': _selectedMood,
        'tags': List<DiaryTag>.of(_selectedTags),
        'files': List<_PendingAttachment>.of(_attachments),
      };
  String _fingerprint(Map<String, dynamic> d) => jsonEncode({
        'title': d['title'],
        'document': d['document'],
        'date': d['date'],
        'private': d['private'],
        'mood': (d['mood'] as Mood?)?.id,
        'tags': (d['tags'] as List<DiaryTag>).map((t) => t.name).toList(),
        'files': (d['files'] as List<_PendingAttachment>)
            .map((f) => f.path)
            .toList(),
      });
  bool get _dirty => _fingerprint(_snapshot()) != _fingerprint(_history.first);
  void _record() {
    if (_restoring || _history.isEmpty) return;
    final value = _snapshot();
    if (jsonEncode(value['document']) !=
        jsonEncode(_history[_historyIndex]['document'])) {
      _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(value);
      _historyIndex++;
    }
    if (mounted) setState(() {});
  }

  void _undo(int direction) {
    final index = _historyIndex + direction;
    if (index < 0 || index >= _history.length) return;
    FocusScope.of(context).unfocus();
    _restoring = true;
    final value = _history[index];
    final old = _editor;
    old.removeListener(_record);
    _documentSubscription?.cancel();
    _editor = FleatherController(
        document: ParchmentDocument.fromJson(value['document'] as List));
    old.dispose();
    _observeEditor();
    _historyIndex = index;
    _restoring = false;
    setState(() {});
  }

  Future<void> _leave() async {
    if (_isSaving || _confirming) return;
    if (_dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Discard entry?'),
                  content: const Text('Your unsaved changes will be lost.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep writing')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Discard'))
                  ]));
      _confirming = false;
      if (discard != true) return;
    }
    if (mounted) {
      setState(() => _allowPop = true);
      context.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _accountKey = _currentAccount;
    _token = ApiClient.userService.readToken();
    _history.add(_snapshot());
    _title.addListener(_record);
    _observeEditor();
  }

  /// Moods are paged in by the picker itself, so nothing is fetched until it's
  /// opened - the compose screen doesn't pay for a list the user may never
  /// look at.
  Future<void> _pickMood() async {
    final choice = await showMoodPickerSheet(context, selected: _selectedMood);
    if (choice == null || !mounted) return;
    setState(() => _selectedMood = choice.mood);
    _record();
  }

  @override
  void dispose() {
    _documentSubscription?.cancel();
    _editor.dispose();
    _editorFocus.dispose();
    _title.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _searchTags(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _tagSuggestions = [];
        _typedTagIsNew = false;
      });
      return;
    }
    setState(() => _isSearchingTags = true);
    final result = await DiaryApi().searchTags(search: trimmed);
    if (!mounted) return;

    // The response can land after the field has moved on; ignore a result
    // that no longer describes what's typed rather than showing stale matches.
    if (_tagInput.text.trim() != trimmed) return;

    setState(() {
      _isSearchingTags = false;
      // Hide anything already chosen so the list only offers new options.
      final chosen = _selectedTags.map((t) => t.name.toLowerCase()).toSet();
      _tagSuggestions = result.tags
          .where((t) => !chosen.contains(t.name.toLowerCase()))
          .toList();
      // Don't offer to create a tag that's already selected.
      _typedTagIsNew = result.isNew && !chosen.contains(trimmed.toLowerCase());
    });
  }

  void _addTag(DiaryTag tag) {
    if (_selectedTags
        .any((t) => t.name.toLowerCase() == tag.name.toLowerCase())) {
      return;
    }
    setState(() {
      _selectedTags.add(tag);
      _tagInput.clear();
      _tagSuggestions = [];
      _typedTagIsNew = false;
    });
    _record();
  }

  /// A tag the user typed that isn't in the suggestions. Sent with a null id -
  /// the server resolves by name through get_or_create_by_name, so a brand-new
  /// tag needs no special handling on this side.
  void _addTypedTag() {
    final name = _tagInput.text.trim();
    if (name.isEmpty) return;
    _addTag(DiaryTag(id: null, name: name));
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || !mounted) return;

    final rejected = <String>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (file.size > UploadLimits.of(UploadFeature.diary).maxBytes) {
        rejected.add(file.name);
        continue;
      }
      _attachments.add(
          _PendingAttachment(path: path, name: file.name, size: file.size));
    }

    _record();
    if (rejected.isNotEmpty && mounted) {
      _toast(
          "Skipped ${rejected.length} file(s) over ${UploadLimits.of(UploadFeature.diary).label}",
          type: CLAlertType.warning);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _entryDate = picked);
      _record();
    }
  }

  void _toast(String message, {CLAlertType type = CLAlertType.error}) {
    CLAlerts.show(message, type: type);
  }

  /// Parchment document -> HTML, the format the server stores and webapp
  /// renders through dangerouslySetInnerHTML.
  String _contentAsHtml() => encodeWritingHtml(_editor.document);

  /// The server splits entry_date on a space and parses with "%Y-%m-%d", so a
  /// full ISO-8601 string with a "T" separator would throw. Send the date part
  /// only.
  String _entryDateForApi() {
    final m = _entryDate.month.toString().padLeft(2, '0');
    final d = _entryDate.day.toString().padLeft(2, '0');
    return "${_entryDate.year}-$m-$d";
  }

  Future<void> _save() async {
    final session = DiarySession.instance;
    final visit = session.generation;
    if (_currentAccount != _accountKey) {
      _toast(
          'Account changed. Return to the original account to save this entry.');
      return;
    }
    final token = await _token;
    if (token == null || _currentAccount != _accountKey || !mounted) return;
    final title = _title.text.trim();
    final plain = _editor.document.toPlainText().trim();

    // The server 422s when either is blank, so catch it here with a message
    // that says which one rather than surfacing a raw failure.
    if (title.isEmpty) {
      _toast("Add a title first", type: CLAlertType.warning);
      return;
    }
    if (plain.isEmpty) {
      _toast("Write something first", type: CLAlertType.warning);
      return;
    }

    setState(() => _isSaving = true);
    String wireTitle = title, wireContent = _contentAsHtml();
    final encrypted = session.active != null;
    if (encrypted) {
      try {
        final fields = await session.encryptNew(title, wireContent);
        wireTitle = fields.$1;
        wireContent = fields.$2;
      } catch (_) {
        if (mounted) {
          setState(() => _isSaving = false);
          _toast(
              'Diary protection requires an updated server and an unlocked visit. Reopen Diary and try again.');
        }
        return;
      }
    }
    if (!mounted || visit != session.generation) return;

    // Attachments upload first: the entry POST takes their resulting URLs, so
    // a failure here has to abort before anything is created.
    final uploaded = <DiaryAttachment>[];
    for (final pending in _attachments) {
      try {
        final files =
            await MediaUploader(api: ApiClient.instance.forToken(token))
                .upload(purpose: UploadFeature.diary, paths: [pending.path]);
        final result = files.single;
        uploaded.add(DiaryAttachment(
            url: result.fileUrl,
            fileId: result.uploadId,
            fileName: result.name,
            fileType: result.mime));
      } catch (_) {
        if (mounted) {
          setState(() => _isSaving = false);
          _toast("Couldn't upload the attachment. Try again.");
        }
        return;
      }
    }
    if (!mounted ||
        visit != session.generation ||
        _currentAccount != _accountKey) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    final entry =
        await DiaryApi(dio: ApiClient.userService.forToken(token)).createEntry(
      title: wireTitle,
      content: wireContent,
      entryDate: _entryDateForApi(),
      isPrivate: encrypted || _isPrivate,
      isEncrypted: encrypted,
      mood: _selectedMood,
      tags: _selectedTags,
      attachments: uploaded,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (entry == null) {
      _toast("Couldn't save the entry. Try again.");
      return;
    }
    // The list screen reloads from the top when it sees this.
    setState(() => _allowPop = true);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final theme = Theme.of(context);
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Theme(
            data: theme.copyWith(
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: p.border),
                        borderRadius: BorderRadius.circular(9)),
                    focusColor: Colors.transparent)),
            child: CLScreen(
              backgroundColor: p.surface,
              appBar: AppBar(
                  centerTitle: false,
                  leadingWidth: 48,
                  titleSpacing: 4,
                  backgroundColor: p.surface,
                  leading: IconButton(
                      tooltip: 'Back to diary',
                      onPressed: _leave,
                      icon: const Icon(Icons.arrow_back)),
                  title: const Text('New entry',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  actions: [
                    TextButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text('Save',
                                style: TextStyle(
                                    color: p.brand,
                                    fontWeight: FontWeight.w600)))
                  ]),
              body: AbsorbPointer(
                  absorbing: _isSaving,
                  child: Column(children: [
                    Expanded(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(19, 16, 19, 24),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: Text(
                                          DiarySession.instance.active != null
                                              ? 'Titles and text are encrypted and private. Attachments, tags, moods and dates are outside this protection.'
                                              : 'No active passphrase. This entry will be saved without passphrase encryption.',
                                          style: TextStyle(
                                              color: p.text2,
                                              fontSize: CLType.caption))),
                                  _titleAndDate(p),
                                  const SizedBox(height: 16),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: _moodPicker(p)),
                                        const SizedBox(width: 9),
                                        Expanded(child: _privacyToggle(p))
                                      ]),
                                  const SizedBox(height: 12),
                                  _tagPicker(p),
                                  const SizedBox(height: 22),
                                  _editorCard(p),
                                  const SizedBox(height: 18),
                                  _attachmentPicker(p),
                                ]))),
                    SafeArea(
                        top: false,
                        child: Container(
                            decoration: BoxDecoration(
                                border:
                                    Border(top: BorderSide(color: p.border))),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(children: [
                                    IconButton(
                                        tooltip: 'Undo',
                                        onPressed: _historyIndex > 0
                                            ? () => _undo(-1)
                                            : null,
                                        icon: const Icon(Icons.undo, size: 20)),
                                    IconButton(
                                        tooltip: 'Redo',
                                        onPressed:
                                            _historyIndex + 1 < _history.length
                                                ? () => _undo(1)
                                                : null,
                                        icon: const Icon(Icons.redo, size: 20)),
                                    const Spacer(),
                                    IconButton(
                                        tooltip: 'Attach file',
                                        onPressed: _pickAttachments,
                                        icon: const Icon(Icons.attach_file,
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
                  ])),
            )));
  }

  Widget _titleAndDate(CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            TextField(
              controller: _title,
              style: TextStyle(
                  color: p.text,
                  fontSize: CLType.screenTitle,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: "Title",
                hintStyle: TextStyle(color: p.text3),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _pickDate,
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: p.text3),
                  const SizedBox(width: 6),
                  Text(_entryDateForApi(),
                      style:
                          TextStyle(color: p.text2, fontSize: CLType.bodySm)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: p.text3),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _editorCard(CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 285),
              child: FleatherTheme(
                data: writingEditorTheme(context),
                child: FleatherEditor(
                  controller: _editor,
                  focusNode: _editorFocus,
                  expands: false,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
          ],
        ),
      );

  /// A full-width field that opens the paginated picker, matching webapp's
  /// "Select Mood" async select rather than rendering every mood inline.
  Widget _moodPicker(CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: double.infinity),
            Text("Mood",
                style: TextStyle(
                    color: p.text2,
                    fontSize: CLType.caption,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(CLRadii.sm),
              onTap: _pickMood,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: p.surface2,
                  border: Border.all(color: p.border2),
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                ),
                child: Row(
                  children: [
                    if (_selectedMood != null) ...[
                      Text(_selectedMood!.emoji,
                          // Emoji glyph sized to its container - not a CLType step.
                          style: const TextStyle(fontSize: 17)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _selectedMood?.name ?? "Select Mood",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedMood == null ? p.text3 : p.text,
                          fontSize: CLType.title,
                          fontWeight: _selectedMood == null
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 20, color: p.text3),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tagPicker(CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Forces the card to fill its parent rather than shrinking to fit
            // a single chip.
            const SizedBox(width: double.infinity),
            Text("Tags",
                style: TextStyle(
                    color: p.text2,
                    fontSize: CLType.caption,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_selectedTags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedTags
                    .map((t) => CLChip(
                          label: t.name,
                          icon: Icons.close,
                          active: true,
                          onTap: () {
                            setState(() => _selectedTags.remove(t));
                            _record();
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _tagInput,
              onChanged: _searchTags,
              onSubmitted: (_) => _addTypedTag(),
              textInputAction: TextInputAction.done,
              style: TextStyle(color: p.text, fontSize: CLType.title),
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.border),
                    borderRadius: BorderRadius.circular(9)),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.border),
                    borderRadius: BorderRadius.circular(9)),
                hintText: "Search or create a tag",
                hintStyle: TextStyle(color: p.text3, fontSize: CLType.bodySm),
                isDense: true,
                suffixIcon: _isSearchingTags
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.add, size: 20, color: p.brand),
                        onPressed: _addTypedTag,
                      ),
              ),
            ),
            // Mirrors webapp's tagsLoadOptions: the "create" option is
            // prepended above the matches, so a unique name is offered first
            // rather than buried under near-misses.
            if (_typedTagIsNew) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(CLRadii.sm),
                onTap: _addTypedTag,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.brandSoft,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: p.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tagInput.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.text,
                              fontSize: CLType.bodySm,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text("Add Tag",
                          style: TextStyle(
                              color: p.brand, fontSize: CLType.caption)),
                    ],
                  ),
                ),
              ),
            ],
            if (_tagSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tagSuggestions
                    .take(8)
                    .map((t) => CLChip(label: t.name, onTap: () => _addTag(t)))
                    .toList(),
              ),
            ],
            if (!_isSearchingTags &&
                _tagInput.text.trim().isNotEmpty &&
                !_typedTagIsNew &&
                _tagSuggestions.isEmpty) ...[
              const SizedBox(height: 8),
              Text("Already added",
                  style: TextStyle(color: p.text3, fontSize: CLType.caption)),
            ],
          ],
        ),
      );

  Widget _attachmentPicker(CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Attachments",
                      style: TextStyle(
                          color: p.text2,
                          fontSize: CLType.caption,
                          fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _pickAttachments,
                  icon: Icon(Icons.attach_file, size: 17, color: p.brand),
                  label: Text("Add",
                      style:
                          TextStyle(color: p.brand, fontSize: CLType.bodySm)),
                ),
              ],
            ),
            if (_attachments.isEmpty)
              Text(
                  "Up to ${UploadLimits.of(UploadFeature.diary).label} per file",
                  style: TextStyle(color: p.text3, fontSize: CLType.caption))
            else
              ..._attachments.map((a) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file_outlined,
                            size: 17, color: p.text2),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.text, fontSize: CLType.bodySm)),
                        ),
                        Text(_readableSize(a.size),
                            style: TextStyle(
                                color: p.text3, fontSize: CLType.caption)),
                        IconButton(
                          icon: Icon(Icons.close, size: 17, color: p.text3),
                          onPressed: () => setState(() {
                            _attachments.remove(a);
                            _record();
                          }),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      );

  Widget _privacyToggle(CLPalette p) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Privacy', style: TextStyle(fontSize: 11, color: p.text2)),
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: p.surface2,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(9)),
            child: DropdownButtonHideUnderline(
                child: DropdownButton<bool>(
              value: DiarySession.instance.active != null || _isPrivate,
              isExpanded: true,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12, color: p.text),
              items: const [
                DropdownMenuItem(value: true, child: Text('Private')),
                DropdownMenuItem(value: false, child: Text('Public'))
              ],
              onChanged: DiarySession.instance.active != null
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _isPrivate = value);
                        _record();
                      }
                    },
            ))),
      ]);

  String _readableSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(0)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}
