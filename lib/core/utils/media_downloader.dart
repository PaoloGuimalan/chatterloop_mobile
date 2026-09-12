// Saving a message attachment to the device, from inside the app.
//
// The alternative - handing the URL to url_launcher - opens the system
// browser, which means the download lands in Chrome's own flow rather than
// the app's. The user explicitly asked for the app to do it instead, so this
// downloads the bytes with the app's own HTTP client and then hands the
// finished file to the platform to file away.
//
// "Background" is meant literally: [download] is fire-and-forget and survives
// leaving the conversation, so the completion message goes through
// [clSnack]'s context-free messenger rather than the caller's context.
//
// Deliberately a PLAIN Dio, not ApiClient.instance.dio: attachments live on
// object storage (DigitalOcean Spaces, and legacy Google Cloud Storage), not
// on either backend. Sending this app's x-access-token / device-token /
// X-Nonce headers to a third-party host would hand credentials to somewhere
// that has no business seeing them, and the media URL needs none of them.

import 'dart:io';

import 'package:chatterloop_app/core/utils/app_messenger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The URL half of a message's `content`.
///
/// Same normalisation the players already do inline (see
/// message_content_widget's video/audio branches), in one place so the
/// download of an attachment and the playback of it can never disagree about
/// which URL they mean:
///
///   %%%   legacy "url%%%filename" encoding, Google Cloud Storage only
///   ###   a literal "###" inside a Spaces key, which has to be escaped back
///         into a percent-encoded "#" or everything after it reads as a
///         fragment and the request misses
///
/// Both are no-ops on a plain URL, which is what every current upload is.
String chatMediaUrl(String content) =>
    content.split("%%%")[0].replaceAll("###", "%23%23%23");

/// What to call the saved file.
///
/// Mirrors message_content_widget's `_fileNamePart` for where the name comes
/// from, and then does two things that only matter once it becomes a real
/// filename on disk: percent-decodes it (a Spaces key with an encoded space
/// would otherwise save as "my%20photo.jpg") and strips the characters
/// Android and iOS will not accept in one.
String chatMediaFileName(String content, {String fallback = "file"}) {
  if (content.contains("storage.googleapis.com")) {
    final parts = content.split("%%%");
    if (parts.length > 1 && parts[1].trim().isNotEmpty) {
      return _sanitizeFileName(parts[1], fallback);
    }
  }
  final url = chatMediaUrl(content);
  // Uri.parse rather than a raw split, so a query string
  // ("?X-Amz-Signature=...") never ends up in the filename.
  final path = Uri.tryParse(url)?.path ?? url;
  final segments = path.split("/").where((s) => s.isNotEmpty).toList();
  final last = segments.isEmpty ? "" : segments.last;
  return _sanitizeFileName(last, fallback);
}

String _sanitizeFileName(String raw, String fallback) {
  var name = raw.trim();
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {
    // Not valid percent-encoding - keep it exactly as it came.
  }
  name = name.replaceAll(RegExp('[\\\\/:*?"<>|]'), "_").trim();
  // Leaves room for the uniquifying " (1)" suffix, and stays well under every
  // filesystem's 255-BYTE limit once a multi-byte name is counted.
  if (name.length > 120) {
    final dot = name.lastIndexOf(".");
    final ext = dot > 0 && name.length - dot <= 12 ? name.substring(dot) : "";
    name = name.substring(0, 120 - ext.length) + ext;
  }
  return name.isEmpty ? fallback : name;
}

/// Extension -> content type, for the platform's file index.
///
/// Small on purpose. MediaStore only needs this to decide which collection a
/// download belongs to and which app opens it on tap; anything unrecognised is
/// correctly treated as an opaque blob. The authoritative type of a message's
/// attachment is the server's `messageType`, which callers pass in when they
/// have one - this is the fallback for when they do not.
String mimeTypeForFileName(String fileName) {
  final dot = fileName.lastIndexOf(".");
  if (dot < 0 || dot == fileName.length - 1) return "application/octet-stream";
  switch (fileName.substring(dot + 1).toLowerCase()) {
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "png":
      return "image/png";
    case "gif":
      return "image/gif";
    case "webp":
      return "image/webp";
    case "heic":
      return "image/heic";
    case "mp4":
      return "video/mp4";
    case "mov":
      return "video/quicktime";
    case "webm":
      return "video/webm";
    case "m4a":
      return "audio/mp4";
    case "mp3":
      return "audio/mpeg";
    case "wav":
      return "audio/wav";
    case "ogg":
      return "audio/ogg";
    case "pdf":
      return "application/pdf";
    case "txt":
      return "text/plain";
    case "csv":
      return "text/csv";
    case "json":
      return "application/json";
    case "zip":
      return "application/zip";
    case "doc":
      return "application/msword";
    case "docx":
      return "application/vnd.openxmlformats-officedocument"
          ".wordprocessingml.document";
    case "xls":
      return "application/vnd.ms-excel";
    case "xlsx":
      return "application/vnd.openxmlformats-officedocument"
          ".spreadsheetml.sheet";
    case "ppt":
      return "application/vnd.ms-powerpoint";
    case "pptx":
      return "application/vnd.openxmlformats-officedocument"
          ".presentationml.presentation";
    default:
      return "application/octet-stream";
  }
}

/// Downloads message attachments and files them away on the device.
///
/// A singleton because the progress it publishes has to be readable from
/// somewhere other than the widget that started the download: the same
/// attachment is shown in the bubble AND in the full-screen viewer, and both
/// should show the same spinner for the same file.
class MediaDownloader {
  MediaDownloader._();

  static final MediaDownloader instance = MediaDownloader._();

  /// Android's half of the save. iOS has no shared Downloads folder to insert
  /// into, so there it stays entirely in Dart (see [_saveToDevice]).
  static const MethodChannel _saver = MethodChannel('chatterloop/media_saver');

  final Dio _dio = Dio();

  /// Normalised URL -> 0..1, for every download running right now. A NEW map
  /// is published on each change rather than the existing one mutated, or
  /// ValueListenableBuilder never rebuilds.
  final ValueNotifier<Map<String, double>> progress =
      ValueNotifier<Map<String, double>>(const {});

  /// True while [content]'s download is in flight. Keyed on the normalised
  /// URL, so the bubble and the viewer agree even though one holds the raw
  /// content string and the other a resolved URL.
  bool isDownloading(String content) =>
      progress.value.containsKey(chatMediaUrl(content));

  /// 0..1 for a running download, or null when nothing is running for it.
  /// 0 also means "started, but the size is unknown" - see [download].
  double? progressOf(String content) => progress.value[chatMediaUrl(content)];

  /// Fetches [content] and saves it. Safe to call and forget: every failure
  /// ends in a message rather than an exception, and asking for a download
  /// that is already running is a no-op rather than a second copy.
  ///
  /// [mimeType] is the server's `messageType` when the caller has one; it
  /// beats guessing from the extension, because a storage key does not always
  /// carry one.
  Future<void> download(String content, {String? mimeType}) async {
    final url = chatMediaUrl(content);
    if (url.isEmpty) return;
    if (progress.value.containsKey(url)) {
      clSnack("Already downloading");
      return;
    }

    final fileName = chatMediaFileName(content);
    final type = (mimeType != null && mimeType.contains("/"))
        ? mimeType
        : mimeTypeForFileName(fileName);

    _publish(url, 0);
    File? staged;
    try {
      // Staged in the cache first, then handed over whole. Streaming straight
      // into the destination would leave a half-written file in the user's
      // Downloads if the connection dropped - and on Android it cannot be done
      // at all, because the destination is a MediaStore uri rather than a path
      // this process can write through dart:io.
      final tempDir = await getTemporaryDirectory();
      final stagedPath = "${tempDir.path}/cl_download_"
          "${DateTime.now().microsecondsSinceEpoch}_$fileName";
      await _dio.download(
        url,
        stagedPath,
        onReceiveProgress: (received, total) {
          // total is -1 whenever the response carries no Content-Length;
          // leaving the entry at 0 keeps the UI on its indeterminate spinner
          // instead of showing a percentage it does not actually know.
          if (total > 0) _publish(url, received / total);
        },
      );
      staged = File(stagedPath);

      final location = await _saveToDevice(staged, fileName, type);
      clSnack("Saved $fileName to $location");
    } on DioException catch (_) {
      clSnack("Couldn't download $fileName. Check your connection.");
    } on PlatformException catch (e) {
      clSnack(e.code == "permission_denied"
          ? "Storage permission is needed to save files."
          : "Couldn't save $fileName to this device.");
    } catch (_) {
      clSnack("Couldn't save $fileName to this device.");
    } finally {
      // The staged copy has been handed over, or the attempt failed - either
      // way this process is done with it. Best-effort: the cache directory is
      // the OS's to reclaim.
      if (staged != null) {
        try {
          if (await staged.exists()) await staged.delete();
        } catch (_) {}
      }
      _clear(url);
    }
  }

  /// Files [staged] away where the platform expects downloads to live, and
  /// returns a short human-readable location for the confirmation message.
  Future<String> _saveToDevice(
      File staged, String fileName, String mimeType) async {
    if (Platform.isAndroid) {
      // MediaStore, via MediaSaver.kt - the only way to put a file into the
      // SHARED Downloads collection on API 29+ without all-files access.
      await _saver.invokeMethod<String>("saveToDownloads", {
        "path": staged.path,
        "fileName": fileName,
        "mimeType": mimeType,
      });
      return "Downloads";
    }

    // iOS (and anything else): there is no shared Downloads folder, so the
    // app's own Documents directory is the destination. Info.plist declares
    // UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace, which is what
    // makes that directory appear as "Chatterloop" under On My iPhone in the
    // Files app - i.e. somewhere the user can actually reach it.
    final documents = await getApplicationDocumentsDirectory();
    final target = Directory("${documents.path}/Downloads");
    if (!await target.exists()) await target.create(recursive: true);
    final destination = await _uniquePath(target.path, fileName);
    await staged.copy(destination);
    return "Files - Chatterloop";
  }

  /// "photo.jpg", then "photo (1).jpg", ... - downloading the same attachment
  /// twice should not silently overwrite the first copy.
  Future<String> _uniquePath(String directory, String fileName) async {
    final dot = fileName.lastIndexOf(".");
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : "";
    var candidate = "$directory/$fileName";
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = "$directory/$stem ($counter)$ext";
      counter++;
    }
    return candidate;
  }

  void _publish(String url, double value) {
    progress.value = {...progress.value, url: value.clamp(0, 1).toDouble()};
  }

  void _clear(String url) {
    progress.value = {...progress.value}..remove(url);
  }
}
