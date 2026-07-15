// Waveform-style voice message player, redesigned to match webapp's
// VoiceMessagePlayer.tsx: a circular play/pause button, a row of bars that
// fill in as playback progresses and can be tapped/dragged to seek, and a
// duration readout. webapp decodes real amplitude data via the Web Audio
// API when it can (falling back to deterministic pseudo-random bars for
// long recordings or decode failures); this port always uses that
// deterministic fallback shape (seeded off the audio URL, so it's stable
// per message) rather than pulling in native PCM decoding just for the bar
// heights - visually it's the same "waveform" language, just not a literal
// amplitude reading.

import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

const int _barCount = 40;
const double _minBarHeight = 0.12;

List<double> _fallbackBars(String seed, int count) {
  int h = 0;
  for (final codeUnit in seed.codeUnits) {
    h = (h * 31 + codeUnit) & 0xFFFFFFFF;
  }
  final bars = <double>[];
  for (var i = 0; i < count; i++) {
    h = (h * 1103515245 + 12345) & 0xFFFFFFFF;
    bars.add(_minBarHeight + ((h % 1000) / 1000) * (1 - _minBarHeight));
  }
  return bars;
}

String _formatDuration(Duration d) {
  if (d.isNegative) return "0:00";
  final mins = d.inMinutes;
  final secs = d.inSeconds % 60;
  return "$mins:${secs.toString().padLeft(2, '0')}";
}

class VoiceMessagePlayer extends StatefulWidget {
  final String src;
  final bool isSender;
  final bool isLocalFile;

  const VoiceMessagePlayer(
      {super.key,
      required this.src,
      required this.isSender,
      this.isLocalFile = false});

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late final AudioPlayer _player;
  late final List<double> _bars;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  final GlobalKey _waveformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _bars = _fallbackBars(widget.src, _barCount);
    _player = AudioPlayer();
    if (widget.isLocalFile) {
      _player.setSourceDeviceFile(widget.src);
    } else {
      _player.setSourceUrl(widget.src);
    }
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _player.pause();
    } else {
      if (_duration > Duration.zero && _position >= _duration) {
        _player.seek(Duration.zero);
      }
      _player.resume();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _seekFromLocalDx(double dx) {
    final box = _waveformKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _duration <= Duration.zero) return;
    final fraction = (dx / box.size.width).clamp(0.0, 1.0);
    final target = _duration * fraction;
    _player.seek(target);
    setState(() => _position = target);
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final accent = p.brand;
    final bg = widget.isSender ? accent : p.surface;
    final border = widget.isSender ? accent : p.border;
    final textColor = widget.isSender ? Colors.white : p.text;
    final trackColor =
        widget.isSender ? Colors.white.withValues(alpha: 0.35) : p.border2;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 270),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(CLRadii.md),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _togglePlayback,
            customBorder: const CircleBorder(),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isSender
                    ? Colors.white.withValues(alpha: 0.22)
                    : accent,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTapDown: (details) =>
                      _seekFromLocalDx(details.localPosition.dx),
                  onHorizontalDragUpdate: (details) =>
                      _seekFromLocalDx(details.localPosition.dx),
                  child: SizedBox(
                    key: _waveformKey,
                    height: 28,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(_bars.length, (index) {
                        final barPosition = index / _bars.length;
                        final isPlayed = barPosition <= progress;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(
                              height: math.max(2, 28 * _bars[index]),
                              decoration: BoxDecoration(
                                color: isPlayed ? textColor : trackColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(
                      _position > Duration.zero ? _position : _duration),
                  style: TextStyle(fontSize: 11, color: textColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
