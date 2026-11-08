import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_shell.dart';

/// UIKit reserved regions are separate from Flutter's traditional safe area.
/// Keep the Navigator mounted while its available window changes.
class DuoWindow extends StatefulWidget {
  const DuoWindow({super.key, required this.child});
  final Widget child;

  @override
  State<DuoWindow> createState() => _DuoWindowState();
}

class _DuoWindowState extends State<DuoWindow> with WidgetsBindingObserver {
  static const _channel = MethodChannel('ai_music/window_regions');
  Map<Object?, Object?> _geometry = const {};
  bool get _enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _accept(call.arguments);
    });
    _refresh();
  }

  void _accept(Object? value) {
    if (mounted && value is Map) {
      setState(() => _geometry = Map<Object?, Object?>.from(value));
    }
  }

  Future<void> _refresh() async {
    try {
      _accept(await _channel.invokeMethod<Object?>('snapshot'));
    } on MissingPluginException {
      // Other hosts and widget tests use the engine's own display features.
    } on PlatformException {
      // Preserve the engine safe area if the host isn't ready yet.
    }
  }

  @override
  void didChangeMetrics() => _refresh();

  @override
  void dispose() {
    if (_enabled) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final geometry = DuoGeometry.fromMap(_geometry, data.size);
    // Keep the complete window when UIKit asks for a vertical bar. Each
    // DuoScaffold puts controls in that strip, below the actual occlusions.
    // Under the native shell the system bars already keep their controls
    // clear of the camera, and content sits below them through the safe
    // area; padding the whole window as well left a strip of the dimmer app
    // backdrop showing above every page, read as a dark band at the top.
    final inset = geometry.edge == DuoBarEdge.none && !NativeShell.active
        ? geometry.occlusionInsets
        : EdgeInsets.zero;
    EdgeInsets remaining(EdgeInsets value) => EdgeInsets.fromLTRB(
      math.max(0, value.left - inset.left),
      math.max(0, value.top - inset.top),
      math.max(0, value.right - inset.right),
      math.max(0, value.bottom - inset.bottom),
    );
    final offset = Offset(inset.left, inset.top);
    return Padding(
      padding: inset,
      child: MediaQuery(
        data: data.copyWith(
          size: Size(
            data.size.width - inset.horizontal,
            data.size.height - inset.vertical,
          ),
          padding: remaining(data.padding),
          viewPadding: remaining(data.viewPadding),
          displayFeatures: [
            for (final feature in data.displayFeatures)
              ui.DisplayFeature(
                bounds: feature.bounds.shift(-offset),
                type: feature.type,
                state: feature.state,
              ),
            for (final rect in geometry.divisions)
              ui.DisplayFeature(
                bounds: rect.shift(-offset),
                type: ui.DisplayFeatureType.hinge,
                state: ui.DisplayFeatureState.postureHalfOpened,
              ),
          ],
        ),
        child: DuoWindowScope(geometry: geometry, child: widget.child),
      ),
    );
  }
}

enum DuoBarEdge { none, left, right }

class DuoWindowScope extends InheritedWidget {
  const DuoWindowScope({
    super.key,
    required this.geometry,
    required super.child,
  });
  final DuoGeometry geometry;
  static DuoGeometry of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoWindowScope>()?.geometry ??
      const DuoGeometry(EdgeInsets.zero, []);
  @override
  bool updateShouldNotify(DuoWindowScope oldWidget) =>
      geometry != oldWidget.geometry;
}

class DuoGeometry {
  const DuoGeometry(
    this.occlusionInsets,
    this.divisions, {
    this.edge = DuoBarEdge.none,
    this.obstructions = const [],
  });
  final DuoBarEdge edge;
  final List<Rect> obstructions;
  final EdgeInsets occlusionInsets;
  final List<Rect> divisions;

  factory DuoGeometry.fromMap(Map<Object?, Object?> map, Size size) {
    // Discard an in-flight snapshot from the previous window orientation.
    if (map['width'] != size.width || map['height'] != size.height) {
      return const DuoGeometry(EdgeInsets.zero, []);
    }
    var inset = EdgeInsets.zero;
    final divisions = <Rect>[];
    final obstructions = <Rect>[];
    for (final raw in (map['regions'] as List? ?? const [])) {
      final r = Map<Object?, Object?>.from(raw as Map);
      double n(String key) => (r[key] as num).toDouble();
      final rect = Rect.fromLTWH(
        n('x'),
        n('y'),
        n('width'),
        n('height'),
      ).intersect(Offset.zero & size);
      if (rect.isEmpty) continue;
      if (r['kind'] == 'division') {
        divisions.add(rect);
      } else {
        obstructions.add(rect);
        if (r['kind'] == 'status') continue;
        // Reserve the nearest edge strip for camera / Live Activity occlusions.
        // This also protects Flutter sheets and app-bar buttons globally.
        final edges = [
          rect.right,
          rect.bottom,
          size.width - rect.left,
          size.height - rect.top,
        ];
        final edge = edges.indexOf(edges.reduce(math.min));
        inset = EdgeInsets.fromLTRB(
          math.max(inset.left, edge == 0 ? edges[0] : 0),
          math.max(inset.top, edge == 1 ? edges[1] : 0),
          math.max(inset.right, edge == 2 ? edges[2] : 0),
          math.max(inset.bottom, edge == 3 ? edges[3] : 0),
        );
      }
    }
    return DuoGeometry(
      inset,
      divisions,
      edge: switch (map['verticalBarEdge']) {
        'left' => DuoBarEdge.left,
        'right' => DuoBarEdge.right,
        _ => DuoBarEdge.none,
      },
      obstructions: obstructions,
    );
  }
}
