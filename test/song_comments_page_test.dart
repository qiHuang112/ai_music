import 'dart:async';

import 'package:ai_music/src/data/song_comments.dart';
import 'package:ai_music/src/presentation/song_comments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = SongCommentQuery(title: '不再犹豫', artist: 'Beyond');

void main() {
  testWidgets(
    'offline combined refresh preserves loaded pages and reading position',
    (tester) async {
      final repo = _Repository();
      await _mount(tester, repo);
      repo
          .last(SongCommentPlatform.netease)
          .complete(
            _page(
              List.generate(15, (i) => '$i'),
              SongCommentPlatform.netease,
              more: true,
            ),
          );
      await tester.pumpAndSettle();
      var list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pump();
      final pending = repo.last(SongCommentPlatform.netease);
      expect(pending.page, 1);
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pump();
      expect(
        repo.last(SongCommentPlatform.netease),
        same(pending),
        reason: 'one request per in-flight page',
      );
      pending.complete(_page(['extra'], SongCommentPlatform.netease));
      await tester.pumpAndSettle();
      list = tester.widget<ListView>(find.byType(ListView));
      final offset = list.controller!.offset;
      await tester.tap(find.byKey(const Key('comments-refresh')));
      await tester.pump();
      repo
          .last(SongCommentPlatform.netease)
          .complete(
            SongCommentsResult(
              platform: SongCommentPlatform.netease,
              status: SongCommentsStatus.ready,
              pageUrl: _query.searchUrl(SongCommentPlatform.netease),
              stale: true,
              comments: const [
                SongComment(id: '0', author: '', content: '评论0', likes: 1),
              ],
            ),
          );
      await tester.pumpAndSettle();
      list = tester.widget<ListView>(find.byType(ListView));
      expect(list.controller!.offset, offset);
      expect(list.semanticChildCount, 17);
    },
  );

  testWidgets(
    'late responses after leaving the combined page do not update disposed state',
    (tester) async {
      final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
      await _mount(tester, repo);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final source in SongCommentPlatform.values) {
        repo.last(source).complete(_page(['late'], source));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default all loads three sources independently and labels every comment',
    (tester) async {
      final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
      await _mount(tester, repo);
      expect(repo.requests.map((r) => r.platform), SongCommentPlatform.values);
      repo
          .last(SongCommentPlatform.qq)
          .complete(_page(['qq'], SongCommentPlatform.qq));
      await tester.pump();
      expect(find.text('评论qq'), findsOneWidget);
      expect(find.text('来自QQ 音乐'), findsOneWidget);
      repo
          .last(SongCommentPlatform.netease)
          .complete(_page(['ne'], SongCommentPlatform.netease));
      repo
          .last(SongCommentPlatform.qishui)
          .complete(_page(['qs'], SongCommentPlatform.qishui));
      await tester.pumpAndSettle();
      for (final source in SongCommentPlatform.values) {
        expect(find.text('来自${source.label}'), findsOneWidget);
      }
      expect(find.byType(SegmentedButton<SongCommentPlatform>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same comment ID on different platforms remains distinct', (
    tester,
  ) async {
    final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
    await _mount(tester, repo);
    for (final source in SongCommentPlatform.values) {
      repo.last(source).complete(_page(['same', 'same'], source));
    }
    await tester.pumpAndSettle();
    expect(find.text('评论same'), findsNWidgets(3));
  });

  testWidgets(
    'more menu filters an existing combined list without refetching',
    (tester) async {
      final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
      await _mount(tester, repo);
      for (final source in SongCommentPlatform.values) {
        repo.last(source).complete(_page([source.name], source));
      }
      await tester.pumpAndSettle();
      await _select(tester, 'qishui');
      expect(find.text('评论qishui'), findsOneWidget);
      expect(find.text('评论qq'), findsNothing);
      await _select(tester, 'all');
      expect(find.text('评论qq'), findsOneWidget);
      expect(repo.requests, hasLength(3));
    },
  );

  testWidgets('one readable platform hides all other source status messages', (
    tester,
  ) async {
    final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
    await _mount(tester, repo);
    repo
        .last(SongCommentPlatform.netease)
        .complete(_unavailable(SongCommentPlatform.netease));
    repo
        .last(SongCommentPlatform.qishui)
        .complete(_unavailable(SongCommentPlatform.qishui));
    await tester.pump();
    expect(find.byKey(const Key('comments-empty-message')), findsNothing);
    repo
        .last(SongCommentPlatform.qq)
        .complete(_page(['qq'], SongCommentPlatform.qq));
    await tester.pumpAndSettle();
    expect(find.text('评论qq'), findsOneWidget);
    expect(find.textContaining('暂时无法读取'), findsNothing);
    expect(find.text('重试'), findsNothing);
    // An explicit failed-platform filter still offers that platform's retry.
    await _select(tester, 'netease');
    expect(
      find.byKey(const ValueKey('comments-retry-netease')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('comments-retry-netease')));
    await tester.pump();
    repo
        .last(SongCommentPlatform.netease)
        .complete(_page(['recovered'], SongCommentPlatform.netease));
    await tester.pumpAndSettle();
    expect(find.text('评论recovered'), findsOneWidget);
    expect(
      repo.requests.where((r) => r.platform == SongCommentPlatform.qq),
      hasLength(1),
    );
    expect(
      repo.requests.where((r) => r.platform == SongCommentPlatform.qishui),
      hasLength(1),
    );
  });

  testWidgets('all source failures collapse to one message and one retry', (
    tester,
  ) async {
    final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
    await _mount(tester, repo);
    for (final source in SongCommentPlatform.values) {
      repo.last(source).complete(_unavailable(source));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时无法读取'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comments-retry-all')));
    await tester.pump();
    for (final source in SongCommentPlatform.values) {
      expect(repo.last(source).refresh, isTrue);
      repo
          .last(source)
          .complete(
            _page(source == SongCommentPlatform.qq ? ['ok'] : [], source),
          );
    }
    await tester.pumpAndSettle();
    expect(find.text('评论ok'), findsOneWidget);
    expect(find.byKey(const Key('comments-empty-message')), findsNothing);
  });

  testWidgets('empty public results show one empty state without an error', (
    tester,
  ) async {
    final repo = _Repository(controlled: {});
    await _mount(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('这首歌暂时没有公开热评'), findsOneWidget);
    expect(find.textContaining('暂时无法读取'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('readable cached comments hide unavailable platform notices', (
    tester,
  ) async {
    final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
    await _mount(tester, repo);
    repo
        .last(SongCommentPlatform.netease)
        .complete(
          SongCommentsResult(
            platform: SongCommentPlatform.netease,
            status: SongCommentsStatus.ready,
            pageUrl: _query.searchUrl(SongCommentPlatform.netease),
            stale: true,
            comments: const [
              SongComment(
                id: 'cached',
                author: '听众',
                content: '已有缓存热评',
                likes: 1,
              ),
            ],
          ),
        );
    repo
        .last(SongCommentPlatform.qq)
        .complete(_unavailable(SongCommentPlatform.qq));
    repo
        .last(SongCommentPlatform.qishui)
        .complete(_unavailable(SongCommentPlatform.qishui));
    await tester.pumpAndSettle();
    expect(find.text('已有缓存热评'), findsOneWidget);
    expect(find.byKey(const Key('comments-empty-message')), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets(
    'single-source paging keeps cursor and deduplicates pinned comments on retry',
    (tester) async {
      final repo = _Repository(controlled: {SongCommentPlatform.qishui});
      await _mount(tester, repo);
      repo
          .last(SongCommentPlatform.qishui)
          .complete(
            _page(
              ['pinned'],
              SongCommentPlatform.qishui,
              more: true,
              cursor: '20',
            ),
          );
      await tester.pumpAndSettle();
      await _select(tester, 'qishui');
      await tester.tap(find.byKey(const Key('comments-load-more')));
      await tester.pump();
      expect(repo.last(SongCommentPlatform.qishui).cursor, '20');
      repo
          .last(SongCommentPlatform.qishui)
          .complete(_unavailable(SongCommentPlatform.qishui));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comments-more-retry')));
      await tester.pump();
      expect(repo.last(SongCommentPlatform.qishui).cursor, '20');
      expect(repo.last(SongCommentPlatform.qishui).page, 1);
      repo
          .last(SongCommentPlatform.qishui)
          .complete(_page(['pinned', 'next'], SongCommentPlatform.qishui));
      await tester.pumpAndSettle();
      expect(find.text('评论pinned'), findsOneWidget);
      expect(find.text('评论next'), findsOneWidget);
    },
  );

  testWidgets(
    'all-source pagination uses each platform cursor and does not mix IDs',
    (tester) async {
      final repo = _Repository(controlled: SongCommentPlatform.values.toSet());
      await _mount(tester, repo);
      for (final source in SongCommentPlatform.values) {
        repo
            .last(source)
            .complete(
              _page(
                [source.name],
                source,
                more: true,
                cursor: 'cursor-${source.name}',
              ),
            );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comments-load-more')));
      await tester.pump();
      for (final source in SongCommentPlatform.values) {
        final next = repo.last(source);
        expect(next.page, 1);
        expect(next.cursor, 'cursor-${source.name}');
        next.complete(_page(['new'], source));
      }
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        list.semanticChildCount,
        7,
        reason:
            'three first-page entries plus three source-scoped new IDs and footer',
      );
    },
  );

  testWidgets('late pagination cannot replace a refreshed first page', (
    tester,
  ) async {
    final repo = _Repository();
    await _mount(tester, repo);
    repo
        .last(SongCommentPlatform.netease)
        .complete(_page(['old'], SongCommentPlatform.netease, more: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comments-load-more')));
    await tester.pump();
    final oldPage = repo.last(SongCommentPlatform.netease);
    await tester.tap(find.byKey(const Key('comments-refresh')));
    await tester.pump();
    expect(repo.last(SongCommentPlatform.netease).refresh, true);
    repo
        .last(SongCommentPlatform.netease)
        .complete(_page(['fresh'], SongCommentPlatform.netease));
    await tester.pumpAndSettle();
    oldPage.complete(_page(['late'], SongCommentPlatform.netease));
    await tester.pumpAndSettle();
    expect(find.text('评论fresh'), findsOneWidget);
    expect(find.text('评论late'), findsNothing);
    expect(find.text('评论old'), findsNothing);
  });

  testWidgets(
    'combined and individual views retain independent reading positions',
    (tester) async {
      final repo = _Repository();
      await _mount(tester, repo);
      repo
          .last(SongCommentPlatform.netease)
          .complete(
            _page(List.generate(25, (i) => '$i'), SongCommentPlatform.netease),
          );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(500);
      await tester.pump();
      await _select(tester, 'qq');
      await _select(tester, 'all');
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        500,
      );
      expect(repo.requests, hasLength(3));
    },
  );

  testWidgets('opening a new comments page always defaults to all', (
    tester,
  ) async {
    final repo = _Repository(controlled: {});
    await _mount(tester, repo);
    await tester.pumpAndSettle();
    await _select(tester, 'qq');
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, repo);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey('comments-list-all')),
      findsOneWidget,
    );
  });

  testWidgets('combined comments and menu fit narrow large-text layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 500),
            textScaler: TextScaler.linear(1.6),
          ),
          child: SongCommentsPage(query: _query, repository: repo),
        ),
      ),
    );
    repo
        .last(SongCommentPlatform.netease)
        .complete(_page(['很长的公开评论。' * 40], SongCommentPlatform.netease));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await _select(tester, 'qishui');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(WidgetTester tester, _Repository repo) => tester.pumpWidget(
  MaterialApp(
    home: SongCommentsPage(query: _query, repository: repo),
  ),
);
Future<void> _select(WidgetTester tester, String platform) async {
  await tester.tap(find.byKey(const Key('comments-more')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.byKey(ValueKey('comments-platform-$platform')),
      matching: find.byType(CheckedPopupMenuItem<String>),
    ),
  );
  await tester.pumpAndSettle();
}

SongCommentsResult _page(
  List<String> ids,
  SongCommentPlatform platform, {
  bool more = false,
  String? cursor,
}) => SongCommentsResult(
  platform: platform,
  status: SongCommentsStatus.ready,
  pageUrl: _query.searchUrl(platform),
  hasMore: more,
  nextCursor: cursor,
  comments: [
    for (final id in ids)
      SongComment(id: id, author: '听众', content: '评论$id', likes: 1),
  ],
);
SongCommentsResult _unavailable(SongCommentPlatform platform) =>
    SongCommentsResult(
      platform: platform,
      status: SongCommentsStatus.unavailable,
      pageUrl: _query.searchUrl(platform),
    );

class _Request {
  _Request(this.platform, this.page, this.cursor, this.refresh);
  final SongCommentPlatform platform;
  final int page;
  final String? cursor;
  final bool refresh;
  final pending = Completer<SongCommentsResult>();
  void complete(SongCommentsResult result) => pending.complete(result);
}

class _Repository extends SongCommentsRepository {
  _Repository({this.controlled = const {SongCommentPlatform.netease}});
  final Set<SongCommentPlatform> controlled;
  final requests = <_Request>[];
  _Request last(SongCommentPlatform platform) =>
      requests.lastWhere((r) => r.platform == platform);
  @override
  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) {
    final request = _Request(platform, page, cursor, refresh);
    requests.add(request);
    if (!controlled.contains(platform)) request.complete(_page([], platform));
    return request.pending.future;
  }
}
