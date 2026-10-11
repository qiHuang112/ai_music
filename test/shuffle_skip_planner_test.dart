import 'package:ai_music/src/playback/shuffle_skip_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('revisiting the same song draws new next tracks', () {
    final planner = ShuffleSkipPlanner(seed: 7)
      ..reset(const ['a', 'b', 'c', 'd', 'e']);
    final choices = {
      for (var i = 0; i < 80; i++) planner.nextAfterCompleted('a'),
    };
    expect(choices, unorderedEquals(['b', 'c', 'd', 'e']));
  });

  test('preloading reserves a draw and consumption draws again', () {
    final planner = ShuffleSkipPlanner(seed: 9)
      ..reset(const ['a', 'b', 'c', 'd']);
    final next = planner.peekNextAfter('a');
    for (var i = 0; i < 5; i++) {
      planner.updateQueue(const ['a', 'b', 'c', 'd']);
      expect(planner.peekNextAfter('a'), next);
    }
    expect(planner.nextAfterCompleted('a'), next);
    expect(planner.earlySkippedIds, isEmpty);
    final draws = {next};
    for (var i = 0; i < 40; i++) {
      final planned = planner.peekNextAfter('a');
      expect(planner.nextAfterCompleted('a'), planned);
      draws.add(planned);
    }
    expect(draws, unorderedEquals(['b', 'c', 'd']));
  });

  test('short manual skips are excluded until candidates are exhausted', () {
    final planner = ShuffleSkipPlanner(seed: 7)..reset(const ['a', 'b', 'c']);
    planner.nextAfter('b', position: const Duration(seconds: 3));
    expect(planner.earlySkippedIds, contains('b'));
    expect(planner.nextAfter('a', position: const Duration(seconds: 12)), 'c');
    expect(planner.peekNextAfter('a'), 'c');
    expect(planner.nextAfter('c', position: const Duration(seconds: 3)), 'a');
    expect(
      planner.nextAfter('a', position: const Duration(seconds: 3)),
      isIn(['b', 'c']),
    );
    expect(planner.earlySkippedIds, isEmpty);
  });

  test(
    'completed songs do not create early skips and never select themselves',
    () {
      final planner = ShuffleSkipPlanner(seed: 13)
        ..reset(const ['a', 'b', 'c']);
      var current = 'a';
      for (var i = 0; i < 100; i++) {
        final next = planner.nextAfterCompleted(current)!;
        expect(next, isNot(current));
        current = next;
      }
      expect(planner.earlySkippedIds, isEmpty);
    },
  );

  test('changed queue drops stale plans and empty/single queues stay safe', () {
    final planner = ShuffleSkipPlanner(seed: 2)..reset(const ['a', 'b']);
    expect(planner.peekNextAfter('a'), 'b');
    planner.updateQueue(const ['a', 'c']);
    expect(planner.nextAfterCompleted('a'), 'c');
    expect(planner.nextAfterCompleted('b'), isNull);
    planner.reset(const ['a']);
    expect(planner.peekNextAfter('a'), isNull);
    expect(planner.nextAfterCompleted('a'), isNull);
    planner.reset(const []);
    expect(planner.nextAfterCompleted('a'), isNull);
  });
}
