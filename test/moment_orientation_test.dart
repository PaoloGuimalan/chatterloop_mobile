import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = MediaSource(
      path: '/clip.mp4',
      kind: MediaKind.video,
      width: 1920,
      height: 1080,
      duration: Duration(minutes: 4));

  test('landscape orientation survives persistence and timeline edits', () {
    const edit = Composition(
        orientation: CanvasOrientation.landscape,
        clips: [MediaLayer(source: source)]);
    final restored = Composition.fromJson(edit.toJson());
    expect(restored.canvasWidth, 1920);
    expect(restored.canvasHeight, 1080);
    expect(restored.aspectRatio, closeTo(16 / 9, 1e-9));
    final split = restored.splitAt(const Duration(seconds: 20))!;
    expect(split.orientation, CanvasOrientation.landscape);
    expect(split.naturalDuration, const Duration(minutes: 4));
  });

  test('older drafts default to portrait and can change orientation', () {
    final old = Composition.fromJson({
      'v': 4,
      'clips': [
        const MediaLayer(source: source).toJson(),
      ]
    });
    expect(old.orientation, CanvasOrientation.portrait);
    final landscape = old.copyWith(orientation: CanvasOrientation.landscape);
    expect(landscape.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(landscape.clips, same(old.clips));
  });
}
