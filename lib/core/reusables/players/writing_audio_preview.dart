import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// The Notes/Diary audio tile mirrors the web attachment card. Messages keep
/// their separate waveform player and conversation styling.
class WritingAudioPreview extends StatelessWidget {
  const WritingAudioPreview({super.key, required this.src, this.fileName});
  final String src;
  final String? fileName;

  @override
  Widget build(BuildContext context) =>
      _WritingAudioCard(key: ValueKey(src), src: src, fileName: fileName);
}

class _WritingAudioCard extends StatefulWidget {
  const _WritingAudioCard({super.key, required this.src, this.fileName});
  final String src;
  final String? fileName;
  @override
  State<_WritingAudioCard> createState() => _WritingAudioCardState();
}

class _WritingAudioCardState extends State<_WritingAudioCard>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  late Future<void> _prepared;
  Duration _duration = Duration.zero;
  bool _ready = false,
      _playing = false,
      _busy = false,
      _completed = false,
      _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.addAll([
      _player.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(
              () => _duration = duration.isNegative ? Duration.zero : duration);
        }
      }, onError: _failed),
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _playing = state == PlayerState.playing);
      }, onError: _failed),
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _completed = true;
          });
        }
      }, onError: _failed),
    ]);
    _prepared = _prepare();
  }

  void _failed(Object _) {
    if (mounted) {
      setState(() {
        _error = true;
        _ready = false;
        _playing = false;
      });
    }
  }

  Future<void> _prepare() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSourceUrl(widget.src);
      final duration = await _player.getDuration();
      if (mounted) {
        setState(() {
          _ready = true;
          _error = false;
          if (duration != null && !duration.isNegative) _duration = duration;
        });
      }
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _prepared;
      if (!mounted) return;
      if (!_ready) {
        _prepared = _prepare();
        await _prepared;
      }
      if (!mounted || !_ready) return;
      if (_playing) {
        await _player.pause();
      } else {
        if (_completed) {
          await _player.seek(Duration.zero);
          _completed = false;
        }
        await _player.resume();
      }
    } catch (error) {
      _failed(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) {
      unawaited(_player.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final name = widget.fileName?.trim().isNotEmpty == true
        ? widget.fileName!
        : 'Audio file';
    final duration =
        '${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}';
    return Container(
        key: const ValueKey('writing-audio-preview'),
        width: 150,
        height: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: p.surface2,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(5)),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filled(
                  tooltip: _error
                      ? 'Retry audio'
                      : _playing
                          ? 'Pause audio'
                          : 'Play audio',
                  onPressed: _busy ? null : _toggle,
                  style: IconButton.styleFrom(
                      backgroundColor: p.brand,
                      disabledBackgroundColor: p.brand,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(_playing ? Icons.pause : Icons.play_arrow,
                          size: 24))),
          const SizedBox(height: 16),
          Tooltip(
              message: name,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.text2, fontSize: 12, height: 1.4))),
          const SizedBox(height: 3),
          Text(_error ? 'Unable to play' : duration,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text3, fontSize: 12, height: 1.4)),
        ])));
  }
}
