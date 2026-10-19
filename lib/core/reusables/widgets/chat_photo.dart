import 'dart:math' as math;

import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:flutter/material.dart';

/// The image sizes its bubble at its natural aspect ratio, within the chat's
/// width limit. Metadata can size the loading placeholder, but never forces
/// the loaded image into a fixed frame or crops it to a shared thumbnail size.
class ChatPhotoPreview extends StatelessWidget {
  const ChatPhotoPreview(
      {super.key,
      required this.source,
      this.isLocal = false,
      this.aspectRatio});

  final String source;
  final bool isLocal;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: LayoutBuilder(builder: (context, box) {
        final width =
            math.min(270.0, box.hasBoundedWidth ? box.maxWidth : 270.0);
        final ratio = aspectRatio;
        final placeholderHeight = ratio != null && ratio.isFinite && ratio > 0
            ? width / ratio
            : 160.0;
        return CLNetworkImage(
            src: source,
            isLocal: isLocal,
            placeholderHeight: placeholderHeight,
            fit: BoxFit.cover);
      }));
}
