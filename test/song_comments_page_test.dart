import 'dart:async';

import 'package:ai_music/src/data/song_comments.dart';
import 'package:ai_music/src/presentation/song_comments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = SongCommentQuery(title: '不再犹豫', artist: 'Beyond');

void main() {
  testWidgets(
    'comments load lazily per platform and out of order replies do not replace selected source',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: SongCommentsPage(query: _query, repository: repo),
        ),
      );
      expect(repo.calls, [SongCommentPlatform.netease]);
      await tester.tap(find.byKey(const ValueKey('comments-platform-qq')));
      await tester.pump();
      expect(repo.calls, [SongCommentPlatform.netease, SongCommentPlatform.qq]);
      repo.qq.complete(_result(SongCommentPlatform.qq, 'QQ热评正文'));
      await tester.pumpAndSettle();
      expect(find.text('QQ热评正文'), findsOneWidget);
      repo.ne.complete(_result(SongCommentPlatform.netease, '网易热评正文'));
      await tester.pumpAndSettle();
      expect(find.text('QQ热评正文'), findsOneWidget);
      expect(find.text('网易热评正文'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('comments-platform-netease')));
      await tester.pumpAndSettle();
      expect(find.text('网易热评正文'), findsOneWidget);
      expect(repo.calls.length, 2);
    },
  );

  testWidgets('no match can be retried within the comments page', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: SongCommentsPage(query: _query, repository: repo),
      ),
    );
    repo.ne.complete(
      SongCommentsResult(
        platform: SongCommentPlatform.netease,
        status: SongCommentsStatus.noMatch,
        pageUrl: _query.searchUrl(SongCommentPlatform.netease),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有找到'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repo.calls.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'comments remain scrollable on a narrow screen with enlarged text',
    (tester) async {
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
      repo.ne.complete(_result(SongCommentPlatform.netease, '很长的一条公开热评。' * 50));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paging failure keeps comments and retries the same cursor', (
    tester,
  ) async {
    final repo = _PagedRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SongCommentsPage(query: _query, repository: repo),
      ),
    );
    repo.requests.single.complete(
      _pageResult(['one'], hasMore: true, cursor: 'c1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comments-load-more')));
    await tester.pump();
    expect(repo.requests.length, 2);
    expect(repo.requests.last.page, 1);
    expect(repo.requests.last.cursor, 'c1');
    expect(find.text('评论one'), findsOneWidget);
    repo.requests.last.complete(
      SongCommentsResult(
        platform: SongCommentPlatform.netease,
        status: SongCommentsStatus.unavailable,
        pageUrl: _query.searchUrl(SongCommentPlatform.netease),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('评论one'), findsOneWidget);
    await tester.tap(find.byKey(const Key('comments-more-retry')));
    await tester.pump();
    expect(repo.requests.last.page, 1);
    expect(repo.requests.last.cursor, 'c1');
    repo.requests.last.complete(_pageResult(['one', 'two']));
    await tester.pumpAndSettle();
    expect(find.text('评论one'), findsOneWidget);
    expect(find.text('评论two'), findsOneWidget);
    expect(find.text('已显示全部热评'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late next page does not replace the refreshed first page', (
    tester,
  ) async {
    final repo = _PagedRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SongCommentsPage(query: _query, repository: repo),
      ),
    );
    repo.requests.single.complete(_pageResult(['old'], hasMore: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comments-load-more')));
    await tester.pump();
    final oldPage = repo.requests.last;
    await tester.tap(find.byKey(const Key('comments-refresh')));
    await tester.pump();
    expect(repo.requests.last.refresh, isTrue);
    repo.requests.last.complete(_pageResult(['fresh']));
    await tester.pumpAndSettle();
    oldPage.complete(_pageResult(['late']));
    await tester.pumpAndSettle();
    expect(find.text('评论fresh'), findsOneWidget);
    expect(find.text('评论old'), findsNothing);
    expect(find.text('评论late'), findsNothing);
  });

  testWidgets('platform switches keep pending pages isolated and reuse them', (
    tester,
  ) async {
    final repo = _PagedRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SongCommentsPage(query: _query, repository: repo),
      ),
    );
    repo.requests.single.complete(_pageResult(['ne1'], hasMore: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comments-load-more')));
    await tester.pump();
    final pendingNetease = repo.requests.last;
    await tester.tap(find.byKey(const ValueKey('comments-platform-qq')));
    await tester.pump();
    repo.requests.last.complete(
      _pageResult(['qq'], platform: SongCommentPlatform.qq),
    );
    await tester.pumpAndSettle();
    pendingNetease.complete(_pageResult(['ne2']));
    await tester.pumpAndSettle();
    expect(find.text('评论qq'), findsOneWidget);
    expect(find.text('评论ne2'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('comments-platform-netease')));
    await tester.pumpAndSettle();
    expect(find.text('评论ne1'), findsOneWidget);
    expect(find.text('评论ne2'), findsOneWidget);
    expect(repo.requests.length, 3);
  });

  testWidgets(
    'scrolling to the bottom loads once and retains each platform position',
    (tester) async {
      final repo = _PagedRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: SongCommentsPage(query: _query, repository: repo),
        ),
      );
      repo.requests.single.complete(
        _pageResult(List.generate(10, (index) => 'ne$index'), hasMore: true),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pump();
      expect(repo.requests.length, 2);
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pump();
      expect(repo.requests.length, 2);
      repo.requests.last.complete(_pageResult(['next']));
      await tester.pumpAndSettle();
      final offset = list.controller!.offset;
      await tester.tap(find.byKey(const ValueKey('comments-platform-qq')));
      await tester.pump();
      repo.requests.last.complete(
        _pageResult(['qq'], platform: SongCommentPlatform.qq),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comments-platform-netease')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        offset,
      );
      expect(repo.requests.length, 3);
      expect(tester.takeException(), isNull);
    },
  );
}

SongCommentsResult _result(SongCommentPlatform platform, String text) =>
    SongCommentsResult(
      platform: platform,
      status: SongCommentsStatus.ready,
      pageUrl: _query.searchUrl(platform),
      comments: [
        SongComment(
          id: '1',
          author: '音乐听众',
          content: text,
          likes: 25,
          createdAt: DateTime(2026, 10, 8),
        ),
      ],
    );

class _Repository extends SongCommentsRepository {
  final calls = <SongCommentPlatform>[];
  final ne = Completer<SongCommentsResult>();
  final qq = Completer<SongCommentsResult>();
  @override
  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) {
    calls.add(platform);
    return platform == SongCommentPlatform.netease ? ne.future : qq.future;
  }
}

SongCommentsResult _pageResult(
  List<String> ids, {
  SongCommentPlatform platform = SongCommentPlatform.netease,
  bool hasMore = false,
  String? cursor,
}) => SongCommentsResult(
  platform: platform,
  status: SongCommentsStatus.ready,
  pageUrl: _query.searchUrl(platform),
  hasMore: hasMore,
  nextCursor: cursor,
  comments: [
    for (final id in ids)
      SongComment(id: id, author: '听众', content: '评论$id', likes: 1),
  ],
);

class _CommentRequest {
  _CommentRequest(this.platform, this.page, this.cursor, this.refresh);
  final _completer = Completer<SongCommentsResult>();
  Future<SongCommentsResult> get future => _completer.future;
  void complete(SongCommentsResult result) => _completer.complete(result);
  final SongCommentPlatform platform;
  final int page;
  final String? cursor;
  final bool refresh;
}

class _PagedRepository extends SongCommentsRepository {
  final requests = <_CommentRequest>[];
  @override
  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) {
    final request = _CommentRequest(platform, page, cursor, refresh);
    requests.add(request);
    return request.future;
  }
}
