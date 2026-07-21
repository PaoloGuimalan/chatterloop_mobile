// Models for the Diary feature, mirroring diary/serializers.py in the Django
// user service. Read that file rather than guessing when a field is unclear -
// several names differ from what the UI calls them (`tag_objects` vs `tags`
// most notably, see [DiaryEntry.tags]).
//
// Parsing is defensive throughout: every field tolerates null and the wrong
// type, matching the convention in
// models/notifications_models/notifications_item_model.dart. These come from a
// paginated list endpoint, so one malformed row should cost that row, not the
// whole screen.

/// A DRF PageNumberPagination envelope: `{count, next, previous, results}`.
///
/// `next`/`previous` are absolute URLs (or null). Only their presence is used -
/// the diary screens page by number, exactly as webapp's Diary.tsx does, rather
/// than following the URLs.
class DiaryPage<T> {
  const DiaryPage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  final int count;
  final List<T> results;
  final String? next;
  final String? previous;

  bool get hasNext => next != null && next!.isNotEmpty;

  static DiaryPage<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final raw = json["results"];
    return DiaryPage<T>(
      count: json["count"] is int ? json["count"] as int : 0,
      next: json["next"]?.toString(),
      previous: json["previous"]?.toString(),
      results: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => itemFromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  static DiaryPage<T> empty<T>() =>
      DiaryPage<T>(count: 0, results: const [], next: null, previous: null);
}

/// One of the fixed moods seeded server-side (diary/models.py's Mood).
class Mood {
  const Mood({required this.id, required this.name, required this.emoji});

  final int id;
  final String name;
  final String emoji;

  factory Mood.fromJson(Map<String, dynamic> json) => Mood(
        id: json["id"] is int ? json["id"] as int : 0,
        name: (json["name"] ?? "").toString(),
        emoji: (json["emoji"] ?? "").toString(),
      );

  /// The shape POST /api/diary/entry/ expects - it reads `mood["id"]` only
  /// (diary/views.py's DiaryCRUDView.post).
  Map<String, dynamic> toPayload() => {"id": id};
}

/// A tag on an entry. Backed by the shared Interest table, not a diary-specific
/// one, which is why creating a tag here also bumps interest affinity
/// server-side (see EntrySerializer._handle_tags).
class DiaryTag {
  const DiaryTag({required this.id, required this.name});

  /// Null for a tag the user has just typed that doesn't exist yet - the
  /// server resolves it by name via get_or_create_by_name, so the id is only
  /// ever informational on the client.
  final int? id;
  final String name;

  factory DiaryTag.fromJson(Map<String, dynamic> json) => DiaryTag(
        id: json["id"] is int ? json["id"] as int : null,
        name: (json["name"] ?? "").toString(),
      );

  /// POST sends `tags: [{name}]` - ids are ignored server-side, which is what
  /// lets a brand-new tag be sent the same way as an existing one.
  Map<String, dynamic> toPayload() => {"name": name};
}

/// A file attached to an entry. [fileId] is the object-storage id returned by
/// the upload endpoint; the server stores it alongside the URL so the file can
/// be traced back to its record.
class DiaryAttachment {
  const DiaryAttachment({
    required this.url,
    this.id,
    this.fileId,
    this.fileName,
    this.fileType,
    this.createdAt,
  });

  final String url;
  final String? id;
  final String? fileId;
  final String? fileName;
  final String? fileType;
  final DateTime? createdAt;

  bool get isImage {
    final type = (fileType ?? "").toLowerCase();
    if (type.contains("image")) return true;
    // file_type isn't always a MIME type - fall back to the extension.
    final lower = url.toLowerCase();
    return lower.endsWith(".jpg") ||
        lower.endsWith(".jpeg") ||
        lower.endsWith(".png") ||
        lower.endsWith(".gif") ||
        lower.endsWith(".webp");
  }

  factory DiaryAttachment.fromJson(Map<String, dynamic> json) =>
      DiaryAttachment(
        id: json["id"]?.toString(),
        url: (json["url"] ?? "").toString(),
        fileId: json["file_id"]?.toString(),
        fileName: json["file_name"]?.toString(),
        fileType: json["file_type"]?.toString(),
        createdAt: DateTime.tryParse((json["created_at"] ?? "").toString()),
      );

  Map<String, dynamic> toPayload() => {
        "file_id": fileId,
        "file_name": fileName,
        "file_type": fileType,
        "url": url,
      };
}

/// Optional geotag on an entry (diary/models.py's MapView). Only meaningful
/// when [status] is true - the row exists with status false for entries whose
/// location was captured but not shared.
class DiaryMapInfo {
  const DiaryMapInfo({
    required this.status,
    required this.isStationary,
    this.mapViewId,
    this.latitude,
    this.longitude,
  });

  final bool status;
  final bool isStationary;
  final String? mapViewId;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  factory DiaryMapInfo.fromJson(Map<String, dynamic> json) => DiaryMapInfo(
        mapViewId: json["map_view_id"]?.toString(),
        status: json["status"] == true,
        isStationary: json["is_stationary"] == true,
        latitude: (json["latitude"] as num?)?.toDouble(),
        longitude: (json["longitude"] as num?)?.toDouble(),
      );
}

/// A diary entry.
///
/// [content] is **HTML** - webapp authors it with ReactQuill and renders it
/// through dangerouslySetInnerHTML. Never show it raw; use the HTML renderer in
/// the entry detail screen, or [plainTextPreview] for list rows.
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.isPrivate,
    required this.tags,
    required this.attachments,
    this.account,
    this.entryDate,
    this.mood,
    this.mapInfo,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final bool isPrivate;
  final List<DiaryTag> tags;
  final List<DiaryAttachment> attachments;
  final String? account;
  final DateTime? entryDate;
  final Mood? mood;
  final DiaryMapInfo? mapInfo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// A rough plain-text rendering for list previews. Deliberately crude - it
  /// strips tags and unescapes the handful of entities Quill actually emits,
  /// which is enough for a two-line preview and avoids pulling a full HTML
  /// parser into the list's build path.
  String get plainTextPreview {
    final stripped = content
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    // Read tags from `tag_objects`, NOT `tags` - the serializer declares
    // `tags` write-only (a list of bare strings) and exposes the readable
    // {id, name} objects under tag_objects. Reading `tags` here yields an
    // empty list on every response.
    final rawTags = json["tag_objects"];
    final rawAttachments = json["attachments"];
    final rawMood = json["mood"];
    final rawMap = json["entry_map_info"];

    return DiaryEntry(
      id: (json["id"] ?? "").toString(),
      account: json["account"]?.toString(),
      title: (json["title"] ?? "").toString(),
      content: (json["content"] ?? "").toString(),
      // entry_date is a plain "YYYY-MM-DD" DateField, not a timestamp.
      entryDate: DateTime.tryParse((json["entry_date"] ?? "").toString()),
      isPrivate: json["is_private"] != false,
      mood: rawMood is Map
          ? Mood.fromJson(Map<String, dynamic>.from(rawMood))
          : null,
      tags: rawTags is List
          ? rawTags
              .whereType<Map>()
              .map((e) => DiaryTag.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      attachments: rawAttachments is List
          ? rawAttachments
              .whereType<Map>()
              .map((e) =>
                  DiaryAttachment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      mapInfo: rawMap is Map
          ? DiaryMapInfo.fromJson(Map<String, dynamic>.from(rawMap))
          : null,
      createdAt: DateTime.tryParse((json["created_at"] ?? "").toString()),
      updatedAt: DateTime.tryParse((json["updated_at"] ?? "").toString()),
    );
  }
}

/// The public diary summary shown on a profile.
///
/// Comes from the only diary endpoint that allows anonymous access
/// (DiaryTotalView sets AllowAny and returns no authenticators for GET), which
/// is what lets the card render on someone else's profile even though their
/// entries themselves are unreadable.
class DiaryTotal {
  const DiaryTotal({
    required this.user,
    required this.totalEntries,
    required this.topTags,
    this.latestEntry,
  });

  final String user;
  final int totalEntries;
  final List<DiaryTag> topTags;
  final DateTime? latestEntry;

  factory DiaryTotal.fromJson(Map<String, dynamic> json) {
    final rawTags = json["top_tags"];
    return DiaryTotal(
      user: (json["user"] ?? "").toString(),
      totalEntries: json["total_entries"] is int
          ? json["total_entries"] as int
          : int.tryParse((json["total_entries"] ?? "").toString()) ?? 0,
      latestEntry: DateTime.tryParse((json["latest_entry"] ?? "").toString()),
      topTags: rawTags is List
          ? rawTags
              .whereType<Map>()
              .map((e) => DiaryTag.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
