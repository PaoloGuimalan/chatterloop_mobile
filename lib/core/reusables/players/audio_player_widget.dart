// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;

  const AudioPlayerWidget({super.key, required this.audioUrl});

  @override
  AudioPlayerWidgetState createState() => AudioPlayerWidgetState();
}

class AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _volume = 1.0;
  bool _showVolumeControl = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _totalDuration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _currentPosition = position;
      });

      // Stop playing if the audio reaches the end
      if (_currentPosition >= _totalDuration) {
        setState(() {
          _isPlaying = false;
          _currentPosition = _totalDuration; // Fix current position at the end
        });
      }
    });

    _audioPlayer.setSourceUrl(widget.audioUrl);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      if (_currentPosition >= _totalDuration) {
        // Reset the audio and start from the beginning
        _audioPlayer.seek(Duration.zero);
        _audioPlayer
            .play(UrlSource(widget.audioUrl)); // Play again from the beginning
        _currentPosition = Duration.zero;
      } else {
        _audioPlayer.resume();
      }
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _onSliderChanged(double value) {
    // Ensure the value is within bounds
    final newPosition = Duration(seconds: value.toInt());
    if (newPosition <= _totalDuration) {
      _audioPlayer.seek(newPosition);
      setState(() {
        _currentPosition = newPosition;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlayPause,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF1C7DEF),
                      inactiveTrackColor:
                          const Color(0xFF1C7DEF).withOpacity(0.3),
                      thumbColor: const Color(0xFF1C7DEF),
                      overlayColor: const Color(0xFF1C7DEF).withOpacity(0.2),
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius:
                            8.0, // Adjust this value to make the thumb smaller
                      )),
                  child: Slider(
                    value: _currentPosition.inSeconds.toDouble(),
                    max: _totalDuration.inSeconds.toDouble(),
                    onChanged: _onSliderChanged,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.volume_up),
                onPressed: () {
                  setState(() {
                    _showVolumeControl = !_showVolumeControl;
                  });
                },
              ),
            ],
          ),
          if (_showVolumeControl)
            Padding(
              padding: EdgeInsets.only(left: 30, right: 30),
              child: Row(
                children: [
                  Text(
                    "${_currentPosition.inMinutes}:${(_currentPosition.inSeconds % 60).toString().padLeft(2, '0')}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  Expanded(
                      child: SizedBox(
                    height: 0,
                  )),
                  Text(
                    "${_totalDuration.inMinutes}:${(_totalDuration.inSeconds % 60).toString().padLeft(2, '0')}",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          if (_showVolumeControl)
            Row(
              children: [
                const Icon(Icons.volume_down, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF1C7DEF),
                        inactiveTrackColor:
                            const Color(0xFF1C7DEF).withOpacity(0.3),
                        thumbColor: const Color(0xFF1C7DEF),
                        overlayColor: const Color(0xFF1C7DEF).withOpacity(0.2),
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius:
                              8.0, // Adjust this value to make the thumb smaller
                        )),
                    child: Slider(
                      value: _volume,
                      max: 1.0,
                      min: 0.0,
                      onChanged: (value) {
                        setState(() {
                          _volume = value;
                          _audioPlayer.setVolume(_volume);
                        });
                      },
                    ),
                  ),
                ),
                const Icon(Icons.volume_up, size: 18),
              ],
            ),
        ],
      ),
    );
  }
}
