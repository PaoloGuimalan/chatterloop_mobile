/// What /m/conversationfiles can be filtered by - one per tab of the shared
/// files screen.
///
/// Classified server-side with the same rules the message bubbles use
/// (message_content_widget): "image" exactly is a photo, anything containing
/// "video" a video, "audio" audio, and every other attachment a file.
enum ConversationFileKind {
  image('image'),
  video('video'),
  audio('audio'),
  file('file');

  /// The `types` value the endpoint takes, and the `kind` it sends back.
  final String wire;

  const ConversationFileKind(this.wire);

  static ConversationFileKind fromWire(String? value) =>
      ConversationFileKind.values.firstWhere(
        (kind) => kind.wire == value,
        orElse: () => ConversationFileKind.file,
      );

  bool get isVisual =>
      this == ConversationFileKind.image || this == ConversationFileKind.video;
}

/// One file shared in a conversation.
class ConversationFileItem {
  final String messageID;

  /// Entity id of whoever sent it.
  final String sender;
  final ConversationFileKind kind;

  /// The message's messageType - "image", or a real mime type.
  final String mimeType;

  /// The RAW stored reference - a bare URL, or the legacy "url%%%name". Read
  /// it through chatMediaUrl / chatMediaFileName, like a message's content.
  final String content;
  final DateTime? sentAt;

  const ConversationFileItem({
    required this.messageID,
    required this.sender,
    required this.kind,
    required this.mimeType,
    required this.content,
    this.sentAt,
  });

  factory ConversationFileItem.fromJson(Map<String, dynamic> json) {
    return ConversationFileItem(
      messageID: (json["messageID"] ?? "").toString(),
      sender: (json["sender"] ?? "").toString(),
      kind: ConversationFileKind.fromWire(json["kind"]?.toString()),
      mimeType: (json["mimeType"] ?? "").toString(),
      content: (json["content"] ?? "").toString(),
      sentAt: DateTime.tryParse((json["sentAt"] ?? "").toString())?.toLocal(),
    );
  }
}

/// A page of [ConversationFileItem]s, newest first.
class ConversationFilesPage {
  final List<ConversationFileItem> items;

  /// Hand back for the next page; null when there is nothing older.
  final String? nextCursor;

  const ConversationFilesPage({required this.items, this.nextCursor});

  factory ConversationFilesPage.fromJson(Map<String, dynamic> json) {
    final raw = json["items"];
    final cursor = json["nextCursor"];
    return ConversationFilesPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => ConversationFileItem.fromJson(
                  Map<String, dynamic>.from(item)))
              .where((item) => item.content.isNotEmpty)
              .toList()
          : const [],
      nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
    );
  }
}
