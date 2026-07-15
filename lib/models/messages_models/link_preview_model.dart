// Mirrors webapp's LinkPreviewData (reusables/hooks/useLinkPreview.ts) - the
// backend attaches this to a text message's `linkPreview` field once it's
// resolved a URL found in the message content (see server's
// routes/messages/index.js persisting linkPreview after the fact and
// reusing the "messages_list" SSE channel to signal a refetch).

class LinkPreviewData {
  final String? url;
  final String? resolvedUrl;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;
  final String? favicon;
  final String? embedType; // "video" | "rich" | null
  final String? embedUrl;
  final String? embedProvider;
  final int? embedWidth;
  final int? embedHeight;
  final String? embedLayout; // "auto" | "landscape" | "portrait" | null
  final String status; // "ok" | "failed"

  const LinkPreviewData({
    this.url,
    this.resolvedUrl,
    this.title,
    this.description,
    this.image,
    this.siteName,
    this.favicon,
    this.embedType,
    this.embedUrl,
    this.embedProvider,
    this.embedWidth,
    this.embedHeight,
    this.embedLayout,
    required this.status,
  });

  bool get isOk => status == "ok";
  bool get hasEmbed => embedType != null && embedUrl != null;

  factory LinkPreviewData.fromJson(Map<String, dynamic> json) {
    return LinkPreviewData(
      url: json["url"]?.toString(),
      resolvedUrl: json["resolved_url"]?.toString(),
      title: json["title"]?.toString(),
      description: json["description"]?.toString(),
      image: json["image"]?.toString(),
      siteName: json["site_name"]?.toString(),
      favicon: json["favicon"]?.toString(),
      embedType: json["embed_type"]?.toString(),
      embedUrl: json["embed_url"]?.toString(),
      embedProvider: json["embed_provider"]?.toString(),
      embedWidth: json["embed_width"] is num
          ? (json["embed_width"] as num).toInt()
          : null,
      embedHeight: json["embed_height"] is num
          ? (json["embed_height"] as num).toInt()
          : null,
      embedLayout: json["embed_layout"]?.toString(),
      status: (json["status"] ?? "failed").toString(),
    );
  }
}
