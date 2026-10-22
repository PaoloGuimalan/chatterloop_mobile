// A single diary entry - mirrors webapp's app/tabs/profile/diary/EntryView.tsx.
//
// The server allows this for an entry that isn't yours only when is_private is
// false (DiaryCRUDView.get filters on `Q(account=user) | Q(is_private=False)`),
// so a 404 here is a legitimate "private entry" outcome, not necessarily a bug.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_attachment.dart';
import 'package:chatterloop_app/core/reusables/widgets/link_preview_card.dart';
import 'package:chatterloop_app/views/notes/writing_skeletons.dart';
import 'package:chatterloop_app/core/reusables/widgets/writing_body.dart';
import 'package:chatterloop_app/core/encryption/diary_session.dart';
import 'package:chatterloop_app/core/encryption/passphrase_crypto.dart';
import 'package:chatterloop_app/views/settings/passphrase_section.dart';
import 'package:chatterloop_app/views/diary/locked_diary.dart';

class DiaryEntryScreen extends StatefulWidget {
  const DiaryEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<DiaryEntryScreen> createState() => _DiaryEntryScreenState();
}

class _DiaryEntryScreenState extends State<DiaryEntryScreen> {
  DiaryEntry? _entry;
  bool _isLoading = true;
  bool _promptOpen = false, _autoPrompted = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ticket = ++_loadGeneration;
    final result = await DiaryApi().getEntry(widget.entryId);
    if (!mounted || ticket != _loadGeneration) return;
    setState(() {
      _entry = result;
      _isLoading = false;
    });
    if (DiarySession.instance.purposeEnabled &&
        result?.isLocked == true &&
        !_autoPrompted) {
      _autoPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ticket == _loadGeneration && identical(_entry, result)) {
          _unlockEntry();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant DiaryEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId) {
      _entry = null;
      _isLoading = true;
      _autoPrompted = false;
      _load();
    }
  }

  Future<void> _unlockEntry() async {
    final entry = _entry;
    if (entry == null ||
        !entry.isLocked ||
        _promptOpen ||
        !DiarySession.instance.purposeEnabled) {
      return;
    }
    final session = DiarySession.instance,
        generation = DiarySession.instance.generation;
    try {
      final e = PassphraseCrypto.envelope(entry.encryptedTitle!);
      final configuration =
          session.configuration(e['configuration_id'] as String);
      if (configuration == null) return;
      _promptOpen = true;
      final result = await promptPassphrase(context, configuration);
      if (result == null) return;
      if (!mounted ||
          generation != session.generation ||
          !identical(_entry, entry)) {
        result.key.fillRange(0, result.key.length, 0);
        return;
      }
      session.addKey(configuration['id'] as String, result.key);
      final opened = await session.openEntry(entry);
      if (mounted && generation == session.generation) {
        setState(() => _entry = opened);
      }
    } catch (_) {/* Keep malformed or tampered entries locked. */} finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final entry = _entry;

    return CLScreen(
      backgroundColor: p.surface,
      appBar: AppBar(
          centerTitle: false,
          leadingWidth: 48,
          titleSpacing: 4,
          backgroundColor: p.surface,
          title: const Text("Diary",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      body: _isLoading
          ? const WritingDocumentSkeleton(
              key: ValueKey('writing-entry-skeleton'))
          : entry == null
              ? Center(
                  child: CLEmptyState(
                    icon: Icons.lock_outline,
                    iconBg: p.surface2,
                    iconColor: p.text3,
                    title: "Entry unavailable",
                    subtitle: "It may be private, or no longer exist.",
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(19, 23, 19, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(entry, p),
                      const SizedBox(height: 10),
                      if (entry.isLocked) ...[
                        Row(children: [
                          Icon(Icons.lock_outline, size: 15, color: p.text2),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  DiarySession.instance.purposeEnabled
                                      ? 'Entry needs a different or older key to unlock'
                                      : 'Diary protection is temporarily unavailable.',
                                  style: TextStyle(
                                      fontSize: CLType.caption,
                                      color: p.text2))),
                          if (DiarySession.instance.purposeEnabled)
                            TextButton(
                                onPressed: _unlockEntry,
                                child: const Text('Unlock entry')),
                        ]),
                        const SizedBox(height: 16),
                        const LockedDiaryContent(
                            key: ValueKey('locked-diary-content')),
                      ] else
                        _content(entry, p),
                      if (!entry.isEncrypted &&
                          (entry.linkPreview?.isOk ?? false)) ...[
                        const SizedBox(height: 16),
                        LinkPreviewCard(preview: entry.linkPreview),
                      ],
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _tags(entry, p),
                      ],
                      if (entry.attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _attachments(entry, p),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _header(DiaryEntry entry, CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (entry.mood != null) ...[
                  // Emoji glyph sized to its container - not a CLType step.
                  Text(entry.mood!.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: entry.isLocked
                      ? const LockedDiaryTitle(
                          key: ValueKey('locked-diary-title'))
                      : Text(
                          entry.title.isEmpty ? "Untitled" : entry.title,
                          style: TextStyle(
                              color: p.text,
                              fontSize: CLType.screenTitle,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: p.text3),
                const SizedBox(width: 5),
                // Flexible: at a large system text size the date alone can
                // outgrow a narrow phone, and overflowed the row.
                Flexible(
                  child: Text(
                    entry.entryDate != null
                        ? _formatDate(entry.entryDate!)
                        : "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text3, fontSize: CLType.caption),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(entry.isPrivate ? Icons.lock_outline : Icons.public,
                    size: 13, color: p.text3),
                const SizedBox(width: 5),
                Text(
                    entry.isEncrypted
                        ? "Encrypted"
                        : entry.isPrivate
                            ? "Private"
                            : "Public",
                    style: TextStyle(color: p.text3, fontSize: CLType.caption)),
                if (entry.mood != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(entry.mood!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.text3, fontSize: CLType.caption)),
                  ),
                ],
              ],
            ),
          ],
        ),
      );

  /// Content is HTML authored by Quill on either client, so it's rendered
  /// rather than shown literally. HtmlWidget covers the subset Quill emits
  /// (paragraphs, lists, bold/italic/underline, links, headings); anything
  /// unsupported degrades to its text rather than failing.
  Widget _content(DiaryEntry entry, CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          child: WritingHtmlBody(html: entry.content),
        ),
      );

  Widget _tags(DiaryEntry entry, CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keeps the card full-width instead of shrinking around a single
            // chip, so it lines up with the cards above and below it.
            const SizedBox(width: double.infinity),
            Text("Tags",
                style: TextStyle(
                    color: p.text2,
                    fontSize: CLType.caption,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.tags.map((t) => CLChip(label: t.name)).toList(),
            ),
          ],
        ),
      );

  Widget _attachments(DiaryEntry entry, CLPalette p) => Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: double.infinity),
            Text("Attachments (${entry.attachments.length})",
                style: TextStyle(
                    color: p.text2,
                    fontSize: CLType.caption,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...entry.attachments.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WritingAttachment(attachment: a),
                )),
          ],
        ),
      );

  String _formatDate(DateTime date) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return "${ordinalSuffix(date.day)} of ${months[date.month - 1]}, ${date.year}";
  }
}
