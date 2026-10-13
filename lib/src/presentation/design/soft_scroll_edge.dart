import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../app_theme.dart';

/// Gives every vertical list a soft top edge: once content has scrolled under
/// the bar above it, it melts away over a short distance instead of being cut
/// off on a hard line. At rest, with nothing scrolled, there is no fade.
class SoftEdgeScrollBehavior extends MaterialScrollBehavior {
  const SoftEdgeScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final wrapped = super.buildOverscrollIndicator(context, child, details);
    return axisDirectionToAxis(details.direction) == Axis.vertical
        ? _SoftTopEdge(child: wrapped)
        : wrapped;
  }
}

class _SoftTopEdge extends StatefulWidget {
  const _SoftTopEdge({required this.child});

  final Widget child;

  @override
  State<_SoftTopEdge> createState() => _SoftTopEdgeState();
}

class _SoftTopEdgeState extends State<_SoftTopEdge> {
  bool _scrolled = false;

  bool _track(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final scrolled = metrics.extentBefore > 1;
    if (scrolled == _scrolled) return false;
    void apply() {
      if (mounted && scrolled != _scrolled) {
        setState(() => _scrolled = scrolled);
      }
    }

    // Metrics can change while the frame is being laid out.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _track(n.metrics, n.depth),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _track(n.metrics, n.depth),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _scrolled ? 1 : 0),
            duration: MusicMotion.fast,
            builder: (context, amount, child) =>
                _EdgeFade(amount: amount, child: child),
            child: widget.child,
          ),
        ),
      );
}

class _EdgeFade extends SingleChildRenderObjectWidget {
  const _EdgeFade({required this.amount, super.child});

  final double amount;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEdgeFade(amount);

  @override
  void updateRenderObject(BuildContext context, _RenderEdgeFade renderObject) {
    renderObject.amount = amount;
  }
}

class _RenderEdgeFade extends RenderProxyBox {
  _RenderEdgeFade(this._amount);

  /// How far the content takes to melt away.
  static const _length = 30.0;

  double _amount;
  set amount(double value) {
    if (value == _amount) return;
    final wasOn = _amount > 0;
    _amount = value;
    if (wasOn != value > 0) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _amount > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // Untouched lists cost nothing: no layer until something has scrolled.
    if (_amount <= 0 || size.height <= _length) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    final mask = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    mask
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 1 - _amount),
          Colors.white.withValues(alpha: 1 - _amount * .55),
          Colors.white,
        ],
        stops: [0, _length * .45 / size.height, _length / size.height],
      ).createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(mask, super.paint, offset);
    layer = mask;
  }
}
