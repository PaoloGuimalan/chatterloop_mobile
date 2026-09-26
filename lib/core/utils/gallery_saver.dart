// Saving a photo or video into the phone's gallery - where a saved Moment is
// looked for, rather than Downloads.
//
// Android: MediaSaver.kt (the native saver chat downloads use), into a
// "Chatterloop" album - Pictures/Chatterloop, photos and videos together.
//
// iOS: the app has no Photos code of its own; the share sheet's "Save Video"
// / "Save Image" puts it in Photos (Info.plist already has the photo library
// usage string that needs).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class GallerySaver {
  GallerySaver._();

  static const MethodChannel _channel = MethodChannel('chatterloop/media_saver');

  /// Saves the file at [path] into the gallery as [fileName].
  ///
  /// True once it is in the gallery - the caller confirms it. False when the
  /// share sheet did the saving (iOS): the user chose there, and the sheet
  /// said so itself.
  ///
  /// Throws a [PlatformException] when it can't be saved - code
  /// "permission_denied" when storage access was refused (Android 9 and
  /// older).
  static Future<bool> save(
    String path, {
    required String fileName,
    required String mimeType,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<String>('saveToGallery', {
        'path': path,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return true;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: mimeType)],
      fileNameOverrides: [fileName],
    ));
    return false;
  }

  /// "Chatterloop_20260926_204112.mp4" - named for when it was made, as a
  /// camera names its shots.
  static String fileNameFor(DateTime made, String extension) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = made.toLocal();
    return 'Chatterloop_${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}.$extension';
  }

  /// The extension and content type to save [url] under: from its name when
  /// that says a photo (or a video, [isVideo]), else from [mediaType], else
  /// JPEG / MP4.
  static ({String extension, String mimeType}) typeOf(
    String url, {
    required bool isVideo,
    String? mediaType,
  }) {
    final kind = isVideo ? 'video/' : 'image/';
    final path = Uri.tryParse(url)?.path ?? url;
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final named = dot < 0 ? null : _types[name.substring(dot + 1).toLowerCase()];
    if (named != null && named.startsWith(kind)) {
      return (extension: name.substring(dot + 1).toLowerCase(), mimeType: named);
    }
    final type = mediaType != null && mediaType.startsWith(kind)
        ? mediaType
        : (isVideo ? 'video/mp4' : 'image/jpeg');
    final extension = _types.entries
            .where((e) => e.value == type)
            .map((e) => e.key)
            .firstOrNull ??
        (isVideo ? 'mp4' : 'jpg');
    return (extension: extension, mimeType: type);
  }

  /// The photo and video types a moment can be. First of a type is the
  /// extension it saves with.
  static const _types = {
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
  };

  /// What a failed save tells the user.
  /// Debug builds add the error itself, and log it.
  static String failureMessage(Object error) {
    debugPrint('GallerySaver: save failed: $error');
    final message =
        error is PlatformException && error.code == 'permission_denied'
            ? "Allow storage access to save to your gallery."
            : "Couldn't save to your gallery.";
    return kDebugMode ? '$message ($error)' : message;
  }
}
