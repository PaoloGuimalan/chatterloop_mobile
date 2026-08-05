// Per-post view-duration telemetry - the `viewcache` every feed request
// carries in its body.
//
// This is NOT analytics you can skip. user_service's save_viewcache_engagements
// (newsfeed/helpers/query_functions.py) does three things with each entry:
//
//   1. writes a UserEngagementLog row (activity_type "view", time_spent =
//      duration), which is what fetch_trending_posts later filters against so
//      you stop being shown things you've already seen;
//   2. bumps the viewer's interest affinity for that post's interests, which
//      feeds resolved_interest_categories and therefore the trending pool;
//   3. DELETES those post_ids from the viewer's NewsfeedIndex bucket.
//
// (3) is the one that bites: NewsfeedIndex is the fan-out inbox the default
// feed reads from, and the only thing that ever drains it is a viewcache
// entry arriving. A client that always sends an empty list gets the same
// posts back at the top of page 1 forever, and never accrues the view history
// the ranker needs. Webapp does this from localforagehelper.ts
// (persistViewPosts / getAllViewCache / clearViewPosts); this is that store.
//
// Persisted rather than in-memory because webapp persists (IndexedDB): a view
// recorded seconds before the app is killed still has to reach the server on
// the next launch's first feed request, or that post is stuck in the bucket.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One post's accumulated time on screen for one viewer.
@immutable
class ViewCacheEntry {
  final String postId;

  /// Whose cache this is - the viewer's ENTITY id. Kept locally and used to
  /// filter on read (see [ViewCache.snapshot]); deliberately NOT sent, since
  /// the server takes the viewer from the token's acting entity. Webapp drops
  /// it in getAllViewCache's map for the same reason.
  final String viewerEntityId;

  /// The AUTHOR's entity id. The server skips logging when this equals the
  /// viewer, so it has to be the entity id and not a username or account id.
  final String postOwnerId;

  /// Seconds on screen, accumulated across every in→out cycle.
  final double duration;

  /// When the FIRST view session on this post began, ISO-8601. Becomes the
  /// engagement log's activity_time.
  final String createdAt;

  const ViewCacheEntry({
    required this.postId,
    required this.viewerEntityId,
    required this.postOwnerId,
    required this.duration,
    required this.createdAt,
  });

  Map<String, dynamic> toStorageJson() => {
        'post_id': postId,
        'user_id': viewerEntityId,
        'post_owner_id': postOwnerId,
        'duration': duration,
        'created_at': createdAt,
      };

  /// The shape the server reads. Note the absent viewer id - see
  /// [viewerEntityId].
  Map<String, dynamic> toRequestJson() => {
        'post_id': postId,
        'duration': duration,
        'post_owner_id': postOwnerId,
        'created_at': createdAt,
      };

  static ViewCacheEntry? fromStorageJson(Map<String, dynamic> json) {
    final postId = (json['post_id'] ?? '').toString();
    if (postId.isEmpty) return null;
    return ViewCacheEntry(
      postId: postId,
      viewerEntityId: (json['user_id'] ?? '').toString(),
      postOwnerId: (json['post_owner_id'] ?? '').toString(),
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class ViewCache {
  ViewCache._();
  static final ViewCache instance = ViewCache._();

  static const _storageKey = 'cl_viewcache_v1';
  static const _persistDebounce = Duration(milliseconds: 300);

  Map<String, ViewCacheEntry>? _entries;
  Future<void>? _hydrating;
  Timer? _persistTimer;

  /// Idempotent, and safe to call concurrently - the first call owns the read
  /// and everyone else awaits the same future.
  Future<void> _hydrate() {
    if (_entries != null) return Future.value();
    return _hydrating ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_storageKey);
        final decoded = raw == null ? null : jsonDecode(raw);
        final restored = <String, ViewCacheEntry>{};
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final entry =
                ViewCacheEntry.fromStorageJson(Map<String, dynamic>.from(item));
            if (entry != null) restored[entry.postId] = entry;
          }
        }
        _entries = restored;
      } catch (e) {
        // A corrupt or unavailable store must never take a feed down with it -
        // the worst case is losing one session's view history. This also
        // covers widget tests, where the plugin isn't registered at all.
        if (kDebugMode) print('[viewcache hydrate] $e');
        _entries = {};
      } finally {
        _hydrating = null;
      }
    }();
  }

  Future<void> _persistNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final entries = _entries;
    if (entries == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(entries.values.map((e) => e.toStorageJson()).toList()),
      );
    } catch (e) {
      if (kDebugMode) print('[viewcache persist] $e');
    }
  }

  /// Coalesces writes: flicking past twenty posts is one write, not twenty.
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(_persistNow());
    });
  }

  /// Records a viewport session. Repeat calls for the same post ACCUMULATE
  /// duration and keep the original [createdAt] - a post you scroll past
  /// three times is one engagement log covering all three, which is what
  /// webapp's persistViewPosts does.
  Future<void> record(
    String postId, {
    required String viewerEntityId,
    required String postOwnerId,
    required double duration,
    required String createdAt,
  }) async {
    if (postId.isEmpty || viewerEntityId.isEmpty) return;
    await _hydrate();
    final entries = _entries;
    if (entries == null) return;

    final existing = entries[postId];
    entries[postId] = ViewCacheEntry(
      postId: postId,
      viewerEntityId: existing?.viewerEntityId ?? viewerEntityId,
      // Post-owner id can arrive empty from a row whose author didn't
      // resolve; don't let that erase a good one.
      postOwnerId:
          postOwnerId.isNotEmpty ? postOwnerId : (existing?.postOwnerId ?? ''),
      duration: _round3((existing?.duration ?? 0) + duration),
      createdAt: existing?.createdAt ?? createdAt,
    );
    _schedulePersist();
  }

  /// What goes in the request body, for this viewer only.
  ///
  /// The filter matters on a shared device: entries left by the previous
  /// account (or by another entity you'd switched to) would otherwise be
  /// attributed to whoever logs in next.
  Future<List<Map<String, dynamic>>> snapshot(String viewerEntityId) async {
    if (viewerEntityId.isEmpty) return const [];
    await _hydrate();
    final entries = _entries;
    if (entries == null) return const [];
    return entries.values
        .where((entry) => entry.viewerEntityId == viewerEntityId)
        .map((entry) => entry.toRequestJson())
        .toList();
  }

  /// Called only after the server has ACCEPTED a snapshot. Awaited rather
  /// than debounced: if the app dies between the response and the write, the
  /// entries resurrect and get counted twice.
  Future<void> clear() async {
    await _hydrate();
    _entries?.clear();
    await _persistNow();
  }

  /// Tests only - drops the in-memory map so the next call re-reads storage.
  @visibleForTesting
  void resetForTest() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _entries = null;
    _hydrating = null;
  }

  static double _round3(double value) => (value * 1000).round() / 1000;
}
