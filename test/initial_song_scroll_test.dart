import 'package:ai_music/src/presentation/initial_song_scroll.dart';
import 'package:ai_music/src/presentation/playlist_sliver_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'location visibly rolls to the song within 260ms and a drag takes over',
    (tester) async {
      late ScrollController scroll;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InitialSongScroll(
              targetIndex: 80,
              builder: (context, controller, anchor) {
                scroll = controller;
                return ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (_, i) => anchor(
                    i,
                    '$i',
                    SizedBox(
                      height: 90,
                      key: ValueKey('song-$i'),
                      child: Text('Song $i'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      // Prepare the destination, then paint the starting rows before animation.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      final start = scroll.offset;
      await tester.pump(const Duration(milliseconds: 80));
      expect(scroll.offset, greaterThan(start));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(
        find.byKey(const ValueKey('song-80')).hitTestable(),
        findsOneWidget,
      );

      // Reopen and interrupt the animation while it is running.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InitialSongScroll(
              targetIndex: 80,
              builder: (context, controller, anchor) {
                scroll = controller;
                return ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (_, i) => anchor(
                    i,
                    '$i',
                    SizedBox(height: 90, child: Text('Song $i')),
                  ),
                );
              },
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 60));
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      final browsed = scroll.offset;
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, browsed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'waits for page entrance before rolling and safely closes mid-animation',
    (tester) async {
      late ScrollController scroll;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: InitialSongScroll(
                      targetIndex: 80,
                      builder: (context, controller, anchor) {
                        scroll = controller;
                        return ListView.builder(
                          controller: controller,
                          itemCount: 100,
                          itemBuilder: (_, i) => anchor(
                            i,
                            '$i',
                            SizedBox(height: 90, child: Text('Song $i')),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      final start = scroll.offset;
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, start);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(scroll.offset, greaterThan(start));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled motion locates immediately without a scrolling animation',
    (tester) async {
      late ScrollController scroll;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: InitialSongScroll(
              targetIndex: 80,
              builder: (context, controller, anchor) {
                scroll = controller;
                return ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (_, i) => anchor(
                    i,
                    '$i',
                    SizedBox(
                      height: 90,
                      key: ValueKey('song-$i'),
                      child: Text('Song $i'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('song-80')).hitTestable(),
        findsOneWidget,
      );
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      final offset = scroll.offset;
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, offset);
    },
  );
  testWidgets(
    'first playing song is visible below an oversized playlist header',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InitialSongScroll(
              targetIndex: 0,
              builder: (context, controller, anchor) => PlaylistScrollView(
                controller: controller,
                slivers: [
                  const PlaylistSliverHeader(title: 'Long playlist title'),
                  const SliverToBoxAdapter(child: SizedBox(height: 1200)),
                  SliverList.builder(
                    itemCount: 100,
                    itemBuilder: (_, i) => anchor(
                      i,
                      '$i',
                      SizedBox(
                        key: ValueKey('song-$i'),
                        height: 100,
                        child: Text('Song $i'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('song-0')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final reorderable in [false, true]) {
    for (final target in [0, 487, 999]) {
      testWidgets(
        'opens lazy ${reorderable ? 'queue' : 'playlist'} at $target with variable row heights',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var built = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: InitialSongScroll(
                  targetIndex: target,
                  builder: (context, controller, anchor) {
                    Widget row(BuildContext context, int index) {
                      built++;
                      return anchor(
                        index,
                        '$index',
                        SizedBox(
                          key: ValueKey('song-$index'),
                          height: 64 + (index % 5) * 23,
                          child: Text('Song $index'),
                        ),
                      );
                    }

                    return reorderable
                        ? ReorderableListView.builder(
                            scrollController: controller,
                            itemCount: 1000,
                            // ignore: deprecated_member_use
                            onReorder: (_, _) {},
                            itemBuilder: row,
                          )
                        : PlaylistScrollView(
                            controller: controller,
                            slivers: [
                              const PlaylistSliverHeader(
                                title: 'Long playlist',
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 265),
                              ),
                              SliverList.separated(
                                itemCount: 1000,
                                itemBuilder: row,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 100),
                              ),
                            ],
                          );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('song-$target')).hitTestable(),
            findsOneWidget,
          );
          final rect = tester.getRect(find.byKey(ValueKey('song-$target')));
          expect(rect.top, greaterThanOrEqualTo(reorderable ? 0 : 56));
          expect(rect.bottom, lessThanOrEqualTo(700));
          // Variable-height slivers measure preceding rows on a far jump, but
          // only retain the visible window instead of mounting the whole list.
          expect(built, lessThan(1100));
          expect(find.byType(Text).evaluate().length, lessThan(35));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'waits for loaded rows, locates once, allows browsing and locates again on reopen',
    (tester) async {
      var ready = false;
      var target = 80;
      late StateSetter update;
      ScrollController? scroll;
      Widget app() => MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return InitialSongScroll(
                ready: ready,
                targetIndex: target,
                builder: (context, controller, anchor) {
                  scroll = controller;
                  return ListView.builder(
                    controller: controller,
                    itemCount: ready ? 100 : 0,
                    itemBuilder: (_, i) => anchor(
                      i,
                      '$i',
                      SizedBox(
                        height: 90,
                        key: ValueKey('song-$i'),
                        child: Text('Song $i'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      update(() => ready = true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('song-80')).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 450));
      await tester.pumpAndSettle();
      final browsed = scroll!.offset;
      update(() => target = 90);
      await tester.pumpAndSettle();
      expect(scroll!.offset, browsed);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('song-90')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing song keeps the list at its beginning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InitialSongScroll(
          targetIndex: -1,
          builder: (context, controller, anchor) => ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, i) =>
                anchor(i, '$i', SizedBox(height: 90, child: Text('Song $i'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Song 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a song already in view on opening leaves the list still', (
    tester,
  ) async {
    late ScrollController scroll;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InitialSongScroll(
            targetIndex: 2,
            builder: (context, controller, anchor) {
              scroll = controller;
              return ListView.builder(
                controller: controller,
                itemCount: 40,
                itemBuilder: (_, i) => anchor(
                  i,
                  '$i',
                  SizedBox(
                    height: 90,
                    key: ValueKey('song-$i'),
                    child: Text('Song $i'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final offsets = <double>[];
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      offsets.add(scroll.offset);
    }
    expect(offsets, everyElement(0.0));
    expect(find.byKey(const ValueKey('song-2')).hitTestable(), findsOneWidget);
  });
}
