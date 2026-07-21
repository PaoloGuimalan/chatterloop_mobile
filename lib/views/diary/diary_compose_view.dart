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
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:parchment/codecs.dart';

/// A file chosen but not yet uploaded.
class _PendingAttachment {
  _PendingAttachment({required this.path, required this.name, required this.size});
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
  /// Matches NewEntry.tsx's "Cannot upload files greater than 25mb".
  static const int _maxFileBytes = 25 * 1024 * 1024;

  final FleatherController _editor = FleatherController();
  final FocusNode _editorFocus = FocusNode();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _tagInput = TextEditingController();

  DateTime _entryDate = DateTime.now();
  bool _isPrivate = true;
  bool _isSaving = false;

  List<Mood> _moods = [];
  Mood? _selectedMood;

  final List<DiaryTag> _selectedTags = [];
  List<DiaryTag> _tagSuggestions = [];
  bool _isSearchingTags = false;

  /// Server's verdict that the typed text matches no existing interest. Drives
  /// the "Add Tag" row, mirroring webapp's CustomTagItem.
  bool _typedTagIsNew = false;

  final List<_PendingAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _loadMoods();
  }

  @override
  void dispose() {
    _editor.dispose();
    _editorFocus.dispose();
    _title.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _loadMoods() async {
    final moods = await DiaryApi().getMoods();
    if (!mounted) return;
    setState(() => _moods = moods);
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
      _typedTagIsNew =
          result.isNew && !chosen.contains(trimmed.toLowerCase());
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || !mounted) return;

    final rejected = <String>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (file.size > _maxFileBytes) {
        rejected.add(file.name);
        continue;
      }
      _attachments.add(
          _PendingAttachment(path: path, name: file.name, size: file.size));
    }

    setState(() {});
    if (rejected.isNotEmpty && mounted) {
      _toast("Skipped ${rejected.length} file(s) over 25MB");
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _entryDate = picked);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Parchment document -> HTML, the format the server stores and webapp
  /// renders through dangerouslySetInnerHTML.
  String _contentAsHtml() => parchmentHtml.encode(_editor.document);

  /// The server splits entry_date on a space and parses with "%Y-%m-%d", so a
  /// full ISO-8601 string with a "T" separator would throw. Send the date part
  /// only.
  String _entryDateForApi() {
    final m = _entryDate.month.toString().padLeft(2, '0');
    final d = _entryDate.day.toString().padLeft(2, '0');
    return "${_entryDate.year}-$m-$d";
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final plain = _editor.document.toPlainText().trim();

    // The server 422s when either is blank, so catch it here with a message
    // that says which one rather than surfacing a raw failure.
    if (title.isEmpty) {
      _toast("Add a title first");
      return;
    }
    if (plain.isEmpty) {
      _toast("Write something first");
      return;
    }

    setState(() => _isSaving = true);

    // Attachments upload first: the entry POST takes their resulting URLs, so
    // a failure here has to abort before anything is created.
    final uploaded = <DiaryAttachment>[];
    for (final pending in _attachments) {
      final result = await ProfileApi()
          .uploadMediaRequest(pending.path, _mediaTypeFor(pending.name));
      if (result == null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        _toast("Couldn't upload ${pending.name}");
        return;
      }
      uploaded.add(DiaryAttachment(
        url: result.url,
        fileId: result.fileId,
        fileName: result.fileName,
        fileType: result.mediaType,
      ));
    }

    final entry = await DiaryApi().createEntry(
      title: title,
      content: _contentAsHtml(),
      entryDate: _entryDateForApi(),
      isPrivate: _isPrivate,
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
    context.pop(true);
  }

  String _mediaTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (RegExp(r'\.(jpe?g|png|gif|webp|heic)$').hasMatch(lower)) return 'image';
    if (RegExp(r'\.(mp4|mov|avi|mkv|webm)$').hasMatch(lower)) return 'video';
    if (RegExp(r'\.(mp3|wav|m4a|aac|ogg)$').hasMatch(lower)) return 'audio';
    return 'file';
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text("New entry"),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text("Save",
                    style: TextStyle(
                        color: p.brand, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titleAndDate(p),
              const SizedBox(height: 10),
              _editorCard(p),
              const SizedBox(height: 10),
              _moodPicker(p),
              const SizedBox(height: 10),
              _tagPicker(p),
              const SizedBox(height: 10),
              _attachmentPicker(p),
              const SizedBox(height: 10),
              _privacyToggle(p),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleAndDate(CLPalette p) => CLCard(
        child: Column(
          children: [
            TextField(
              controller: _title,
              style: TextStyle(
                  color: p.text, fontSize: 17, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: "Title",
                hintStyle: TextStyle(color: p.text3),
                border: InputBorder.none,
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
                      style: TextStyle(color: p.text2, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: p.text3),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _editorCard(CLPalette p) => CLCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FleatherToolbar.basic(
              controller: _editor,
              // Trimmed to what the HTML codec represents cleanly and what
              // webapp's own toolbar offers - the full default is far too wide
              // for a phone.
              hideBackgroundColor: true,
              hideForegroundColor: true,
              hideInlineCode: true,
              hideCodeBlock: true,
              hideDirection: true,
              hideUndoRedo: true,
              hideAlignment: true,
            ),
            const Divider(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: FleatherEditor(
                controller: _editor,
                focusNode: _editorFocus,
                expands: false,
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ],
        ),
      );

  Widget _moodPicker(CLPalette p) => CLCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Mood",
                style: TextStyle(
                    color: p.text2, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_moods.isEmpty)
              Text("No moods available",
                  style: TextStyle(color: p.text3, fontSize: 12.5))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _moods.map((mood) {
                  final active = _selectedMood?.id == mood.id;
                  return CLChip(
                    label: "${mood.emoji} ${mood.name}",
                    active: active,
                    // Tapping the active mood clears it - mood is optional
                    // server-side, and there'd otherwise be no way to unset it.
                    onTap: () => setState(
                        () => _selectedMood = active ? null : mood),
                  );
                }).toList(),
              ),
          ],
        ),
      );

  Widget _tagPicker(CLPalette p) => CLCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Forces the card to fill its parent rather than shrinking to fit
            // a single chip.
            const SizedBox(width: double.infinity),
            Text("Tags",
                style: TextStyle(
                    color: p.text2, fontSize: 12, fontWeight: FontWeight.w700)),
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
                          onTap: () => setState(() => _selectedTags.remove(t)),
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
              style: TextStyle(color: p.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search or create a tag",
                hintStyle: TextStyle(color: p.text3, fontSize: 13),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text("Add Tag",
                          style: TextStyle(color: p.brand, fontSize: 12)),
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
                  style: TextStyle(color: p.text3, fontSize: 12)),
            ],
          ],
        ),
      );

  Widget _attachmentPicker(CLPalette p) => CLCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text("Attachments",
                      style: TextStyle(
                          color: p.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _pickAttachments,
                  icon: Icon(Icons.attach_file, size: 17, color: p.brand),
                  label: Text("Add",
                      style: TextStyle(color: p.brand, fontSize: 13)),
                ),
              ],
            ),
            if (_attachments.isEmpty)
              Text("Up to 25MB per file",
                  style: TextStyle(color: p.text3, fontSize: 12))
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
                              style: TextStyle(color: p.text, fontSize: 13)),
                        ),
                        Text(_readableSize(a.size),
                            style: TextStyle(color: p.text3, fontSize: 11.5)),
                        IconButton(
                          icon: Icon(Icons.close, size: 17, color: p.text3),
                          onPressed: () =>
                              setState(() => _attachments.remove(a)),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      );

  Widget _privacyToggle(CLPalette p) => CLCard(
        child: Row(
          children: [
            Icon(_isPrivate ? Icons.lock_outline : Icons.public,
                size: 19, color: p.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isPrivate ? "Private" : "Public",
                      style: TextStyle(
                          color: p.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text(
                    _isPrivate
                        ? "Only you can open this entry"
                        : "Anyone with the link can open this entry",
                    style: TextStyle(color: p.text3, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: !_isPrivate,
              onChanged: (makePublic) =>
                  setState(() => _isPrivate = !makePublic),
            ),
          ],
        ),
      );

  String _readableSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(0)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }
}
