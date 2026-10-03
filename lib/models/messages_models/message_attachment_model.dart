/// A file message's file - the `attachment` the server stores with every
/// file message: { fileId, url, name, mime, kind, size, status }.
///
/// Clients read a file's name and link only from here; nothing reads them out
/// of the URL any more. Messages sent before attachments existed got theirs
/// from a one-time server backfill (scripts/backfillMessageAttachments.js),
/// the last place that parsing happened. A message without one shows "File".
class MessageAttachment {
  const MessageAttachment({
    required this.url,
    required this.name,
    this.fileId,
    this.mime,
    this.kind,
    this.size,
    this.available = true,
  });

  final String url;
  final String name;
  final String? fileId;
  final String? mime;

  /// image | video | audio | file
  final String? kind;
  final int? size;

  /// False when the file itself is gone (the old Firebase uploads).
  final bool available;

  static MessageAttachment? tryParse(dynamic json) {
    if (json is! Map) return null;
    final url = json['url']?.toString();
    if (url == null || url.isEmpty) return null;
    return MessageAttachment(
      url: url,
      name: (json['name'] ?? 'File').toString(),
      fileId: json['fileId']?.toString(),
      mime: json['mime']?.toString(),
      kind: json['kind']?.toString(),
      size: (json['size'] as num?)?.toInt(),
      available: json['status'] != 'unavailable',
    );
  }

  /// "2.4 MB", "830 KB" - empty when unknown.
  String get sizeLabel => formatFileSize(size);
}

String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}
