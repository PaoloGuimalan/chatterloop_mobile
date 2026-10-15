import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/reusables/players/voice_message_player.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:chatterloop_app/core/reusables/widgets/media_viewer.dart';
import 'package:chatterloop_app/core/utils/media_downloader.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/material.dart';

/// Shared inline media and download controls for Notes and Diary.
class WritingAttachment extends StatelessWidget {
  const WritingAttachment({super.key, required this.attachment});
  final DiaryAttachment attachment;
  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final p = cl(context);
    if (a.isImage || a.isVideo) {
      return Stack(
        children: [
          a.isImage
              ? GestureDetector(
                  onTap: () => openMediaViewer(
                      context,
                      [
                        MediaViewerItem(
                            source: a.url, isVideo: false, mimeType: a.fileType)
                      ],
                      0),
                  child: CLNetworkImage(
                    src: a.url,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(CLRadii.sm),
                  child: VideoPlayerScreen(videoUrl: a.url),
                ),
          // Top-right: the video's own controls sit at the bottom and centre.
          Positioned(
            top: 8,
            right: 8,
            child: _AttachmentDownloadButton(attachment: a, overMedia: true),
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
                _AttachmentDownloadButton(attachment: a),
              ],
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(CLRadii.sm),
      onTap: () => _AttachmentDownloadButton.start(a),
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
            _AttachmentDownloadButton(attachment: a),
          ],
        ),
      ),
    );
  }
}

/// Saves a diary attachment through the app's downloader: a download icon, or
/// a progress ring while that file is being saved.
///
/// Reads the downloader's notifier rather than local state, because the
/// download outlives this screen - an entry reopened mid-download picks the
/// ring back up instead of offering to start a second copy.
class _AttachmentDownloadButton extends StatelessWidget {
  const _AttachmentDownloadButton(
      {required this.attachment, this.overMedia = false});

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
        fileName:
            mediaFileName(a.url, name: a.fileName, fallback: "attachment"),
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
