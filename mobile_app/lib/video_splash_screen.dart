import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';

class VideoSplashScreen extends StatefulWidget {
  const VideoSplashScreen({super.key});

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    // Safety timer: force navigation after 1.8 seconds max (1.5s video + init buffer)
    Timer(const Duration(milliseconds: 1800), _navigateToNext);

    _controller = VideoPlayerController.asset('assets/videos/splash_video.mp4')
      ..initialize().then((_) {
        if (!mounted) return;

        // Target finishing in ~1500ms (1.5s)
        final durationMs = _controller.value.duration.inMilliseconds;
        double speed = 1.0;
        if (durationMs > 1500) {
          speed = durationMs / 1500;
        }

        // Ensure speed is at least 1.0x (don't slow down short videos)
        // Cap speed at 5.0x for sanity
        _controller.setPlaybackSpeed(speed > 5.0 ? 5.0 : speed);

        setState(() {
          _initialized = true;
        });
        _controller.play();
        _controller.setLooping(false);
      });

    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        _navigateToNext();
      }
    });
  }

  bool _navigated = false;
  void _navigateToNext() {
    if (mounted && !_navigated) {
      _navigated = true;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _initialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const CircularProgressIndicator(color: Color(0xFF00B9F1)),
      ),
    );
  }
}
