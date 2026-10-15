import 'package:chatterloop_app/core/requests/notes_api.dart';
import 'package:chatterloop_app/models/notes_models/note.dart';
import 'package:chatterloop_app/views/notes/note_autosave.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotesApi api;
  late List<RequestOptions> requests;
  var conflict = false;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'token': 'test-session'});
    api = await NotesApi.open();
    requests = [];
    conflict = false;
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      if (conflict) {
        handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 409),
            type: DioExceptionType.badResponse));
      } else {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: options.method == 'GET'
                ? {
                    'count': 1,
                    'next': null,
                    'results': [
                      {'id': 'n', 'version': 2, 'sort': 10}
                    ]
                  }
                : {'id': 'n', 'version': 2, 'sort': 10}));
      }
    }));
  });
  tearDown(() => api.dio.close());
  test('create permits either title or body and pins its original token',
      () async {
    expect(api.dio.options.extra['authToken'], 'test-session');
    await api.save(const NoteDraft(title: 'Title only'), null);
    expect(requests.last.path, '/api/notes/notes/');
    expect(requests.last.data['content'], '');
    expect(requests.last.data.containsKey('version'), false);
    await api.save(const NoteDraft(content: '<p>Body only</p>'), null);
    expect(requests.last.data['title'], '');
  });
  test('pagination/search and reorder use server collection anchors', () async {
    final page = await api.list(page: 3, search: 'idea');
    expect(requests.last.queryParameters,
        {'page': 3, 'page_size': 20, 'search': 'idea'});
    expect(page.results.single.sort, 10);
    await api.reorder('moving', 'anchor');
    expect(requests.last.path, '/api/notes/notes/reorder/');
    expect(requests.last.data, {'note_id': 'moving', 'before_id': 'anchor'});
    await api.reorder('moving', null);
    expect(requests.last.data, {'note_id': 'moving', 'before_id': null});
  });
  test('patch and delete carry optimistic version and expose conflicts',
      () async {
    const previous = Note(id: 'n', title: 'Previous', version: 7);
    await api.save(const NoteDraft(title: 'Changed'), previous);
    expect(requests.last.method, 'PATCH');
    expect(requests.last.path, '/api/notes/notes/n/');
    expect(requests.last.data['version'], 7);
    await api.delete(previous);
    expect(requests.last.method, 'DELETE');
    expect(requests.last.data, {'version': 7});
    conflict = true;
    await expectLater(api.save(const NoteDraft(title: 'Local'), previous),
        throwsA(isA<NoteConflict>()));
    await expectLater(api.delete(previous), throwsA(isA<NoteConflict>()));
  });
}
