import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef SongRowAnchor = Widget Function(int index, String id, Widget child);

/// Locates a song once on opening, while keeping long, variable-height lists lazy.
class InitialSongScroll extends StatefulWidget {
  const InitialSongScroll({
    super.key,
    required this.targetIndex,
    required this.builder,
    this.ready = true,
  });

  final int? targetIndex;
  final bool ready;
  final Widget Function(BuildContext, ScrollController, SongRowAnchor) builder;

  @override
  State<InitialSongScroll> createState() => _InitialSongScrollState();
}

class _InitialSongScrollState extends State<InitialSongScroll> {
  final _controller = ScrollController(keepScrollOffset: false);
  final _rows = <String, ({int index, GlobalKey key})>{};
  bool _done = false;
  bool _scheduled = false;
  int? _target;
  int _attempts = 0;
  Animation<double>? _entrance;
  double? _origin;
  double? _destination;
  bool _revealed = false;
  bool _cancelled = false;
  bool _animationQueued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entrance = ModalRoute.of(context)?.animation;
    if (identical(entrance, _entrance)) return;
    _entrance?.removeStatusListener(_onEntrance);
    _entrance = entrance;
    _entrance?.addStatusListener(_onEntrance);
  }

  void _onEntrance(AnimationStatus status) {
    if (status == AnimationStatus.completed) _animate();
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _cancelled = true;
      _done = true;
    }
  }

  void _animate() {
    if (_destination == null ||
        _cancelled ||
        _animationQueued ||
        (_entrance != null && !_entrance!.isCompleted)) {
      return;
    }
    _animationQueued = true;
    // Start after the prepared rows have painted and the page is fully open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cancelled || !_controller.hasClients) return;
      unawaited(
        _controller.animateTo(
          _destination!,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _reveal() {
    if (!_revealed) setState(() => _revealed = true);
  }

  void _finish(RenderBox box) {
    _done = true;
    final position = _controller.position;
    final viewport = RenderAbstractViewport.of(box);
    // A song in full view where the list opened stays where it is: nudging
    // the list a few points as the page settles reads as a jolt of the whole
    // page. (A far song may already be on screen here after the estimating
    // jumps; that one still rolls in from the opening position.)
    final media = MediaQuery.of(context);
    final origin = _origin ?? position.pixels;
    final top = viewport.getOffsetToReveal(box, 0).offset - origin;
    final clearTop = media.padding.top + kToolbarHeight + 8;
    final clearBottom = position.viewportDimension - media.padding.bottom;
    if (top >= clearTop && top + box.size.height <= clearBottom) {
      if (position.pixels != origin) position.jumpTo(origin);
      _reveal();
      return;
    }
    // Leave room for the pinned playlist toolbar above the song.
    final destination = viewport
        .getOffsetToReveal(box, .35)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(destination);
    } else {
      _destination = destination;
      final origin = _origin ?? 0;
      final distance = position.viewportDimension * .75;
      // Long lists roll through the last screen near the song in the same
      // short duration, without flashing the intermediate seek positions.
      final start = destination > origin
          ? (destination - distance).clamp(origin, destination)
          : (destination + distance).clamp(destination, origin);
      position.jumpTo(start);
      _animate();
    }
    _reveal();
  }

  Widget _anchor(int index, String id, Widget child) {
    final key = _rows[id]?.key ?? GlobalKey();
    _rows[id] = (index: index, key: key);
    return KeyedSubtree(key: key, child: child);
  }

  void _schedule() {
    if (_done || _scheduled || !widget.ready) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && !_done) _locate();
    });
  }

  void _locate() {
    _target ??= widget.targetIndex;
    final target = _target;
    if (target == null || target < 0 || ++_attempts > 24) {
      _done = true;
      _reveal();
      return;
    }
    if (!_controller.hasClients || !_controller.position.hasContentDimensions) {
      _schedule();
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final position = _controller.position;
    _origin ??= position.pixels;
    final measured = <({int index, double offset, RenderBox box})>[];
    for (final row in _rows.values) {
      final box = row.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (row.index == target) {
        _finish(box);
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport != null) {
        measured.add((
          index: row.index,
          offset: viewport.getOffsetToReveal(box, 0).offset,
          box: box,
        ));
      }
    }
    if (measured.isNotEmpty) {
      measured.sort((a, b) => a.index.compareTo(b.index));
      final first = measured.first;
      final last = measured.last;
      final extent = first.index == last.index
          ? first.box.size.height
          : (last.offset - first.offset) / (last.index - first.index);
      final nearest = target < first.index ? first : last;
      final offset =
          nearest.offset +
          (target - nearest.index) * extent -
          position.viewportDimension * .35;
      position.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    // A far jump lays out a new lazy window and refines its extent estimate.
    _schedule();
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_onEntrance);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return NotificationListener<ScrollStartNotification>(
      onNotification: (event) {
        if (event.depth == 0 && event.dragDetails != null) {
          _cancelled = true;
          _done = true;
          _reveal();
        }
        return false;
      },
      child: Opacity(
        opacity: _revealed || !widget.ready || (widget.targetIndex ?? -1) < 0
            ? 1
            : 0,
        child: widget.builder(context, _controller, _anchor),
      ),
    );
  }
}
