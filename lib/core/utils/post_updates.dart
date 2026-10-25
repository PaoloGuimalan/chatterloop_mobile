import 'package:chatterloop_app/models/post_models/post_preview_model.dart';
import 'package:flutter/foundation.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';

/// Session-local canonical patches shared by feed, detail and nested cards.
/// Only content fields are cached, so a later reaction/comment update keeps
/// its own live counts instead of being replaced by an old full post.
class PostUpdates extends ChangeNotifier {
  PostUpdates._() {
    _scope = _scopeOf(appStore.state.userAuth);
    appStore.onChange.listen((state) => _syncScope(state.userAuth));
  }
  static final instance = PostUpdates._();
  final Map<String, Map<String, dynamic>> _patches = {};
  late String _scope;
  int _generation = 0;

  String _scopeOf(UserAuth auth) =>
      '${auth.auth}:${auth.user.id}:${auth.user.entityId}';

  void _syncScope(UserAuth auth, {bool notify = true}) {
    final next = _scopeOf(auth);
    if (next == _scope) return;
    _scope = next;
    _generation++;
    _patches.clear();
    if (notify) notifyListeners();
  }

  int get session {
    _syncScope(appStore.state.userAuth, notify: false);
    return _generation;
  }

  String captionFor(String postId, String fallback) {
    _syncScope(appStore.state.userAuth, notify: false);
    return _patches[postId]?['caption'] as String? ?? fallback;
  }

  String contentTypeFor(String postId, String fallback) {
    _syncScope(appStore.state.userAuth, notify: false);
    return _patches[postId]?['content_type'] as String? ?? fallback;
  }

  PostPreview resolve(PostPreview post) {
    _syncScope(appStore.state.userAuth, notify: false);
    final patch = _patches[post.postId];
    if (patch != null && post.updatedAt != null) {
      final cachedAt =
          DateTime.tryParse((patch['updated_at'] ?? '').toString());
      if (cachedAt == null || post.updatedAt!.isAfter(cachedAt)) return post;
    }
    return patch == null ? post : post.applyPatch(patch);
  }

  void apply(Map<String, dynamic> patch, {int? forSession}) {
    if (forSession != null && forSession != session) return;
    _syncScope(appStore.state.userAuth, notify: false);
    final id = patch['post_id']?.toString();
    if (id == null || id.isEmpty) return;
    // Archive remains managed by its existing optimistic flow.
    final content = Map<String, dynamic>.from(patch)..remove('is_archived');
    _patches[id] = {...?_patches[id], ...content};
    notifyListeners();
  }

  /// Discard cached content after a destination loses access.
  void clear() {
    _patches.clear();
    notifyListeners();
  }
}
