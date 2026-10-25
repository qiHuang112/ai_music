import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../data/song_comments.dart';
import 'app_localizations.dart';
import 'app_popup_menu.dart';
import 'app_theme.dart';
import 'comment_text.dart';

class SongCommentsPage extends StatefulWidget {
  const SongCommentsPage({
    super.key,
    required this.query,
    this.repository,
    this.embedded = false,
  });
  final bool embedded;
  final SongCommentQuery query;
  final SongCommentsRepository? repository;

  @override
  State<SongCommentsPage> createState() => _SongCommentsPageState();
}

class _SongCommentsPageState extends State<SongCommentsPage> {
  // null is the default combined view; platform state is shared with filters.
  SongCommentPlatform? _platform;
  final _pages = {
    for (final platform in SongCommentPlatform.values)
      platform: _CommentsViewState(),
  };
  final _scrollControllers = <SongCommentPlatform?, ScrollController>{};
  final _offsets = <SongCommentPlatform?, double>{};
  final _combined = <({SongCommentPlatform platform, SongComment comment})>[];
  bool get zh => AppStringsScope.of(context).isZh;
  SongCommentsRepository get repository =>
      widget.repository ?? SongCommentsRepository.shared;
  Iterable<SongCommentPlatform> get _visiblePlatforms =>
      _platform == null ? SongCommentPlatform.values : [_platform!];
  List<({SongCommentPlatform platform, SongComment comment})> get _comments =>
      _platform == null
      ? _combined
      : [
          for (final comment in _pages[_platform]!.comments)
            (platform: _platform!, comment: comment),
        ];

  @override
  void initState() {
    super.initState();
    for (final platform in <SongCommentPlatform?>[
      null,
      ...SongCommentPlatform.values,
    ]) {
      _scrollControllers[platform] = ScrollController()
        ..addListener(() {
          final scroll = _scrollControllers[platform]!;
          if (_platform == platform &&
              scroll.hasClients &&
              scroll.position.extentAfter <
                  scroll.position.viewportDimension.clamp(480.0, 1200.0)) {
            unawaited(_loadMoreVisible());
          }
        });
    }
    for (final platform in SongCommentPlatform.values) {
      unawaited(_load(platform));
    }
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectPlatform(SongCommentPlatform? platform) {
    if (_platform == platform) return;
    final current = _scrollControllers[_platform]!;
    if (current.hasClients) _offsets[_platform] = current.offset;
    setState(() => _platform = platform);
    for (final source in _visiblePlatforms) {
      unawaited(_load(source));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _platform != platform) return;
      final scroll = _scrollControllers[platform]!;
      if (scroll.hasClients) {
        scroll.jumpTo(
          (_offsets[platform] ?? 0).clamp(0, scroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _appendCombined(
    SongCommentPlatform platform,
    List<SongComment> comments, {
    bool replace = false,
  }) {
    if (replace) _combined.removeWhere((entry) => entry.platform == platform);
    final seen = _combined
        .map((entry) => (entry.platform, entry.comment.id))
        .toSet();
    // Append completed batches without moving comments already being read.
    for (final comment in comments) {
      if (seen.add((platform, comment.id))) {
        _combined.add((platform: platform, comment: comment));
      }
    }
  }

  Future<void> _load(
    SongCommentPlatform platform, {
    bool refresh = false,
  }) async {
    final page = _pages[platform]!;
    if (page.loading || (!refresh && page.result != null)) return;
    final request = ++page.request;
    setState(() {
      page.loading = true;
      page.loadingMore = false;
      page.moreFailed = false;
    });
    SongCommentsResult result;
    try {
      result = await repository.load(widget.query, platform, refresh: refresh);
    } catch (_) {
      result = SongCommentsResult(
        platform: platform,
        status: SongCommentsStatus.unavailable,
        pageUrl: widget.query.searchUrl(platform),
      );
    }
    if (!mounted || request != page.request) return;
    setState(() {
      page.result = result;
      page.loading = false;
      if (result.stale && page.comments.isNotEmpty) return;
      page.comments = _unique(result.comments);
      page.nextPage = 1;
      page.nextCursor = result.nextCursor;
      page.hasMore = result.hasMore && page.comments.isNotEmpty;
      _appendCombined(platform, page.comments, replace: true);
    });
    if (refresh && !result.stale) {
      _offsets[platform] = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != page.request || _platform != platform) {
          return;
        }
        final scroll = _scrollControllers[platform]!;
        if (scroll.hasClients) scroll.jumpTo(0);
      });
    }
  }

  Future<void> _refresh() async {
    final platform = _platform;
    final sources = _visiblePlatforms.toList();
    await Future.wait([
      for (final source in sources) _load(source, refresh: true),
    ]);
    if (!mounted || _platform != platform) return;
    // An offline refresh keeps all loaded pages and the reading position.
    if (sources.every(
      (source) =>
          _pages[source]!.result?.stale == true ||
          _pages[source]!.comments.isEmpty,
    )) {
      return;
    }
    _offsets[platform] = 0;
    final scroll = _scrollControllers[platform]!;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _loadMoreVisible({bool retry = false}) => Future.wait([
    for (final platform in _visiblePlatforms.toList())
      _loadMore(platform, retry: retry),
  ]);

  Future<void> _loadMore(
    SongCommentPlatform platform, {
    bool retry = false,
  }) async {
    final page = _pages[platform]!;
    if (page.loading ||
        page.loadingMore ||
        !page.hasMore ||
        (page.moreFailed && !retry)) {
      return;
    }
    final request = page.request;
    final nextPage = page.nextPage;
    setState(() {
      page.loadingMore = true;
      page.moreFailed = false;
    });
    SongCommentsResult result;
    try {
      result = await repository.load(
        widget.query,
        platform,
        page: nextPage,
        cursor: page.nextCursor,
      );
    } catch (_) {
      result = SongCommentsResult(
        platform: platform,
        status: SongCommentsStatus.unavailable,
        pageUrl: widget.query.searchUrl(platform),
      );
    }
    if (!mounted || request != page.request) return;
    setState(() {
      page.loadingMore = false;
      if (result.status != SongCommentsStatus.ready) {
        page.moreFailed = true;
        return;
      }
      final comments = _unique([...page.comments, ...result.comments]);
      page.hasMore = result.hasMore && comments.length > page.comments.length;
      page.comments = comments;
      page.nextPage = nextPage + 1;
      page.nextCursor = result.nextCursor;
      _appendCombined(platform, result.comments);
    });
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final loading = _visiblePlatforms.any((source) => _pages[source]!.loading);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(zh ? '歌曲热评' : 'Song comments'),
        titleTextStyle: widget.embedded
            ? Theme.of(context).textTheme.titleSmall
            : null,
        toolbarHeight: widget.embedded ? 42 : null,
        actions: [
          IconButton(
            key: const Key('comments-refresh'),
            tooltip: zh ? '刷新热评' : 'Refresh comments',
            onPressed: loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          MusicPopupMenuButton<String>(
            key: const Key('comments-more'),
            tooltip: zh ? '更多' : 'More',
            icon: const Icon(Icons.more_vert_rounded),
            initialValue: _platform?.name ?? 'all',
            onSelected: (value) => _selectPlatform(
              value == 'all' ? null : SongCommentPlatform.values.byName(value),
            ),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'all',
                checked: _platform == null,
                child: Text(
                  zh ? '全部展示' : 'All platforms',
                  key: const ValueKey('comments-platform-all'),
                ),
              ),
              for (final platform in SongCommentPlatform.values)
                CheckedPopupMenuItem(
                  value: platform.name,
                  checked: _platform == platform,
                  child: Text(
                    platform.label,
                    key: ValueKey('comments-platform-${platform.name}'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MusicUi.pagePadding,
                    8,
                    MusicUi.pagePadding,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.query.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.query.artist,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: comments.isEmpty && loading
                      ? _CommentsPlaceholder(
                          label: zh
                              ? '正在查找这首歌的热评…'
                              : 'Finding comments for this song…',
                        )
                      : ListView.separated(
                          key: PageStorageKey(
                            'comments-list-${_platform?.name ?? 'all'}',
                          ),
                          controller: _scrollControllers[_platform],
                          scrollCacheExtent: const ScrollCacheExtent.viewport(
                            1,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: MusicUi.pagePadding,
                            vertical: 4,
                          ),
                          itemCount: comments.length + 1,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          itemBuilder: (_, index) => index == comments.length
                              ? _footer()
                              : _CommentEntry(
                                  key: ValueKey(
                                    '${comments[index].platform.name}-${comments[index].comment.id}',
                                  ),
                                  comment: comments[index].comment,
                                  platform: comments[index].platform,
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final sources = _visiblePlatforms.toList();
    final loading = sources.any(
      (source) => _pages[source]!.loading || _pages[source]!.loadingMore,
    );
    final more = sources.any(
      (source) => _pages[source]!.hasMore && !_pages[source]!.moreFailed,
    );
    final failed = sources.any((source) => _pages[source]!.moreFailed);
    final unavailable = sources.any(
      (source) =>
          _pages[source]!.result?.status == SongCommentsStatus.unavailable,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          if (_comments.isEmpty && !loading) ...[
            Text(
              _emptyMessage(sources),
              key: const Key('comments-empty-message'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (sources.any(
              (source) =>
                  _pages[source]!.result?.status != SongCommentsStatus.ready ||
                  _pages[source]!.result?.stale == true,
            ))
              TextButton(
                key: ValueKey('comments-retry-${_platform?.name ?? 'all'}'),
                onPressed: _refresh,
                child: Text(zh ? '重试' : 'Retry'),
              ),
          ],
          if (loading) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text(zh ? '正在加载热评…' : 'Loading comments…'),
          ],
          if (failed)
            TextButton(
              key: const Key('comments-more-retry'),
              onPressed: () => _loadMoreVisible(retry: true),
              child: Text(zh ? '加载更多热评' : 'Load more comments'),
            ),
          if (more && !loading && !failed)
            TextButton(
              key: const Key('comments-load-more'),
              onPressed: _loadMoreVisible,
              child: Text(zh ? '加载更多热评' : 'Load more comments'),
            ),
          if (!loading &&
              !more &&
              !failed &&
              !unavailable &&
              _comments.isNotEmpty)
            Text(
              zh ? '已显示全部热评' : 'All hot comments loaded',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  String _emptyMessage(List<SongCommentPlatform> sources) {
    final results = [for (final source in sources) _pages[source]!.result];
    if (results.any(
      (r) => r?.status == SongCommentsStatus.unavailable || r?.stale == true,
    )) {
      return zh
          ? '暂时无法读取热评，请稍后重试'
          : 'Comments are unavailable. Please retry later.';
    }
    if (results.every((r) => r?.status == SongCommentsStatus.noMatch)) {
      return zh ? '还没有找到歌名、歌手与版本一致的歌曲' : 'No matching recording found.';
    }
    return zh ? '这首歌暂时没有公开热评' : 'No public hot comments yet.';
  }
}

List<SongComment> _unique(Iterable<SongComment> comments) {
  final seen = <String>{};
  return comments.where((comment) => seen.add(comment.id)).toList();
}

class _CommentsViewState {
  SongCommentsResult? result;
  List<SongComment> comments = [];
  int request = 0;
  int nextPage = 1;
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  bool moreFailed = false;
}

class _CommentEntry extends StatelessWidget {
  const _CommentEntry({
    super.key,
    required this.comment,
    required this.platform,
  });
  final SongComment comment;
  final SongCommentPlatform platform;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = comment.createdAt?.toLocal();
    final dateLabel = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final zh = AppStringsScope.of(context).isZh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.author.isEmpty
                          ? (zh ? '音乐听众' : 'Listener')
                          : comment.author,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (dateLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(dateLabel, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Semantics(
                label: '${comment.likes} ${zh ? '赞' : 'likes'}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _likesLabel(comment.likes, zh),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectionArea(
            child: Text(
              displayCommentText(comment.content),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            zh ? '来自${platform.label}' : 'From ${platform.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _likesLabel(int likes, bool zh) {
  if (zh && likes >= 10000) return '${(likes / 10000).toStringAsFixed(1)}万';
  if (!zh && likes >= 1000000) {
    return '${(likes / 1000000).toStringAsFixed(1)}M';
  }
  if (!zh && likes >= 1000) return '${(likes / 1000).toStringAsFixed(1)}K';
  return '$likes';
}

class _CommentsPlaceholder extends StatelessWidget {
  const _CommentsPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: SingleChildScrollView(
        padding: MusicUi.horizontalInsets,
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final width in [0.28, 1.0, 0.84, 0.62])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FractionallySizedBox(
                          widthFactor: width,
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
