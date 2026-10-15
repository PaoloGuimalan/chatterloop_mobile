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
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

class DiaryEntryScreen extends StatefulWidget {
  const DiaryEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<DiaryEntryScreen> createState() => _DiaryEntryScreenState();
}

class _DiaryEntryScreenState extends State<DiaryEntryScreen> {
  DiaryEntry? _entry;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await DiaryApi().getEntry(widget.entryId);
    if (!mounted) return;
    setState(() {
      _entry = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final entry = _entry;

    return CLScreen(
      backgroundColor: p.surface,
      appBar: AppBar(
          backgroundColor: p.surface,
          title: const Text("Diary",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      body: _isLoading
          ? const Padding(padding: EdgeInsets.all(12), child: CLListSkeleton())
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
                      _content(entry, p),
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
                  child: Text(
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
                Text(entry.isPrivate ? "Private" : "Public",
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
          child: HtmlWidget(
            entry.content,
            textStyle: TextStyle(color: p.text, fontSize: 14, height: 1.8),
            onTapUrl: (url) async {
              final uri = Uri.tryParse(url);
              if (uri == null) return false;
              return launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
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
