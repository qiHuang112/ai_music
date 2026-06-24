import 'package:flutter/material.dart';

class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.child,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.threshold = 72,
  });

  final Widget child;
  final Future<void> Function() onSwipeLeft;
  final Future<void> Function() onSwipeRight;
  final double threshold;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip> {
  double _dragDx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _dragDx = 0;
      },
      onHorizontalDragUpdate: (details) {
        _dragDx += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        final delta = _dragDx;
        _dragDx = 0;
        if (delta <= -widget.threshold) {
          widget.onSwipeLeft();
        } else if (delta >= widget.threshold) {
          widget.onSwipeRight();
        }
      },
      onHorizontalDragCancel: () {
        _dragDx = 0;
      },
      child: widget.child,
    );
  }
}
