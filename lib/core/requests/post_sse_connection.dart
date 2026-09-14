import 'dart:async';
import 'dart:convert';

import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/requests/patched_sse_client.dart';
import 'package:chatterloop_app/core/utils/app_version.dart';
import 'package:chatterloop_app/core/utils/device_token.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Live activity on ONE post - comments as they are written, and who is typing.
///
/// A SECOND stream, separate from SseConnection's. That one is opened once per
/// session and addressed to the signed-in entity ("something happened that
/// concerns you"); this is opened per post and addressed to the post
/// ("something happened here"), and reaches whoever is reading it whether or
/// not it concerns them. A comment on a post you are reading is usually
/// neither yours nor about you, so it cannot travel on the notification
/// channel.
///
/// OPENED ONLY BY THE POST SCREEN. A feed shows many post cards at once, and
/// one of these per card would leave a live connection behind for every post
/// scrolled past. The screen that shows a single post in full is the only
/// place a live comment could be seen anyway.
///
/// Unlike SseConnection, nothing here is static: each instance owns its
/// connection, so two posts open in a nav stack cannot close each other's -
/// which is also why PatchedSSEClient had to stop being static (see its own
/// doc comment).

/// What kind of activity an event describes.
///
/// `share` is part of the server's contract but is not published yet; it is
/// listed so a switch over this stays exhaustive when it starts arriving.
/// Anything unrecognised maps to [PostActivityType.unknown] and is ignored -
/// an unknown event type is a newer server, not an error.
enum PostActivityType { comment, typing, reaction, share, unknown }

/// What a [PostActivityType.reaction] was aimed at. The post's tallies and a
/// comment's tallies are different rows behind different endpoints, so this is
/// what says which one to refetch.
enum PostActivityTarget { post, comment, unknown }

/// Who did it. `entityId` is what the UI compares against its own to recognise
/// its OWN echo: it has already applied that change optimistically, so acting
/// on the event again would double-count it.
class PostActivityActor {
  final String entityId;
  final String? handle;
  final String? name;
  final String? type;

  const PostActivityActor({
    required this.entityId,
    this.handle,
    this.name,
    this.type,
  });

  static PostActivityActor? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['entity_id'];
    if (id == null) return null;

    return PostActivityActor(
      entityId: id.toString(),
      handle: raw['handle'] as String?,
      name: raw['name'] as String?,
      type: raw['type'] as String?,
    );
  }
}

class PostActivityEvent {
  final String postId;
  final PostActivityType type;

  /// Present on [PostActivityType.comment].
  final String? commentId;

  /// The thread the new row landed in, which is NOT necessarily the comment
  /// its author aimed at - replying to a reply re-parents onto the top-level
  /// ancestor. null means the top-level list.
  final String? parentId;

  /// Set on [PostActivityType.reaction]; [PostActivityTarget.unknown]
  /// otherwise.
  final PostActivityTarget target;

  /// "added" | "updated" | "removed", on a reaction. Descriptive only -
  /// tallies are refetched rather than derived from it, since a swap moves two
  /// rows and a concurrent reaction may have landed in between.
  final String? action;

  final PostActivityActor? actor;

  const PostActivityEvent({
    required this.postId,
    required this.type,
    this.commentId,
    this.parentId,
    this.target = PostActivityTarget.unknown,
    this.action,
    this.actor,
  });

  static PostActivityType _typeOf(String? raw) => switch (raw) {
        'comment' => PostActivityType.comment,
        'typing' => PostActivityType.typing,
        'reaction' => PostActivityType.reaction,
        'share' => PostActivityType.share,
        _ => PostActivityType.unknown,
      };

  static PostActivityTarget _targetOf(String? raw) => switch (raw) {
        'post' => PostActivityTarget.post,
        'comment' => PostActivityTarget.comment,
        _ => PostActivityTarget.unknown,
      };

  static PostActivityEvent? fromFrame(String data) {
    try {
      final parsed = jsonDecode(data);
      if (parsed is! Map) return null;
      if (parsed['auth'] != true || parsed['status'] != true) return null;

      final result = parsed['result'];
      if (result is! Map) return null;

      return PostActivityEvent(
        postId: (result['post_id'] ?? '').toString(),
        type: _typeOf(result['event_type'] as String?),
        commentId: result['comment_id']?.toString(),
        parentId: result['parent_id']?.toString(),
        target: _targetOf(result['target_type'] as String?),
        action: result['action'] as String?,
        actor: PostActivityActor.fromJson(result['entity']),
      );
    } catch (_) {
      // A frame we cannot parse is a frame we cannot act on. Dropping it costs
      // one missed refresh; throwing out of a stream listener would leave the
      // connection alive and the screen in an unknown state.
      return null;
    }
  }
}

class PostActivityConnection {
  final storage = const FlutterSecureStorage();

  final PatchedSSEClient _client = PatchedSSEClient();
  StreamSubscription? _subscription;

  /// Broadcast, so the comment list and anything else on the post screen can
  /// each listen without one of them consuming the stream.
  final StreamController<PostActivityEvent> _events =
      StreamController<PostActivityEvent>.broadcast();

  Stream<PostActivityEvent> get events => _events.stream;

  Future<void> connect(String postId) async {
    await disconnect();

    final token = await storage.read(key: 'token');
    // Guests can read a public post's comments but get no live updates: the
    // stream is authenticated, because who is typing on a post is not
    // something to hand out to an unidentified reader.
    if (token == null) return;

    final deviceToken = await resolveDeviceToken();
    final sseToken = JwtTools().createJwt({
      "token": token,
      "deviceToken": deviceToken,
      "type": "post_activity",
      "post_id": postId,
    }, secretKey);

    final url =
        '${Endpoints().apiUrl}${Endpoints().ssePostActivityRoute}$sseToken';

    // Same reasoning as sse_connection.dart: resolved BEFORE the header map is
    // built, because that map is what the retry closes over and replays.
    await AppVersion.ensureLoaded();
    final appVersion = AppVersion.header;

    _subscription =
        _client.subscribe(method: SSERequestType.GET, url: url, header: {
      "Accept": "text/event-stream",
      "origin": Endpoints.origin,
      // See sse_connection.dart: gzip's decoder buffers isolated small
      // events until enough later traffic completes a block, which on a
      // quiet post would hold a lone comment event indefinitely.
      "Accept-Encoding": "identity",
      "Cache-Control": "no-cache",
      if (appVersion != null) "X-App-Version": appVersion,
      if (appVersion != null) "X-Platform": AppVersion.platform,
    }).listen((event) {
      if (event.event != 'post_activity') return;

      final data = event.data;
      if (data == null || data.trim().isEmpty) return;

      final parsed = PostActivityEvent.fromFrame(data);
      if (parsed == null) return;
      if (parsed.type == PostActivityType.unknown) return;
      if (_events.isClosed) return;

      _events.add(parsed);
    }, onError: (Object err) {
      // The client retries on its own; this is logged only so a dead stream is
      // visible in debug rather than silently going quiet.
      debugPrint('[post-activity] stream error: $err');
    });
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _client.unsubscribe();
  }

  /// Call from the owning widget's dispose. Closing the controller as well as
  /// the connection matters: the retry can deliver one more event after the
  /// subscription is cancelled, and adding to a controller on a disposed
  /// screen is how a "setState after dispose" starts.
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
