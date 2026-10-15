import 'dart:async';
import 'package:chatterloop_app/models/notes_models/note.dart';
import 'package:chatterloop_app/views/notes/note_autosave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debounces title-only changes for two seconds', (tester) async {
    var calls = 0;
    final save = NoteAutosave(
        write: (draft, previous) async {
          calls++;
          return Note(
              id: 'n',
              title: draft.title,
              content: draft.content,
              version: calls);
        },
        isCurrentEntity: () => true);
    save.update(const NoteDraft(title: 'Title only'));
    expect(save.status, 'Unsaved changes');
    await tester.pump(const Duration(milliseconds: 1999));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    expect(save.status, 'Saved');
    save.dispose();
  });
  testWidgets('serializes and retains input made during a request',
      (tester) async {
    final first = Completer<Note>();
    final requests = <NoteDraft>[];
    final save = NoteAutosave(
        write: (draft, previous) async {
          requests.add(draft);
          if (requests.length == 1) return first.future;
          expectSync(previous?.version, 1);
          return Note(
              id: 'n', title: draft.title, content: draft.content, version: 2);
        },
        isCurrentEntity: () => true);
    save.update(const NoteDraft(content: '<p>Body only</p>'));
    await tester.pump(const Duration(seconds: 2));
    save.update(const NoteDraft(content: '<p>Later input</p>'));
    await tester.pump(const Duration(seconds: 2));
    expect(requests.length, 1);
    first
        .complete(const Note(id: 'n', content: '<p>Body only</p>', version: 1));
    await tester.pump();
    expect(requests.length, 2);
    expect(save.draft.content, '<p>Later input</p>');
    expect(save.lastError, isNull);
    expect(save.status, 'Saved');
    save.dispose();
  });
  testWidgets('errors retain drafts and entity changes prevent writes',
      (tester) async {
    var current = true;
    var calls = 0;
    final save = NoteAutosave(
        write: (draft, previous) async {
          calls++;
          throw StateError('offline');
        },
        isCurrentEntity: () => current);
    save.update(const NoteDraft(title: 'Keep me'));
    await tester.pump(const Duration(seconds: 2));
    expect(save.dirty, true);
    expect(save.draft.title, 'Keep me');
    expect(save.status, "Couldn't save. Retry");
    current = false;
    await save.flush();
    expect(calls, 1);
    expect(save.dirty, true);
    save.dispose();
  });
  test('empty HTML is never created', () {
    expect(const NoteDraft(content: '<p><br></p>').hasValue, false);
    expect(const NoteDraft(content: '<p>&nbsp;</p>').hasValue, false);
    expect(const NoteDraft(content: '<p>Body</p>').hasValue, true);
    expect(const NoteDraft(title: 'Title').hasValue, true);
    expect(const NoteDraft(content: '<p>\u200b</p>').hasValue, false);
    expect(const NoteDraft(content: '<script>hidden</script>').hasValue, false);
  });
  testWidgets('navigation flush awaits every in-flight snapshot',
      (tester) async {
    final first = Completer<Note>();
    final second = Completer<Note>();
    var calls = 0;
    final save = NoteAutosave(
        write: (draft, previous) {
          calls++;
          return calls == 1 ? first.future : second.future;
        },
        isCurrentEntity: () => true);
    save.update(const NoteDraft(title: 'First'));
    await tester.pump(const Duration(seconds: 2));
    save.update(const NoteDraft(title: 'Second'));
    var finished = false;
    final flushing = save.flush().then((_) => finished = true);
    first.complete(const Note(id: 'n', title: 'First', version: 1));
    await tester.pump();
    expect(calls, 2);
    expect(finished, false);
    second.complete(const Note(id: 'n', title: 'Second', version: 2));
    await tester.pump();
    await flushing;
    expect(save.dirty, false);
    save.dispose();
  });
  testWidgets('input during request keeps its own two second idle delay',
      (tester) async {
    final first = Completer<Note>();
    var calls = 0;
    final save = NoteAutosave(
        write: (draft, previous) async {
          calls++;
          if (calls == 1) return first.future;
          return Note(id: 'n', title: draft.title, version: 2);
        },
        isCurrentEntity: () => true);
    save.update(const NoteDraft(title: 'First'));
    await tester.pump(const Duration(seconds: 2));
    save.update(const NoteDraft(title: 'Second'));
    first.complete(const Note(id: 'n', title: 'First', version: 1));
    await tester.pump(const Duration(milliseconds: 1999));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    save.dispose();
  });
  testWidgets('conflicts retain local edits without automatic overwrite',
      (tester) async {
    var calls = 0;
    final save = NoteAutosave(
        write: (_, __) async {
          calls++;
          throw NoteConflict();
        },
        isCurrentEntity: () => true,
        initial: const Note(id: 'n', title: 'Original', version: 1));
    save.update(const NoteDraft(title: 'Local edit'));
    await tester.pump(const Duration(seconds: 2));
    expect(save.conflict, true);
    save.update(const NoteDraft(title: 'More local edits'));
    await tester.pump(const Duration(seconds: 4));
    await save.flush();
    expect(calls, 1);
    expect(save.draft.title, 'More local edits');
    expect(save.saved?.version, 1);
    save.dispose();
  });
  testWidgets('entity switch before idle does not retry or recurse',
      (tester) async {
    var current = true;
    var calls = 0;
    final save = NoteAutosave(
        write: (draft, previous) async {
          calls++;
          return const Note(id: 'n', title: 'Saved', version: 1);
        },
        isCurrentEntity: () => current);
    save.update(const NoteDraft(title: 'Keep this in the original account'));
    current = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    expect(save.status, 'Account changed. Draft retained');
    expect(save.dirty, true);
    save.dispose();
  });
}
