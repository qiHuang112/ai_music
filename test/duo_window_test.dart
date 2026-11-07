import 'package:ai_music/src/presentation/duo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera margins avoid the correct edge and reject stale rotation data',
    () {
      final snapshot = <Object?, Object?>{
        'width': 890.0,
        'height': 626.0,
        'regions': [
          {'kind': 'occlusion', 'x': 820, 'y': 12, 'width': 70, 'height': 80},
          {'kind': 'division', 'x': 430, 'y': 0, 'width': 30, 'height': 626},
        ],
      };
      final geometry = DuoGeometry.fromMap(snapshot, const Size(890, 626));
      expect(geometry.occlusionInsets, const EdgeInsets.only(right: 70));
      expect(geometry.divisions, [const Rect.fromLTWH(430, 0, 30, 626)]);
      final rotated = DuoGeometry.fromMap(snapshot, const Size(626, 890));
      expect(rotated.occlusionInsets, EdgeInsets.zero);
      expect(rotated.divisions, isEmpty);
    },
  );
}
