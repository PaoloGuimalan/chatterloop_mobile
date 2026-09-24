/// Who "Send in message" can send a post to - GET /u/sendPostTargets - and
/// the destinations picked for POST /u/sendPost.
library;

/// One destination: a person or page by ENTITY id (the server opens a chat
/// with them if there is none, like /m/crtc), or a group chat / server
/// channel by conversation id.
class SendPostTarget {
  static const kindEntity = "entity";
  static const kindConversation = "conversation";

  final String kind;
  final String id;

  const SendPostTarget.entity(this.id) : kind = kindEntity;
  const SendPostTarget.conversation(this.id) : kind = kindConversation;

  String get key => "$kind:$id";

  Map<String, dynamic> toJson() => {"kind": kind, "id": id};

  @override
  bool operator ==(Object other) =>
      other is SendPostTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// A row in the picker, whatever section it came from.
class SendPostOption {
  final SendPostTarget target;
  final String title;
  final String subtitle;
  final String? profile;

  /// "user" / "realm" for a person or page; "group" / "channel" otherwise.
  final String kind;

  const SendPostOption({
    required this.target,
    required this.title,
    required this.subtitle,
    required this.kind,
    this.profile,
  });
}

String? _profile(dynamic raw) {
  final value = raw?.toString();
  return (value == null || value.isEmpty || value == "none" || value == "N/A")
      ? null
      : value;
}

class SendPostTargets {
  /// People and pages.
  final List<SendPostOption> direct;
  final List<SendPostOption> groups;

  /// Server channels, labelled with their server.
  final List<SendPostOption> channels;

  const SendPostTargets({
    required this.direct,
    required this.groups,
    required this.channels,
  });

  static const empty = SendPostTargets(direct: [], groups: [], channels: []);

  bool get isEmpty => direct.isEmpty && groups.isEmpty && channels.isEmpty;

  factory SendPostTargets.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> listOf(String key) => json[key] is List
        ? (json[key] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : const [];

    return SendPostTargets(
      direct: listOf("direct")
          .where((d) => (d["entity_id"] ?? "").toString().isNotEmpty)
          .map((d) {
        final handle = (d["handle"] ?? "").toString();
        final isPage = d["type"] == "realm";
        return SendPostOption(
          target: SendPostTarget.entity(d["entity_id"].toString()),
          title: (d["display_name"] ?? handle).toString(),
          subtitle: isPage ? "Page · @$handle" : "@$handle",
          kind: (d["type"] ?? "user").toString(),
          profile: _profile(d["profile"]),
        );
      }).toList(),
      groups: listOf("groups")
          .where((g) => (g["conversation_id"] ?? "").toString().isNotEmpty)
          .map((g) => SendPostOption(
                target: SendPostTarget.conversation(
                    g["conversation_id"].toString()),
                title: (g["display_name"] ?? "").toString(),
                subtitle: "Group",
                kind: "group",
                profile: _profile(g["profile"]),
              ))
          .toList(),
      channels: listOf("channels")
          .where((c) => (c["conversation_id"] ?? "").toString().isNotEmpty)
          .map((c) {
        final server = (c["server_name"] ?? "").toString();
        return SendPostOption(
          target: SendPostTarget.conversation(c["conversation_id"].toString()),
          title: "# ${(c["display_name"] ?? "").toString()}",
          subtitle: server.isEmpty ? "Server channel" : "Server · $server",
          kind: "channel",
          profile: _profile(c["server_profile"]),
        );
      }).toList(),
    );
  }
}
