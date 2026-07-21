// Diary endpoints (Django user service). Mirrors the Diary* request helpers in
// webapp/src/reusables/hooks/requests.ts.
//
// Every method swallows its errors and returns null / an empty page, matching
// the convention in notifications_api.dart - callers render an empty or error
// state rather than handling exceptions.

import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:flutter/foundation.dart';

class DiaryApi {
  // userService, not instance - every diary route lives on the Django user
  // service (userApiUrl), not the Node realtime API.
  final _dio = ApiClient.userService.dio;
  final _endpoints = Endpoints();

  /// The signed-in account's own entries, newest first.
  ///
  /// There is no variant of this for another account - DiaryListView filters
  /// on `account=request.user` unconditionally. Someone else's diary can only
  /// ever be summarised via [getDiaryTotal].
  Future<DiaryPage<DiaryEntry>> getEntries({int page = 1, int range = 10}) async {
    try {
      final response = await _dio.get(
        _endpoints.diaryEntries,
        queryParameters: {'page': page, 'page_size': range},
      );
      final data = response.data;
      if (data is! Map) return DiaryPage.empty<DiaryEntry>();
      return DiaryPage.fromJson<DiaryEntry>(
        Map<String, dynamic>.from(data),
        DiaryEntry.fromJson,
      );
    } catch (e) {
      if (kDebugMode) print("[diary] getEntries failed: $e");
      return DiaryPage.empty<DiaryEntry>();
    }
  }

  /// One entry. Succeeds for an entry that isn't yours only when it's public.
  Future<DiaryEntry?> getEntry(String entryId) async {
    try {
      final response = await _dio.get('${_endpoints.diaryEntry}$entryId/');
      final data = response.data;
      if (data is! Map) return null;
      return DiaryEntry.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) print("[diary] getEntry failed: $e");
      return null;
    }
  }

  /// Creates an entry, returning the created row (with its resolved tags and
  /// attachments) or null.
  ///
  /// [entryDate] must be `YYYY-MM-DD`: the server splits on a space and parses
  /// with `%Y-%m-%d`, so a full ISO-8601 timestamp with a `T` separator throws.
  /// Title and content must both be non-empty or the server answers 422.
  Future<DiaryEntry?> createEntry({
    required String title,
    required String content,
    required String entryDate,
    required bool isPrivate,
    Mood? mood,
    List<DiaryTag> tags = const [],
    List<DiaryAttachment> attachments = const [],
  }) async {
    try {
      final response = await _dio.post(_endpoints.diaryEntry, data: {
        'title': title,
        'content': content,
        'entry_date': entryDate,
        'is_private': isPrivate,
        'mood': mood?.toPayload(),
        'tags': tags.map((t) => t.toPayload()).toList(),
        'attachments': attachments.map((a) => a.toPayload()).toList(),
      });
      final data = response.data;
      if (data is! Map) return null;
      return DiaryEntry.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) print("[diary] createEntry failed: $e");
      return null;
    }
  }

  /// Public summary for [username] - works without auth and for any account.
  Future<DiaryTotal?> getDiaryTotal(String username) async {
    try {
      final response = await _dio.get('${_endpoints.diaryTotal}$username/');
      final data = response.data;
      if (data is! Map) return null;
      return DiaryTotal.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (kDebugMode) print("[diary] getDiaryTotal failed: $e");
      return null;
    }
  }

  /// One page of moods. Returns the whole page rather than a bare list so the
  /// picker can page through it the way webapp's AsyncPaginate does, instead
  /// of guessing at a range large enough to cover every mood.
  Future<DiaryPage<Mood>> getMoods({int page = 1, int range = 10}) async {
    try {
      final response = await _dio.get(
        _endpoints.diaryMoods,
        queryParameters: {'page': page, 'page_size': range},
      );
      final data = response.data;
      if (data is! Map) return DiaryPage.empty<Mood>();
      return DiaryPage.fromJson<Mood>(
        Map<String, dynamic>.from(data),
        Mood.fromJson,
      );
    } catch (e) {
      if (kDebugMode) print("[diary] getMoods failed: $e");
      return DiaryPage.empty<Mood>();
    }
  }

  /// Tag autocomplete. An empty [search] returns the general list.
  ///
  /// This endpoint does NOT return a plain DRF page: `results` is an object,
  /// `{list, is_new}`, not an array (interests/views.py wraps the payload
  /// before handing it to get_paginated_response). Parsing it as a normal page
  /// silently yields nothing.
  ///
  /// [isNew] is the server's verdict that [search] matches no existing
  /// interest, checked case- and whitespace-insensitively against
  /// normalized_name - which is why it's trusted here rather than recomputed
  /// from [tags] client-side, where "  Travel " vs "travel" would disagree.
  Future<({List<DiaryTag> tags, bool isNew})> searchTags({
    String search = '',
    int page = 1,
    int range = 10,
  }) async {
    try {
      final response = await _dio.get(
        _endpoints.diaryTags,
        queryParameters: {'search': search, 'page': page, 'page_size': range},
      );
      final data = response.data;
      if (data is! Map) return (tags: <DiaryTag>[], isNew: false);

      final results = data["results"];
      if (results is! Map) return (tags: <DiaryTag>[], isNew: false);

      final rawList = results["list"];
      final tags = rawList is List
          ? rawList
              .whereType<Map>()
              .map((e) => DiaryTag.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <DiaryTag>[];

      return (tags: tags, isNew: results["is_new"] == true);
    } catch (e) {
      if (kDebugMode) print("[diary] searchTags failed: $e");
      return (tags: <DiaryTag>[], isNew: false);
    }
  }
}
