import 'package:flutter/material.dart';

import '../application/performance_monitor.dart';

/// Above the Navigator; only this small panel rebuilds for new samples.
class PerformanceOverlayPanel extends StatefulWidget {
  const PerformanceOverlayPanel({super.key, required this.monitor});
  final PerformanceMonitor monitor;

  @override
  State<PerformanceOverlayPanel> createState() =>
      _PerformanceOverlayPanelState();
}

class _PerformanceOverlayPanelState extends State<PerformanceOverlayPanel> {
  Offset? _position;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.monitor,
    builder: (context, _) {
      if (!widget.monitor.enabled) return const SizedBox.shrink();
      final media = MediaQuery.of(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - media.padding.horizontal - 12)
              .clamp(0.0, 128.0);
          const height = 72.0;
          final minX = media.padding.left + 6;
          final minY = media.padding.top + 6;
          final maxX = (constraints.maxWidth - media.padding.right - width - 6)
              .clamp(minX, double.infinity);
          final maxY =
              (constraints.maxHeight -
                      media.viewInsets.bottom -
                      media.padding.bottom -
                      height -
                      6)
                  .clamp(minY, double.infinity);
          final position = _position ?? Offset(maxX, minY);
          final x = position.dx.clamp(minX, maxX);
          final y = position.dy.clamp(minY, maxY);
          final snapshot = widget.monitor.snapshot;
          String value(double? number, {int digits = 0, String unit = ''}) =>
              number == null ? '—' : '${number.toStringAsFixed(digits)}$unit';
          final metrics = [
            ('FPS', value(snapshot?.frames.fps)),
            ('Memory', value(snapshot?.memoryMiB, unit: ' MB')),
            ('CPU', value(snapshot?.cpuPercent, digits: 1, unit: '%')),
          ];
          return Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                width: width,
                height: height,
                child: Semantics(
                  container: true,
                  child: RepaintBoundary(
                    child: Material(
                      key: const Key('performance-overlay'),
                      color: const Color(0xDE182028),
                      elevation: 3,
                      shadowColor: const Color(0x28000000),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0x20FFFFFF)),
                      ),
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (event) => setState(() {
                            // Accumulate pointer events even before a rebuild.
                            final current = _position ?? Offset(x, y);
                            _position = Offset(
                              (current.dx.clamp(minX, maxX) + event.delta.dx)
                                  .clamp(minX, maxX),
                              (current.dy.clamp(minY, maxY) + event.delta.dy)
                                  .clamp(minY, maxY),
                            );
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            child: DefaultTextStyle(
                              style: const TextStyle(
                                color: Color(0xFFF2F5F7),
                                fontSize: 11,
                                height: 1.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < metrics.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 3),
                                    SizedBox(
                                      height: 18,
                                      child: Row(
                                        children: [
                                          Text(
                                            metrics[i].$1,
                                            style: const TextStyle(
                                              color: Color(0xBFFFFFFF),
                                              fontSize: 10,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                metrics[i].$2,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
