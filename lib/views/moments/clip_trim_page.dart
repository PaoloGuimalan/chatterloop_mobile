import 'dart:async';
import 'dart:io';

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:chatterloop_app/core/reusables/widgets/post_video_widget.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Before a video joins an edit: the part of it to use - no longer than
/// [maxSpan], the room the edit has left. The chosen part plays round and
/// round while it is picked.
///
/// Pops with the [TrimRange], or null when the video is skipped.
class ClipTrimPage extends StatefulWidget {
  final MediaSource source;
  final Duration maxSpan;

  /// "2 of 3", when several videos were picked at once.
  final String? step;

  const ClipTrimPage({
    super.key,
    required this.source,
    required this.maxSpan,
    this.step,
  });

  static Future<TrimRange?> open(
    BuildContext context, {
    required MediaSource source,
    required Duration maxSpan,
    String? step,
  }) =>
      Navigator.of(context, rootNavigator: true).push<TrimRange>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              ClipTrimPage(source: source, maxSpan: maxSpan, step: step),
        ),
      );

  @override
  State<ClipTrimPage> createState() => _ClipTrimPageState();
}

class _ClipTrimPageState extends State<ClipTrimPage>
    with WidgetsBindingObserver {
  static const _previewTimeout = Duration(seconds: 15);
  late final Duration _total = widget.source.duration ?? Duration.zero;
  late TrimRange _range = TrimRange(
      Duration.zero, _total > widget.maxSpan ? widget.maxSpan : _total);
  VideoPlayerController? _video;
  final _owned = <VideoPlayerController>{};
  Future<void>? _releasing;
  bool _loading = false;
  bool _failed = false;
  bool _loopSeeking = false;
  bool _resumeAfterLifecycle = false;
  int _generation = 0;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  Duration? _at;
  bool _dragging = false;
  DateTime _lastSeek = DateTime(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    VideoPlayerController? video;
    try {
      await _releasing?.timeout(_previewTimeout);
      // Its own player: the feed's idle ones let their decoders go first.
      await SharedVideoControllers.releaseIdle().timeout(_previewTimeout);
      if (!mounted || generation != _generation) return;
      video = VideoPlayerController.file(File(widget.source.path));
      _owned.add(video);
      await video.initialize().timeout(_previewTimeout);
      if (!mounted || generation != _generation) {
        await _release(video);
        return;
      }
      _video = video;
      video.addListener(_onTick);
      if (_foreground) {
        await video.play().timeout(_previewTimeout);
      } else {
        _resumeAfterLifecycle = true;
      }
      if (!mounted || generation != _generation) {
        await _release(video);
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('ClipTrimPage: preview failed: $e');
      if (mounted && generation == _generation) {
        setState(() {
          _video = null;
          _loading = false;
          _failed = true;
        });
      }
      if (video != null) await _release(video);
    }
  }

  Future<void> _release(VideoPlayerController video) {
    if (!_owned.remove(video)) return Future<void>.value();
    video.removeListener(_onTick);
    return _releasing = _disposeController(video);
  }

  Future<void> _disposeController(VideoPlayerController video) async {
    try {
      await video.dispose();
    } catch (e) {
      debugPrint('ClipTrimPage: preview release failed: $e');
    }
  }

  Future<void> _action(
      VideoPlayerController video, Future<void> Function() action) async {
    if (!mounted || _video != video || !_owned.contains(video)) return;
    try {
      await action().timeout(_previewTimeout);
    } catch (e) {
      if (!mounted || _video != video) return;
      setState(() {
        _video = null;
        _failed = true;
        _loading = false;
      });
      await _release(video);
    }
  }

  Future<void> _playFrom(Duration start) async {
    final video = _video;
    if (video == null || _loopSeeking) return;
    _loopSeeking = true;
    try {
      await _action(video, () async {
        await video.seekTo(start);
        if (mounted && _video == video && !_dragging && _foreground) {
          await video.play();
        }
      });
    } finally {
      _loopSeeking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final video = _video;
    if (video == null) return;
    if (state == AppLifecycleState.resumed) {
      if (_resumeAfterLifecycle && !_dragging) {
        _resumeAfterLifecycle = false;
        unawaited(_action(video, video.play));
      }
    } else if (video.value.isPlaying) {
      _resumeAfterLifecycle = true;
      unawaited(_action(video, video.pause));
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _video = null;
    for (final video in _owned.toList()) {
      unawaited(_release(video));
    }
    super.dispose();
  }

  /// Round and round the chosen part.
  void _onTick() {
    final video = _video;
    if (video == null || _dragging) return;
    if (video.value.hasError) {
      setState(() {
        _video = null;
        _failed = true;
        _loading = false;
      });
      unawaited(_release(video));
      return;
    }
    final pos = video.value.position;
    if (mounted &&
        ((_at ?? Duration.zero) - pos).abs() >
            const Duration(milliseconds: 90)) {
      setState(() => _at = pos);
    }
    if (pos >= _range.end || video.value.isCompleted) {
      unawaited(_playFrom(_range.start));
    }
  }

  void _changed(TrimRange range) {
    final previous = _range;
    setState(() => _range = range);
    // The frame at the edge being moved (at most every 80ms).
    final now = DateTime.now();
    final video = _video;
    if (video != null &&
        now.difference(_lastSeek) >= const Duration(milliseconds: 80)) {
      _lastSeek = now;
      unawaited(_action(
          video,
          () => video.seekTo(range.start != previous.start
              ? range.start
              : range.end - const Duration(milliseconds: 40))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "Skip this video",
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Choose the part",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: CLType.screenTitle,
                                fontWeight: FontWeight.w800)),
                        if (widget.step != null)
                          Text("Video ${widget.step}",
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: CLType.caption)),
                      ],
                    ),
                  ),
                  CLBtn(
                    label: "Add",
                    size: CLBtnSize.sm,
                    onPressed: !_failed &&
                            !_loading &&
                            video != null &&
                            _range.length > Duration.zero
                        ? () => Navigator.pop(context, _range)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _failed
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white70, size: 40),
                        const SizedBox(height: 12),
                        const Text('Could not preview this video.',
                            style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 12),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                              onPressed: _load, child: const Text('Retry')),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Skip')),
                        ]),
                      ])
                    : video == null || _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(
                            aspectRatio: video.value.aspectRatio,
                            child: GestureDetector(
                              onTap: () => unawaited(_action(
                                  video,
                                  video.value.isPlaying
                                      ? video.pause
                                      : video.play)),
                              child: VideoPlayer(video),
                            ),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TrimBar(
                icon: Icons.videocam_outlined,
                title: "Use this much",
                total: _total,
                range: _range,
                maxSpan: widget.maxSpan,
                minSpan: const Duration(milliseconds: 500),
                position: _at,
                onChangeStart: (_) {
                  _dragging = true;
                  final video = _video;
                  if (video != null) unawaited(_action(video, video.pause));
                },
                onChanged: _changed,
                onChangeEnd: (range) {
                  _dragging = false;
                  unawaited(_playFrom(range.start));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                _total > widget.maxSpan
                    ? "Up to ${TrimBar.lengthLabel(widget.maxSpan)} fits in this moment."
                    : "Drag the ends to keep just the part you want.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: CLType.caption),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
