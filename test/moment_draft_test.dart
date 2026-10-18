import 'dart:convert';
import 'dart:io';

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/moment_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Directory support;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('moment_draft_test_');
    support = Directory('${temporary.path}/support');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  MomentDraftStore store([String owner = 'account/entity']) => MomentDraftStore(
        ownerId: owner,
        directoryProvider: () async => support,
      );

  Future<File> source(String name, String contents) =>
      File('${temporary.path}/$name').writeAsString(contents);

  Future<File> manifest() async => (await support
          .list(recursive: true)
          .where((file) => file is File && file.path.endsWith('draft.json'))
          .toList())
      .single as File;

  test('restores every media kind and metadata after picker files disappear',
      () async {
    final video = await source('picked.mp4', 'video');
    final text = await source('text.png', 'text image');
    final audio = await source('voice.m4a', 'sound');
    final draft = MomentDraft(
      edit: Composition(
        clips: [MediaLayer(source: media(video.path, MediaKind.video))],
        overlays: [
          OverlayClip(
            clip: MediaLayer(source: media(text.path, MediaKind.image)),
            text: TextCard(text: video.path),
          ),
        ],
        audio: [
          AudioTrack(
            path: audio.path,
            name: video.path,
            trim: const TrimRange(Duration.zero, Duration(seconds: 3)),
          ),
        ],
      ),
      caption: video.path,
      audience: 'friends',
      allowReplies: false,
      position: const Duration(milliseconds: 2345),
    );

    await store().save(draft);
    await video.delete();
    await text.delete();
    await audio.delete();
    final restored = (await store().load())!;

    expect(restored.caption, video.path);
    expect(restored.audience, 'friends');
    expect(restored.allowReplies, isFalse);
    expect(restored.position, const Duration(milliseconds: 2345));
    expect(restored.edit.overlays.single.text!.text, video.path);
    expect(restored.edit.audio.single.name, video.path);
    expect(await File(restored.edit.clips.single.source.path).readAsString(),
        'video');
    expect(
        await File(restored.edit.overlays.single.clip.source.path)
            .readAsString(),
        'text image');
    expect(await File(restored.edit.audio.single.path).readAsString(), 'sound');
  });

  test('metadata autosaves reuse copied assets and preserve source files',
      () async {
    final original = await source('picked.jpg', 'image');
    final draft = draftFor(original.path);
    final drafts = store();
    await drafts.save(draft);
    final first = (await drafts.load())!;
    final copied = File(first.edit.clips.single.source.path);
    final modified = await copied.lastModified();
    await drafts.save(draftFor(original.path, caption: 'changed'));
    expect((await drafts.load())!.caption, 'changed');
    expect(await copied.lastModified(), modified);
    expect(await original.exists(), isTrue);
    final files =
        await support.list(recursive: true).where((e) => e is File).toList();
    expect(files.length, 2);
  });

  test('account and entity owners have isolated drafts and discard', () async {
    final original = await source('picked.jpg', 'image');
    await store('account/entity-a').save(draftFor(original.path, caption: 'a'));
    await store('account/entity-b').save(draftFor(original.path, caption: 'b'));
    expect(await store('other-account/entity-a').load(), isNull);
    await store('account/entity-a').discard();
    expect(await store('account/entity-a').load(), isNull);
    expect((await store('account/entity-b').load())!.caption, 'b');
    expect(await original.exists(), isTrue);
  });

  test('queued saves retain older restored assets until discard finishes',
      () async {
    final original = await source('picked.jpg', 'image');
    final drafts = store();
    await drafts.save(draftFor(original.path));
    final older = (await drafts.load())!;
    final second = await source('second.jpg', 'second');
    final newSave = drafts.save(draftFor(second.path));
    final oldSave = drafts.save(older);
    await Future.wait([newSave, oldSave]);
    expect(
        await File((await drafts.load())!.edit.clips.single.source.path)
            .readAsString(),
        'image');

    final pendingSave = drafts.save(draftFor(second.path));
    final discarded = drafts.discard();
    await Future.wait([pendingSave, discarded]);
    expect(await store().load(), isNull);
    expect(await second.exists(), isTrue);
  });

  test('missing or corrupt state is ignored without losing unrelated files',
      () async {
    expect(await store().load(), isNull);
    final original = await source('picked.jpg', 'image');
    await store().save(draftFor(original.path));
    final savedManifest = await manifest();
    await savedManifest.writeAsString('{broken');
    expect(await store().load(), isNull);
    await store().save(draftFor(original.path));
    final restored = (await store().load())!;
    await File(restored.edit.clips.single.source.path).delete();
    expect(await store().load(), isNull);
    expect(await original.exists(), isTrue);
  });

  test('a failed save leaves the previous manifest and queue usable', () async {
    final original = await source('picked.jpg', 'image');
    final drafts = store();
    await drafts.save(draftFor(original.path, caption: 'safe'));
    await expectLater(
      drafts.save(draftFor('${temporary.path}/absent.jpg')),
      throwsA(isA<FileSystemException>()),
    );
    expect((await drafts.load())!.caption, 'safe');
    await drafts.save(draftFor(original.path, caption: 'next'));
    expect((await drafts.load())!.caption, 'next');
  });

  test('autosave still works with original paths after picker cache cleanup',
      () async {
    final original = await source('picked.jpg', 'image');
    await store().save(draftFor(original.path));
    await original.delete();
    await store().save(draftFor(original.path, caption: 'after cleanup'));
    final restored = (await store().load())!;
    expect(restored.caption, 'after cleanup');
    expect(await File(restored.edit.clips.single.source.path).readAsString(),
        'image');
  });

  test('a changed source gets a new asset without destroying an old snapshot',
      () async {
    final original = await source('text.png', 'old text image');
    final drafts = store();
    await drafts.save(draftFor(original.path));
    final oldSnapshot = (await drafts.load())!;
    await original.writeAsString('new longer text image');
    await drafts.save(draftFor(original.path));
    final newSnapshot = (await drafts.load())!;
    expect(await File(newSnapshot.edit.clips.single.source.path).readAsString(),
        'new longer text image');
    expect(await File(oldSnapshot.edit.clips.single.source.path).readAsString(),
        'old text image');
  });

  test('relative media survives moving the application support directory',
      () async {
    final original = await source('picked.jpg', 'image');
    await store().save(draftFor(original.path));
    final moved = await support.rename('${temporary.path}/relocated');
    final restored = await MomentDraftStore(
      ownerId: 'account/entity',
      directoryProvider: () async => moved,
    ).load();
    expect(restored, isNotNull);
    expect(await File(restored!.edit.clips.single.source.path).readAsString(),
        'image');
  });

  test('separate store instances serialize a pending save before discard',
      () async {
    final original = await source('picked.jpg', 'image');
    final pending = store().save(draftFor(original.path));
    final discarded = store().discard();
    await Future.wait([pending, discarded]);
    expect(await store().load(), isNull);
  });

  test('manifest media paths cannot escape owned assets', () async {
    final original = await source('picked.jpg', 'image');
    await store().save(draftFor(original.path));
    final savedManifest = await manifest();
    final json = jsonDecode(await savedManifest.readAsString()) as Map;
    json['edit']['clips'][0]['source']['path'] = original.path;
    await savedManifest.writeAsString(jsonEncode(json));
    expect(await store().load(), isNull);
    await store().discard();
    expect(await original.exists(), isTrue);
  });

  test('valid JSON with malformed media fields is ignored safely', () async {
    final original = await source('picked.jpg', 'image');
    await store().save(draftFor(original.path));
    final savedManifest = await manifest();
    final json = jsonDecode(await savedManifest.readAsString()) as Map;
    json['edit']['clips'] = [123];
    await savedManifest.writeAsString(jsonEncode(json));
    expect(await store().load(), isNull);
  });
}

MediaSource media(String path, MediaKind kind) => MediaSource(
      path: path,
      kind: kind,
      width: 100,
      height: 200,
      duration: kind == MediaKind.video ? const Duration(seconds: 8) : null,
    );

MomentDraft draftFor(String path, {String caption = ''}) => MomentDraft(
      edit: Composition(
          clips: [MediaLayer(source: media(path, MediaKind.image))]),
      caption: caption,
      audience: 'public',
      allowReplies: true,
      position: Duration.zero,
    );
