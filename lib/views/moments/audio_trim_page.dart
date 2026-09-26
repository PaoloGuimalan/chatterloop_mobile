import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/media/composition.dart';
import 'package:chatterloop_app/core/media/widgets/trim_bar.dart';
import 'package:flutter/material.dart';

/// Before a song joins an edit: the part of it to use - where it starts and
/// ends - no longer than [maxSpan], the room there is for it where it goes.
/// The chosen part plays round and round while it is picked, like
/// ClipTrimPage for a video.
///
/// Pops with the [TrimRange], or null when the song is not added.
class AudioTrimPage extends StatefulWidget {
  final String path;
  final String name;

  /// The whole file's length.
  final Duration length;
  final Duration maxSpan;

  const AudioTrimPage({
    super.key,
    required this.path,
    required this.name,
    required this.length,
    required this.maxSpan,
  });

  static Future<TrimRange?> open(
    BuildContext context, {
    required String path,
    required String name,
    required Duration length,
    required Duration maxSpan,
  }) =>
      Navigator.of(context, rootNavigator: true).push<TrimRange>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AudioTrimPage(
              path: path, name: name, length: length, maxSpan: maxSpan),
        ),
      );

  @override
  State<AudioTrimPage> createState() => _AudioTrimPageState();
}

class _AudioTrimPageState extends State<AudioTrimPage> {
  late TrimRange _range = TrimRange(Duration.zero,
      widget.length > widget.maxSpan ? widget.maxSpan : widget.length);
  final _player = AudioPlayer();
  StreamSubscription<Duration>? _position;
  StreamSubscription<void>? _done;
  Duration? _at;
  bool _playing = false;
  bool _dragging = false;
  DateTime _lastSeek = DateTime(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(DeviceFileSource(widget.path));
      _position = _player.onPositionChanged.listen(_onTick);
      _done = _player.onPlayerComplete.listen((_) => _fromTop());
      if (!mounted) return;
      await _fromTop();
    } catch (e) {
      debugPrint('AudioTrimPage: preview failed: $e');
    }
  }

  @override
  void dispose() {
    _position?.cancel();
    _done?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Round and round the chosen part.
  void _onTick(Duration pos) {
    if (!mounted || _dragging) return;
    setState(() => _at = pos);
    if (pos >= _range.end) _fromTop();
  }

  Future<void> _fromTop() async {
    await _player.seek(_range.start);
    await _player.resume();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      final at = _at ?? _range.start;
      if (at < _range.start || at >= _range.end) {
        await _fromTop();
      } else {
        await _player.resume();
        if (mounted) setState(() => _playing = true);
      }
    }
  }

  void _changed(TrimRange range) {
    final previous = _range;
    setState(() => _range = range);
    // Heard from the edge being moved (at most every 150ms).
    final now = DateTime.now();
    if (now.difference(_lastSeek) >= const Duration(milliseconds: 150)) {
      _lastSeek = now;
      final edge = range.start != previous.start
          ? range.start
          : range.end - const Duration(seconds: 1);
      _player.seek(edge < range.start ? range.start : edge);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    tooltip: "Don't add",
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text("Choose the part",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: CLType.screenTitle,
                            fontWeight: FontWeight.w800)),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D6B),
                        borderRadius: BorderRadius.circular(CLRadii.lg),
                      ),
                      child: const Icon(Icons.music_note_rounded,
                          size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        widget.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: CLType.sectionTitle,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 18),
                    IconButton.filled(
                      tooltip: _playing ? "Pause" : "Play",
                      onPressed: _toggle,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        fixedSize: const Size(56, 56),
                      ),
                      icon: Icon(_playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TrimBar(
                icon: Icons.music_note_rounded,
                title: "Use this much",
                total: widget.length,
                range: _range,
                maxSpan: widget.maxSpan,
                minSpan: const Duration(milliseconds: 500),
                position: _at,
                onChangeStart: (_) => _dragging = true,
                onChanged: _changed,
                onChangeEnd: (range) {
                  _dragging = false;
                  if (_playing) _fromTop();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                widget.length > widget.maxSpan
                    ? "Up to ${TrimBar.lengthLabel(widget.maxSpan)} fits where it goes."
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
