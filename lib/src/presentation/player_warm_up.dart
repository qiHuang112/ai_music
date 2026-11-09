import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import 'music_home_page.dart' show playlistPageForWarmUp;
import 'player_page.dart';

/// Draws the player and a playlist page once, hidden under the app's opaque
/// backdrop, shortly after launch.
///
/// Android renders with Skia here (Impeller is off for the Mi 10 Pro's
/// driver), and Skia compiles each new shader the first time it is drawn: on
/// 77 the first player of a process spent 134 ms of a 184 ms frame compiling
/// 16 shaders, so the push visibly jumped, and the first playlist 97 ms in two
/// frames. Drawing them once while the app is idle moves that cost off the
/// tap; later opens compile nothing.
class PlayerWarmUp extends StatefulWidget {
  const PlayerWarmUp({
    super.key,
    required this.controller,
    this.delay = const Duration(milliseconds: 1500),
  });

  final MusicController controller;
  final Duration delay;

  /// Only where shaders compile at run time.
  static bool get wanted =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<PlayerWarmUp> createState() => _PlayerWarmUpState();
}

class _PlayerWarmUpState extends State<PlayerWarmUp> {
  StreamSubscription<Object?>? _items;
  Timer? _timer;
  bool _drawing = false, _done = false;

  @override
  void initState() {
    super.initState();
    // The record and its label are most of the work: wait for a song.
    final handler = widget.controller.audioHandler;
    if (handler.mediaItem.value != null) {
      _schedule();
    } else {
      _items = handler.mediaItem.listen((item) {
        if (item != null) _schedule();
      });
    }
  }

  void _schedule() {
    unawaited(_items?.cancel());
    _items = null;
    if (_timer != null || _done) return;
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _drawing = true);
      // Two frames: the record bakes its grooves into an image on the first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _drawing = false;
              _done = true;
            });
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_items?.cancel());
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_drawing) return const SizedBox.shrink();
    // Its own overlay for tooltips and menus: the app's lies inside the
    // navigator, above this.
    return Overlay(initialEntries: [OverlayEntry(builder: _pages)]);
  }

  Widget _pages(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: TickerMode(
            enabled: false,
            child: HeroMode(
              enabled: false,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  playlistPageForWarmUp(widget.controller),
                  PlayerPage(controller: widget.controller),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
