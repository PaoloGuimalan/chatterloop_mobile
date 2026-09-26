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

class _ClipTrimPageState extends State<ClipTrimPage> {
  late final Duration _total = widget.source.duration ?? Duration.zero;
  late TrimRange _range = TrimRange(
      Duration.zero, _total > widget.maxSpan ? widget.maxSpan : _total);
  VideoPlayerController? _video;
  Duration? _at;
  bool _dragging = false;
  DateTime _lastSeek = DateTime(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Its own player: the feed's idle ones let their decoders go first.
    await SharedVideoControllers.releaseIdle();
    final video = VideoPlayerController.file(File(widget.source.path));
    try {
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      video.addListener(_onTick);
      await video.play();
      setState(() => _video = video);
    } catch (e) {
      debugPrint('ClipTrimPage: preview failed: $e');
      await video.dispose();
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_onTick);
    _video?.dispose();
    super.dispose();
  }

  /// Round and round the chosen part.
  void _onTick() {
    final video = _video;
    if (video == null || _dragging) return;
    final pos = video.value.position;
    if (mounted &&
        ((_at ?? Duration.zero) - pos).abs() > const Duration(milliseconds: 90)) {
      setState(() => _at = pos);
    }
    if (pos >= _range.end || video.value.isCompleted) {
      video.seekTo(_range.start).then((_) => video.play());
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
      video.seekTo(range.start != previous.start
          ? range.start
          : range.end - const Duration(milliseconds: 40));
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
                    onPressed: _range.length > Duration.zero
                        ? () => Navigator.pop(context, _range)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: video == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : AspectRatio(
                        aspectRatio: video.value.aspectRatio,
                        child: GestureDetector(
                          onTap: () => video.value.isPlaying
                              ? video.pause()
                              : video.play(),
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
                  _video?.pause();
                },
                onChanged: _changed,
                onChangeEnd: (range) {
                  _dragging = false;
                  _video?.seekTo(range.start).then((_) => _video?.play());
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
