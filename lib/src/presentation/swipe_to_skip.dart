import 'package:flutter/material.dart';

/// Handles horizontal song changes without taking over vertical scrolling.
class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrevious,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip> {
  static const _minimumSwipeDistance = 48.0;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_dragDistance <= -_minimumSwipeDistance) {
          widget.onNext();
        } else if (_dragDistance >= _minimumSwipeDistance) {
          widget.onPrevious();
        }
        _dragDistance = 0;
      },
      onHorizontalDragCancel: () => _dragDistance = 0,
      child: widget.child,
    );
  }
}
