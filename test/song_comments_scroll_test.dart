import 'dart:async';

import 'package:ai_music/src/data/song_comments.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/song_comments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = SongCommentQuery(title: '不再犹豫', artist: 'Beyond');

void main() {
  testWidgets('long press still selects comment text for copying', (
    tester,
  ) async {
    final repository = _SlowCommentsRepository();
    await _mount(tester, repository);
    final body = find.text(_content(0));
    await tester.longPressAt(tester.getTopLeft(body) + const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('next page starts before the reader reaches the footer', (
    tester,
  ) async {
    final repository = _SlowCommentsRepository();
    await _mount(tester, repository);
    final list = tester.widget<ListView>(find.byType(ListView));
    final controller = list.controller!;
    for (var i = 0; i < 80 && repository.nextPageCalls == 0; i++) {
      controller.jumpTo(controller.offset + 100);
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(repository.nextPageCalls, 1);
    // The old 240px trigger waited until new rows would be on screen.
    expect(controller.position.extentAfter, greaterThan(240));
    expect(
      controller.position.extentAfter,
      lessThanOrEqualTo(controller.position.viewportDimension + 100),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('body swipes scroll the comment list without moving text internally', (
    tester,
  ) async {
    final repository = _SlowCommentsRepository();
    await _mount(tester, repository);
    final list = find.byType(ListView);
    final controller = tester.widget<ListView>(list).controller!;
    final observations = <Map<String, Object?>>[];

    for (var swipe = 0; swipe < 12; swipe++) {
      // More than the double-tap window: these are separate human-paced swipes,
      // not repeated taps inadvertently entering text-selection gestures.
      await tester.pump(const Duration(milliseconds: 400));
      final (body, point) = _visibleBody(tester, list);
      final beforeOffset = controller.offset;
      final beforeY = tester.getTopLeft(body).dy;
      final beforeInner = _innerOffsets(tester, body);
      final content = _bodyText(tester.widget(body))!;
      final hitTargets = tester
          .hitTestOnBinding(point)
          .path
          .map((entry) => entry.target.runtimeType.toString())
          .toList();
      final gesture = await tester.startGesture(point);
      for (var step = 0; step < 6; step++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      final delta = controller.offset - beforeOffset;
      final sameBody = find.text(content);
      final stillMounted = sameBody.evaluate().isNotEmpty;
      final afterInner = stillMounted
          ? _innerOffsets(tester, sameBody)
          : <double>[];
      final afterY = stillMounted ? tester.getTopLeft(sameBody).dy : null;
      observations.add({
        'swipe': swipe,
        'outerBefore': beforeOffset,
        'outerAfter': controller.offset,
        'bodyBeforeY': beforeY,
        'bodyAfterY': afterY,
        'innerBefore': beforeInner,
        'innerAfter': afterInner,
        'point': point.toString(),
        'hitTargets': hitTargets,
        'selection': [
          for (final editable in tester.widgetList<EditableText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is EditableText && widget.controller.text == content,
            ),
          ))
            '${editable.controller.selection}; focus=${editable.focusNode.hasFocus}',
        ],
      });
      // The fixture has many screenfuls ahead, so these swipes are not clamped
      // at the list's bottom. A text node must not consume the vertical drag.
      expect(delta, greaterThan(30), reason: observations.toString());
      for (final offset in afterInner) {
        expect(offset.abs(), lessThan(.5), reason: observations.toString());
      }
      if (afterY != null) {
        expect(
          afterY - beforeY,
          closeTo(-delta, 1),
          reason: observations.toString(),
        );
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slow page append preserves visible comment position and text', (
    tester,
  ) async {
    final repository = _SlowCommentsRepository();
    await _mount(tester, repository);
    final list = find.byType(ListView);
    final controller = tester.widget<ListView>(list).controller!;
    // Trigger the same near-bottom listener used by swiping, then leave the
    // fetch pending so we can compare content before and after the append.
    controller.jumpTo(controller.position.maxScrollExtent - 100);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      controller.jumpTo(controller.position.maxScrollExtent - 100);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repository.nextPageCalls, 1);
    final anchor = find.text(_content(5));
    expect(anchor, findsOneWidget);
    final beforeY = tester.getTopLeft(anchor).dy;
    final beforeOffset = controller.offset;
    // No pumpAndSettle while the pending footer's spinner is active.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(anchor).dy, closeTo(beforeY, .5));
    expect(controller.offset, closeTo(beforeOffset, .5));
    repository.nextPage.complete(_page([6, 7, 8], hasMore: false));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(beforeY, .5));
    expect(controller.offset, closeTo(beforeOffset, .5));
    expect(repository.nextPageCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _mount(
  WidgetTester tester,
  _SlowCommentsRepository repository,
) async {
  tester.view.physicalSize = const Size(393, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: MusicAppTheme.create(
        Brightness.light,
      ).copyWith(platform: TargetPlatform.android),
      home: SongCommentsPage(query: _query, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

(Finder, Offset) _visibleBody(WidgetTester tester, Finder list) {
  final viewport = tester.getRect(list).deflate(24);
  Finder? best;
  Rect? bestRect;
  for (final element
      in find
          .byWidgetPredicate(
            (widget) => _bodyText(widget)?.startsWith('评论 ') ?? false,
          )
          .evaluate()) {
    final body = find.byWidget(element.widget);
    final overlap = tester.getRect(body).intersect(viewport);
    if (overlap.height > 140 &&
        overlap.width > 80 &&
        (bestRect == null || overlap.height > bestRect.height)) {
      best = body;
      bestRect = overlap;
    }
  }
  expect(
    best,
    isNotNull,
    reason: 'A long comment body should fill the viewport',
  );
  return (best!, Offset(bestRect!.center.dx, bestRect.bottom - 10));
}

String? _bodyText(Widget widget) => switch (widget) {
  SelectableText() => widget.data,
  Text() => widget.data,
  _ => null,
};

List<double> _innerOffsets(WidgetTester tester, Finder body) => [
  for (final state in tester.stateList<ScrollableState>(
    find.descendant(of: body, matching: find.byType(Scrollable)),
  ))
    state.position.pixels,
];

String _content(int index) =>
    '评论 $index\n${List.generate(18, (line) => '第${line + 1}段：每次听到熟悉的旋律，都会想起曾经一起走过的日子。').join('\n')}';

SongCommentsResult _page(List<int> indexes, {required bool hasMore}) =>
    SongCommentsResult(
      platform: SongCommentPlatform.netease,
      status: SongCommentsStatus.ready,
      pageUrl: _query.searchUrl(SongCommentPlatform.netease),
      hasMore: hasMore,
      comments: [
        for (final index in indexes)
          SongComment(
            id: '$index',
            author: '听众 $index',
            content: _content(index),
            likes: 100 - index,
            createdAt: DateTime(2026, 10, 8),
          ),
      ],
    );

class _SlowCommentsRepository extends SongCommentsRepository {
  final nextPage = Completer<SongCommentsResult>();
  int nextPageCalls = 0;
  @override
  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) async {
    if (page == 0) return _page([0, 1, 2, 3, 4, 5], hasMore: true);
    nextPageCalls++;
    return nextPage.future;
  }
}
