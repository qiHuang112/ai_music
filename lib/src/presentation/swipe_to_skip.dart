import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

/// Handles horizontal song changes without taking over vertical scrolling.
class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrevious,
    this.onDrag,
    this.onSettle,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// For a view that follows the finger: the distance dragged so far, then
  /// how it ended (-1 went to the next song, 1 to the previous, 0 neither).
  final ValueChanged<double>? onDrag;
  final ValueChanged<int>? onSettle;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip> {
  static const _minimumSwipeDistance = 48.0;

  /// A short, quick flick changes the song as well as a long drag.
  static const _flickVelocity = 320.0;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.delta.dx;
        widget.onDrag?.call(_dragDistance);
      },
      onHorizontalDragEnd: (details) {
        var direction = 0;
        final velocity = details.primaryVelocity ?? 0;
        if (_dragDistance <= -_minimumSwipeDistance ||
            (velocity <= -_flickVelocity && _dragDistance < 0)) {
          direction = -1;
          widget.onNext();
        } else if (_dragDistance >= _minimumSwipeDistance ||
            (velocity >= _flickVelocity && _dragDistance > 0)) {
          direction = 1;
          widget.onPrevious();
        }
        _dragDistance = 0;
        widget.onSettle?.call(direction);
      },
      onHorizontalDragCancel: () {
        _dragDistance = 0;
        widget.onSettle?.call(0);
      },
      child: widget.child,
    );
  }
}
