import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/models/diary_models/diary_models.dart';
import 'package:chatterloop_app/models/notes_models/note.dart';
import 'package:chatterloop_app/views/notes/note_autosave.dart';
import 'package:dio/dio.dart';

class NotesApi {
  NotesApi._(this.entityId, this.accountId, this.token);
  final String entityId;
  final String accountId;
  final String token;
  late final Dio dio = ApiClient.userService.forToken(token);
  static const path = '/api/notes/notes/';
  bool get isCurrent =>
      appStore.state.userAuth.user.entityId == entityId &&
      appStore.state.userAuth.user.id == accountId;
  static Future<NotesApi> open() async {
    final user = appStore.state.userAuth.user;
    final token = await ApiClient.userService.readToken();
    if (token == null ||
        appStore.state.userAuth.user.entityId != user.entityId ||
        appStore.state.userAuth.user.id != user.id) {
      throw StateError('Account changed');
    }
    return NotesApi._(user.entityId, user.id, token);
  }

  void _check() {
    if (!isCurrent) throw StateError('Account changed. Draft retained');
  }

  Future<DiaryPage<Note>> list({int page = 1, String search = ''}) async {
    _check();
    final response = await dio.get(path,
        queryParameters: {'page': page, 'page_size': 20, 'search': search});
    return DiaryPage.fromJson(
        Map<String, dynamic>.from(response.data), Note.fromJson);
  }

  Future<Note> get(String id) async {
    _check();
    return Note.fromJson(
        Map<String, dynamic>.from((await dio.get('$path$id/')).data));
  }

  Future<Note> save(NoteDraft draft, Note? previous) async {
    _check();
    try {
      final response = previous == null
          ? await dio.post(path, data: draft.toPayload())
          : await dio.patch('$path${previous.id}/',
              data: {...draft.toPayload(), 'version': previous.version});
      return Note.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) throw NoteConflict();
      rethrow;
    }
  }

  Future<void> reorder(String id, String? beforeId) async {
    _check();
    await dio
        .post('${path}reorder/', data: {'note_id': id, 'before_id': beforeId});
  }

  Future<void> delete(Note note) async {
    _check();
    try {
      await dio.delete('$path${note.id}/', data: {'version': note.version});
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) throw NoteConflict();
      rethrow;
    }
  }
}
