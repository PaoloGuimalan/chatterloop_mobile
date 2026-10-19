import 'dart:async';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/media/display_image.dart';
import 'package:chatterloop_app/core/reusables/widgets/chat_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in [
    (name: 'portrait', size: const Size(270, 1080)),
    (name: 'landscape', size: const Size(270, 135)),
    (name: 'small', size: const Size(40, 80)),
  ]) {
    testWidgets('a ${example.name} photo sizes its container to the image',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final url = 'https://cdn.test/${example.name}';
      final frame = Completer<ImageInfo>();
      PaintingBinding.instance.imageCache.putIfAbsent(
          DisplayImage(source: url, width: 270, fit: BoxFit.cover),
          () => OneFrameImageStreamCompleter(frame.future));
      await tester.pumpWidget(MaterialApp(
          theme: buildCLTheme(Brightness.light),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: ChatPhotoPreview(source: url))))));
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
      final decoded = await tester.runAsync(() => createTestImage(
          width: example.size.width.toInt(),
          height: example.size.height.toInt()));
      frame.complete(ImageInfo(image: decoded!));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ChatPhotoPreview)), example.size);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
