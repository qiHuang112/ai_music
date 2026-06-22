import 'package:ai_music/src/playback/shuffle_skip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short manual skips are excluded until the round releases', () {
    final planner = ShuffleSkipPlanner(seed: 7)
      ..reset(const ['alpha', 'beta', 'gamma']);
    final order = planner.order;
    final current = order[0];
    final skipped = order[1];
    final fallback = order[2];

    planner.nextAfter(skipped, position: const Duration(seconds: 3));

    expect(planner.earlySkippedIds, contains(skipped));
    expect(
      planner.nextAfter(current, position: const Duration(seconds: 12)),
      fallback,
    );
  });

  test('same queue keeps the existing shuffle order', () {
    final planner = ShuffleSkipPlanner(seed: 9)
      ..reset(const ['alpha', 'beta', 'gamma']);
    final order = planner.order;

    planner.updateQueue(const ['alpha', 'beta', 'gamma']);

    expect(planner.order, order);
  });

  test('all skipped tracks release without reshuffling the order', () {
    final planner = ShuffleSkipPlanner(seed: 11)
      ..reset(const ['alpha', 'beta', 'gamma']);
    final order = planner.order;

    for (final id in order) {
      planner.nextAfter(id, position: const Duration(seconds: 2));
    }

    expect(planner.earlySkippedIds, isEmpty);
    expect(planner.order, order);
  });

  test('completed track keeps random order without marking an early skip', () {
    final planner = ShuffleSkipPlanner(seed: 13)
      ..reset(const ['alpha', 'beta', 'gamma']);
    final order = planner.order;

    expect(planner.nextAfterCompleted(order[0]), order[1]);
    expect(planner.earlySkippedIds, isEmpty);
    expect(planner.order, order);
  });
}
