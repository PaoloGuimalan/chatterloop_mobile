/// Runs edits through the bundled ffmpeg: inspects picked files, renders a
/// [Composition] to an MP4 plus its poster JPEG.
///
/// Renders run ONE at a time, in the order asked (a second render waits for
/// the first) - encoders are a scarce device resource and two encodes at once
/// only make both slow. Each render gets its own temp folder, deleted by
/// [RenderResult.dispose] once the files are uploaded (or given up on).
library;

import 'dart:async';
import 'dart:io';

import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/encoding_profile.dart';
import 'package:chatterloop_app/core/media/ffmpeg_command.dart';
import 'package:chatterloop_app/core/media/media_info.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/statistics.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A render or probe that failed. [message] is safe to show; [logs] (the tail
/// of ffmpeg's output) is for diagnosis only.
class MediaEngineException implements Exception {
  final String message;
  final String? logs;

  const MediaEngineException(this.message, {this.logs});

  @override
  String toString() => 'MediaEngineException: $message';
}

/// The render was cancelled - not a failure to report.
class RenderCancelled implements Exception {
  const RenderCancelled();

  @override
  String toString() => 'RenderCancelled';
}

/// A finished render: the files, and what they are.
class RenderResult {
  final String videoPath;
  final String posterPath;

  /// The video's frame size - also the poster's.
  final int width;
  final int height;
  final Duration duration;

  /// Whether the video carries real sound (every output has an audio track,
  /// silent when there is none).
  final bool hasSound;

  final Directory _workspace;

  const RenderResult._({
    required this.videoPath,
    required this.posterPath,
    required this.width,
    required this.height,
    required this.duration,
    required this.hasSound,
    required Directory workspace,
  }) : _workspace = workspace;

  /// Deletes the files. Call once they are uploaded, or no longer wanted.
  Future<void> dispose() => _deleteQuietly(_workspace);
}

/// A render that was asked for: its progress, its outcome, and a way to stop
/// it (queued or running).
class RenderJob {
  final Composition composition;
  final EncodingProfile profile;
  final List<H264Encoder> _encoders;

  final ValueNotifier<double> _progress = ValueNotifier(0);
  final Completer<RenderResult> _outcome = Completer();
  bool _started = false;
  bool _cancelled = false;
  int? _sessionId;

  RenderJob._(this.composition, this.profile, this._encoders) {
    // A render nobody awaits (the screen was left) must not surface its
    // failure or cancellation as an uncaught error. Listeners of [result]
    // still get it.
    _outcome.future.ignore();
  }

  /// 0..1 - the video encode is 0..0.97, the poster the rest.
  ValueListenable<double> get progress => _progress;

  /// Completes with the files, or with a [RenderCancelled] /
  /// [MediaEngineException] error.
  Future<RenderResult> get result => _outcome.future;

  bool get isCancelled => _cancelled;

  /// Stops the render. A queued one never starts; a running one is killed
  /// and its files deleted. No effect once it has finished.
  Future<void> cancel() async {
    if (_outcome.isCompleted || _cancelled) return;
    _cancelled = true;
    if (!_started) {
      // Still queued: settle now rather than when its turn comes.
      _outcome.completeError(const RenderCancelled());
      return;
    }
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  void _report(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped > _progress.value) _progress.value = clamped;
  }
}

class MediaEngine {
  MediaEngine._();

  static final MediaEngine instance = MediaEngine._();

  /// The video encode's share of [RenderJob.progress]; the poster is the
  /// rest.
  static const _encodeShare = 0.97;

  /// How much of ffmpeg's log a failure keeps.
  static const _logTail = 4000;

  Future<void> _queue = Future.value();
  Future<Directory>? _root;
  var _workspaceCount = 0;

  /// What [path] is - size, length, rotation, streams.
  ///
  /// Throws a [MediaEngineException] when ffprobe can't read it (not a media
  /// file, unsupported, unreadable).
  Future<MediaInfo> probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final properties = session.getMediaInformation()?.getAllProperties();
    if (properties == null) {
      throw MediaEngineException(
        "Couldn't read this file",
        logs: _tail(await session.getAllLogsAsString()),
      );
    }
    return MediaInfo.fromProbeJson(path, properties);
  }

  /// Queues [composition] for rendering per [profile] (Moments by default).
  ///
  /// [encoders] overrides the per-platform H.264 encoder list, tried in
  /// order - the next only when one fails.
  RenderJob render(
    Composition composition, {
    EncodingProfile profile = EncodingProfile.moment,
    List<H264Encoder>? encoders,
  }) {
    final job = RenderJob._(
      composition,
      profile,
      encoders ?? H264Encoder.candidatesFor(defaultTargetPlatform),
    );
    // _run never throws (it completes the job instead), so one failed render
    // can't stall the ones queued behind it.
    _queue = _queue.then((_) => _run(job));
    return job;
  }

  Future<void> _run(RenderJob job) async {
    // Cancelled while queued - already settled by cancel().
    if (job._cancelled) return;
    job._started = true;
    Directory? workspace;
    try {
      workspace = await _newWorkspace();
      final videoPath = '${workspace.path}/moment.mp4';
      final posterPath = '${workspace.path}/poster.jpg';

      RenderCommand? rendered;
      String? failureLogs;
      for (final encoder in job._encoders) {
        RenderCommand build({required bool qpCeilings}) => buildRenderCommand(
              composition: job.composition,
              profile: job.profile,
              encoder: encoder,
              outputPath: videoPath,
              qpCeilings: qpCeilings,
            );
        var command = build(qpCeilings: true);
        var outcome = await _encode(job, command);
        if (!outcome.ok && command.usesQpCeilings) {
          // An encoder that refuses the QP ceilings may still take the
          // plain bitrate.
          failureLogs = outcome.logs;
          debugPrint('MediaEngine: ${encoder.name} refused the QP ceilings');
          command = build(qpCeilings: false);
          outcome = await _encode(job, command);
        } else if (outcome.ok &&
            command.usesQpCeilings &&
            await _overLimit(job.profile, videoPath)) {
          // The ceilings took a long, busy video past the upload cap; the
          // bitrate alone is chosen to land under it.
          debugPrint('MediaEngine: too big with QP ceilings, redoing without');
          command = build(qpCeilings: false);
          outcome = await _encode(job, command);
        }
        if (outcome.ok) {
          rendered = command;
          break;
        }
        failureLogs = outcome.logs;
        debugPrint(
            'MediaEngine: ${encoder.name} (${encoder.pixelFormat}) failed');
      }
      if (rendered == null) {
        throw MediaEngineException("Couldn't process this video",
            logs: failureLogs);
      }
      if (await _overLimit(job.profile, videoPath)) {
        throw const MediaEngineException(
            'This came out too big to share. Try a shorter part.');
      }

      final poster = await _execute(
        job,
        buildPosterCommand(
          videoPath: videoPath,
          posterPath: posterPath,
          profile: job.profile,
        ),
      );
      if (poster.cancelled) throw const RenderCancelled();
      if (!poster.ok) {
        throw MediaEngineException("Couldn't process this video",
            logs: poster.logs);
      }

      job._report(1);
      job._outcome.complete(RenderResult._(
        videoPath: videoPath,
        posterPath: posterPath,
        width: job.profile.width,
        height: job.profile.height,
        duration: rendered.duration,
        hasSound: rendered.hasSound,
        workspace: workspace,
      ));
    } catch (error, stack) {
      if (workspace != null) await _deleteQuietly(workspace);
      final reported = job._cancelled ? const RenderCancelled() : error;
      job._outcome.completeError(
        reported is RenderCancelled || reported is MediaEngineException
            ? reported
            : MediaEngineException("Couldn't process this video",
                logs: '$error'),
        stack,
      );
    }
  }

  /// Runs one video encode for [job], its progress from 0 - a retry starts
  /// the bar over rather than sitting at the last one's end.
  Future<_Outcome> _encode(RenderJob job, RenderCommand command) async {
    job._progress.value = 0;
    final totalMs = command.duration.inMilliseconds;
    final outcome = await _execute(
      job,
      command.arguments,
      onTime: (ms) => job._report(ms / totalMs * _encodeShare),
    );
    if (outcome.cancelled) throw const RenderCancelled();
    return outcome;
  }

  /// Whether the file at [path] is past what [profile] allows.
  static Future<bool> _overLimit(EncodingProfile profile, String path) async {
    final limit = profile.maxBytes;
    return limit != null && await File(path).length() > limit;
  }

  /// Runs one ffmpeg command for [job], reporting output time (ms) to
  /// [onTime].
  Future<_Outcome> _execute(
    RenderJob job,
    List<String> arguments, {
    void Function(int ms)? onTime,
  }) async {
    if (job._cancelled) return const _Outcome.cancelled();
    final done = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      done.complete,
      null,
      onTime == null ? null : (Statistics s) => onTime(s.getTime()),
    );
    job._sessionId = session.getSessionId();
    // Cancelled between the start call and knowing the session id.
    if (job._cancelled) await FFmpegKit.cancel(job._sessionId);
    final finished = await done.future;
    job._sessionId = null;

    final code = await finished.getReturnCode();
    if (ReturnCode.isCancel(code) || job._cancelled) {
      return const _Outcome.cancelled();
    }
    if (ReturnCode.isSuccess(code)) return const _Outcome.ok();
    return _Outcome.failed(_tail(await finished.getAllLogsAsString()));
  }

  /// A fresh temp folder for an editor's own files (a prepared photo, say).
  /// The caller deletes it when the editor closes.
  Future<Directory> createWorkspace() => _newWorkspace();

  /// A fresh folder for one render. The first call in an app run clears
  /// what earlier runs left behind (a render killed with the app).
  Future<Directory> _newWorkspace() async {
    final root = await (_root ??= _prepareRoot());
    final dir = Directory(
        '${root.path}/${DateTime.now().millisecondsSinceEpoch}-${_workspaceCount++}');
    return dir.create(recursive: true);
  }

  Future<Directory> _prepareRoot() async {
    final root =
        Directory('${(await getTemporaryDirectory()).path}/media_engine');
    await _deleteQuietly(root);
    return root.create(recursive: true);
  }

  static String? _tail(String? logs) {
    if (logs == null || logs.length <= _logTail) return logs;
    return logs.substring(logs.length - _logTail);
  }
}

class _Outcome {
  final bool ok;
  final bool cancelled;
  final String? logs;

  const _Outcome.ok()
      : ok = true,
        cancelled = false,
        logs = null;
  const _Outcome.cancelled()
      : ok = false,
        cancelled = true,
        logs = null;
  const _Outcome.failed(this.logs)
      : ok = false,
        cancelled = false;
}

Future<void> _deleteQuietly(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {
    // Temp files; the OS clears the temp folder eventually.
  }
}
