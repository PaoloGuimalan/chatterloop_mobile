// A single diary entry - mirrors webapp's app/tabs/profile/diary/EntryView.tsx.
//
// The server allows this for an entry that isn't yours only when is_private is
// false (DiaryCRUDView.get filters on `Q(account=user) | Q(is_private=False)`),
// so a 404 here is a legitimate "private entry" outcome, not necessarily a bug.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/diary_api.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/utils/date_words.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';
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
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text("Entry")),
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
                  padding: const EdgeInsets.all(12),
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

  Widget _header(DiaryEntry entry, CLPalette p) => CLCard(
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
                        fontWeight: FontWeight.w800),
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
  Widget _content(DiaryEntry entry, CLPalette p) => CLCard(
        child: SizedBox(
          width: double.infinity,
          child: HtmlWidget(
            entry.content,
            textStyle:
                TextStyle(color: p.text, fontSize: CLType.title, height: 1.5),
            onTapUrl: (url) async {
              final uri = Uri.tryParse(url);
              if (uri == null) return false;
              return launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ),
      );

  Widget _tags(DiaryEntry entry, CLPalette p) => CLCard(
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

  Widget _attachments(DiaryEntry entry, CLPalette p) => CLCard(
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
                  child: _attachment(a, p),
                )),
          ],
        ),
      );

  /// Renders an attachment as whatever it actually is: images are shown,
  /// audio and video get real players, and anything else is a file row.
  ///
  /// Both players are the ones already used for message media
  /// (voice_message_player.dart, post_video_widget.dart) rather than new ones,
  /// so diary media behaves exactly like media in a conversation.
  ///
  /// Every kind can be saved through the app's own downloader (see
  /// MediaDownloader) - a button over a picture or video, at the end of an
  /// audio or file row - rather than handed to the browser.
  Widget _attachment(DiaryAttachment a, CLPalette p) {
    if (a.isImage || a.isVideo) {
      return Stack(
        children: [
          a.isImage
              ? CLNetworkImage(
                  src: a.url,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                  child: VideoPlayerScreen(videoUrl: a.url),
                ),
          // Top-right: the video's own controls sit at the bottom and centre.
          Positioned(
            top: 8,
            right: 8,
            child: _DiaryDownloadButton(attachment: a, overMedia: true),
          ),
        ],
      );
    }

    if (a.isAudio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(CLRadii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // isSender only picks the player's colour scheme; the diary has no
            // sender/receiver distinction, so it uses the received styling.
            VoiceMessagePlayer(src: a.url, isSender: false),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(a.fileName ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.text3, fontSize: CLType.caption)),
                  ),
                ),
                _DiaryDownloadButton(attachment: a),
              ],
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(CLRadii.sm),
      onTap: () => _DiaryDownloadButton.start(a),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(CLRadii.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 18, color: p.text2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.fileName ?? "Attachment",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: CLType.bodySm),
              ),
            ),
            _DiaryDownloadButton(attachment: a),
          ],
        ),
      ),
    );
  }

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

/// Saves a diary attachment through the app's downloader: a download icon, or
/// a progress ring while that file is being saved.
///
/// Reads the downloader's notifier rather than local state, because the
/// download outlives this screen - an entry reopened mid-download picks the
/// ring back up instead of offering to start a second copy.
class _DiaryDownloadButton extends StatelessWidget {
  const _DiaryDownloadButton({required this.attachment, this.overMedia = false});

  final DiaryAttachment attachment;

  /// Drawn over a picture or video: white on a dark disc, so it reads on any
  /// frame.
  final bool overMedia;

  /// Fire-and-forget; the downloader reports where the file landed.
  static void start(DiaryAttachment a) => MediaDownloader.instance.download(
        a.url,
        // file_type is sometimes a bare word ("image"); the downloader only
        // trusts it when it is a real MIME type, else goes by the name.
        mimeType: a.fileType,
        fileName: mediaFileName(a.url, name: a.fileName, fallback: "attachment"),
      );

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final color = overMedia ? Colors.white : p.text2;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: MediaDownloader.instance.progress,
      builder: (context, running, _) {
        final value = running[chatMediaUrl(attachment.url)];
        final glyph = SizedBox(
          width: 20,
          height: 20,
          child: value == null
              ? Icon(Icons.download_rounded, size: 20, color: color)
              : CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                  // 0 = no Content-Length to measure against: spin instead.
                  value: value > 0 ? value : null,
                ),
        );
        return Material(
          color: overMedia
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // A tap while it runs is answered by the downloader itself
            // ("Already downloading").
            onTap: () => start(attachment),
            child: Tooltip(
              message: value == null ? "Download" : "Downloading",
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: glyph,
              ),
            ),
          ),
        );
      },
    );
  }
}
