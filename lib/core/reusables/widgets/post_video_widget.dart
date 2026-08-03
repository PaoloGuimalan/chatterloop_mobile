import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  /// True for a pending (not-yet-uploaded) video, whose "url" is actually
  /// a local file path - the file picker/camera never produces a network
  /// URL, only a path on-device.
  final bool isLocalFile;

  const VideoPlayerScreen(
      {super.key, required this.videoUrl, this.isLocalFile = false});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  late Future<void> initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();

    // Create and store the VideoPlayerController. The VideoPlayerController
    // offers several different constructors to play videos from assets, files,
    // or the internet.
    _controller = widget.isLocalFile
        ? VideoPlayerController.file(File(widget.videoUrl))
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

    initializeVideoPlayerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Ensure disposing of the VideoPlayerController to free up resources.
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // Use AspectRatio so the widget takes the exact shape of the video file
          return AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
              child: VideoPlayer(_controller),
            ),
          );
        } else {
          // Keep a minimum height placeholder while loading so it doesn't collapse to 0
          return const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
      },
    );
  }
}
