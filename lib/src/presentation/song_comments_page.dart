import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../data/song_comments.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'comment_text.dart';

class SongCommentsPage extends StatefulWidget {
  const SongCommentsPage({super.key, required this.query, this.repository});
  final SongCommentQuery query;
  final SongCommentsRepository? repository;

  @override
  State<SongCommentsPage> createState() => _SongCommentsPageState();
}

class _SongCommentsPageState extends State<SongCommentsPage> {
  SongCommentPlatform _platform = SongCommentPlatform.netease;
  final _pages = {
    for (final platform in SongCommentPlatform.values)
      platform: _CommentsViewState(),
  };
  final _scrollControllers = <SongCommentPlatform, ScrollController>{};
  _CommentsViewState get _page => _pages[_platform]!;
  bool get zh => AppStringsScope.of(context).isZh;
  SongCommentsRepository get repository =>
      widget.repository ?? SongCommentsRepository.shared;

  @override
  void initState() {
    super.initState();
    for (final platform in SongCommentPlatform.values) {
      _scrollControllers[platform] = ScrollController()
        ..addListener(() {
          final controller = _scrollControllers[platform]!;
          if (_platform == platform &&
              controller.hasClients &&
              controller.position.extentAfter <
                  controller.position.viewportDimension.clamp(480.0, 1200.0)) {
            _loadMore(platform);
          }
        });
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectPlatform(SongCommentPlatform platform) {
    final current = _scrollControllers[_platform]!;
    if (current.hasClients) _page.scrollOffset = current.offset;
    setState(() => _platform = platform);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _platform != platform) return;
      final controller = _scrollControllers[platform]!;
      if (controller.hasClients) {
        controller.jumpTo(
          _page.scrollOffset.clamp(0, controller.position.maxScrollExtent),
        );
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    final platform = _platform;
    final page = _pages[platform]!;
    if (page.loading || (!refresh && page.result != null)) return;
    final request = ++page.request;
    setState(() {
      page.loading = true;
      page.loadingMore = false;
      page.moreFailed = false;
    });
    final result = await repository.load(
      widget.query,
      platform,
      refresh: refresh,
    );
    if (!mounted || request != page.request) return;
    setState(() {
      page.result = result;
      page.loading = false;
      // An offline refresh must not throw away pages the reader already has.
      if (result.stale && page.comments.isNotEmpty) return;
      page.comments = _unique(result.comments);
      page.nextPage = 1;
      page.nextCursor = result.nextCursor;
      page.hasMore = result.hasMore && page.comments.isNotEmpty;
    });
    if (refresh && !result.stale) {
      page.scrollOffset = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != page.request) return;
        final controller = _scrollControllers[platform]!;
        if (controller.hasClients) controller.jumpTo(0);
      });
    }
  }

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
    final result = await repository.load(
      widget.query,
      platform,
      page: nextPage,
      cursor: page.nextCursor,
    );
    if (!mounted || request != page.request) return;
    setState(() {
      page.loadingMore = false;
      if (result.status != SongCommentsStatus.ready) {
        page.moreFailed = true;
        return;
      }
      final comments = _unique([...page.comments, ...result.comments]);
      // Stop a repeated upstream page from causing an endless scroll loop.
      page.hasMore = result.hasMore && comments.length > page.comments.length;
      page.comments = comments;
      page.nextPage = nextPage + 1;
      page.nextCursor = result.nextCursor;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _page.result;
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '歌曲热评' : 'Song comments'),
        actions: [
          IconButton(
            key: const Key('comments-refresh'),
            tooltip: zh ? '刷新热评' : 'Refresh comments',
            onPressed: _page.loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 320;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        MusicUi.pagePadding,
                        compact ? 0 : 8,
                        MusicUi.pagePadding,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.query.title,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.query.artist,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: compact ? 8 : 18),
                          SegmentedButton<SongCommentPlatform>(
                            showSelectedIcon: false,
                            expandedInsets: EdgeInsets.zero,
                            style: ButtonStyle(
                              minimumSize: const WidgetStatePropertyAll(
                                Size(0, 48),
                              ),
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              textStyle: WidgetStatePropertyAll(
                                Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Theme.of(context).colorScheme.surface,
                              ),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              side: WidgetStatePropertyAll(
                                BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    MusicUi.coverRadius,
                                  ),
                                ),
                              ),
                            ),
                            segments: [
                              for (final platform in SongCommentPlatform.values)
                                ButtonSegment(
                                  value: platform,
                                  label: Text(
                                    platform.label,
                                    key: ValueKey(
                                      'comments-platform-${platform.name}',
                                    ),
                                  ),
                                ),
                            ],
                            selected: {_platform},
                            onSelectionChanged: (selected) =>
                                _selectPlatform(selected.single),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _page.loading
                          ? _CommentsPlaceholder(
                              label: zh
                                  ? '正在查找这首歌的热评…'
                                  : 'Finding comments for this song…',
                            )
                          : result == null ||
                                result.status != SongCommentsStatus.ready ||
                                _page.comments.isEmpty
                          ? _empty(result)
                          : ListView.separated(
                              key: PageStorageKey(
                                'comments-list-${_platform.name}',
                              ),
                              controller: _scrollControllers[_platform],
                              scrollCacheExtent:
                                  const ScrollCacheExtent.viewport(1),
                              padding: const EdgeInsets.symmetric(
                                horizontal: MusicUi.pagePadding,
                                vertical: 4,
                              ),
                              itemCount:
                                  _page.comments.length +
                                  (result.stale ? 1 : 0) +
                                  1,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              itemBuilder: (context, index) {
                                if (result.stale && index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      zh
                                          ? '暂时无法更新，显示上次缓存的热评'
                                          : 'Could not refresh. Showing cached comments.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  );
                                }
                                final commentIndex =
                                    index - (result.stale ? 1 : 0);
                                if (commentIndex == _page.comments.length) {
                                  return _paginationFooter();
                                }
                                return _CommentEntry(
                                  key: ValueKey(
                                    '${_platform.name}-${_page.comments[commentIndex].id}',
                                  ),
                                  comment: _page.comments[commentIndex],
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _paginationFooter() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 88),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _page.loadingMore
            ? Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Text(
                    zh ? '正在加载更多热评…' : 'Loading more comments…',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : _page.moreFailed
            ? TextButton(
                key: const Key('comments-more-retry'),
                onPressed: () => _loadMore(_platform, retry: true),
                child: Text(zh ? '加载失败，点击重试' : 'Could not load more. Retry'),
              )
            : _page.hasMore
            ? TextButton(
                key: const Key('comments-load-more'),
                onPressed: () => _loadMore(_platform),
                child: Text(zh ? '加载更多热评' : 'Load more comments'),
              )
            : Text(
                zh ? '已显示全部热评' : 'All hot comments loaded',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
      ),
    ),
  );

  Widget _empty(SongCommentsResult? result) {
    final message = switch (result?.status) {
      SongCommentsStatus.noMatch =>
        zh
            ? '还没有找到歌名、歌手与版本一致的歌曲'
            : 'No matching song, artist and version found.',
      SongCommentsStatus.ready =>
        zh ? '这首歌暂时没有公开热评' : 'No public hot comments for this song yet.',
      _ =>
        zh
            ? '暂时无法读取热评\n请稍后重试'
            : 'Comments are unavailable.\nPlease retry later.',
    };
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(MusicUi.pagePadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _load(refresh: true),
                  child: Text(zh ? '重试' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
  double scrollOffset = 0;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  bool moreFailed = false;
}

class _CommentEntry extends StatelessWidget {
  const _CommentEntry({super.key, required this.comment});
  final SongComment comment;
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
