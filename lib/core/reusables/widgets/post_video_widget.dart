import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Uri videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  VideoPlayerScreenState createState() => VideoPlayerScreenState();
}

class VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;

  @override
  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.networkUrl(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
      }).catchError((e) {
        if (kDebugMode) {
          print('Error initializing video: $e');
        }
      });
  }

  @override
  void dispose() {
    super.dispose();
    _chewieController.dispose();
    _videoPlayerController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Player')),
      body: Center(
        child: Chewie(
          controller: _chewieController,
        ),
      ),
    );
  }
}
