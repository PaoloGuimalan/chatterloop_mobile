import 'package:chatterloop_app/models/diary_models/diary_models.dart';

String notePlainText(String content) => content
    .replaceAll(
        RegExp(
            r'<(script|style|iframe|object|embed|svg|math)\b[^>]*>[\s\S]*?</\1\s*>',
            caseSensitive: false),
        '')
    .replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '')
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll(RegExp(r'&(?:nbsp|#160|#x[aA]0);'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class Note {
  const Note(
      {required this.id,
      this.title = '',
      this.content = '',
      required this.version,
      this.sort = 0,
      this.attachments = const [],
      this.updatedAt});
  final String id;
  final String title;
  final String content;
  final int version;
  final int sort;
  final List<DiaryAttachment> attachments;
  final DateTime? updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
      attachments: (json['attachments'] as List? ?? [])
          .whereType<Map>()
          .map((a) => DiaryAttachment.fromJson(Map<String, dynamic>.from(a)))
          .toList());
}

class NoteDraft {
  const NoteDraft(
      {this.title = '', this.content = '', this.attachments = const []});
  final String title;
  final String content;
  final List<DiaryAttachment> attachments;
  bool get hasValue =>
      title
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .trim()
          .isNotEmpty ||
      notePlainText(content).isNotEmpty;
  String get fingerprint =>
      '$title\u0000$content\u0000${attachments.map((a) => a.url).join('\u0000')}';
  factory NoteDraft.fromNote(Note note) => NoteDraft(
      title: note.title, content: note.content, attachments: note.attachments);
  Map<String, dynamic> toPayload() => {
        'title': title,
        'content': content,
        'attachments': attachments
            .map((a) => a.id != null ? {'id': a.id} : {'url': a.url})
            .toList(),
      };
}
