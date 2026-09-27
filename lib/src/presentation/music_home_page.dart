import 'date_groups.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/download_use_case.dart';
import '../application/online_playlist_search.dart';
import '../application/online_playlist_tasks.dart';
import '../data/online_playlists.dart';
import 'online_playlist_page.dart';
import '../application/music_controller.dart';
import '../application/music_ui_message.dart';
import '../data/music_playlists.dart';
import '../data/music_charts.dart';
import '../data/music_resolver.dart';
import '../data/search_history_store.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'discover_charts.dart';
import 'download_manager_page.dart';
import 'list_search.dart';
import 'player_page.dart';
import 'playlist_actions.dart';
import 'playlist_download_progress.dart';
import 'settings_page.dart';
import 'screenshot_import_page.dart';
import 'swipe_to_skip.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({
    super.key,
    required this.controller,
    this.playlistRepository,
    this.searchHistoryStore,
  });

  final OnlinePlaylistRepository? playlistRepository;
  final SearchHistoryStore? searchHistoryStore;

  final MusicController controller;

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage>
    with WidgetsBindingObserver {
  static const _exitBackWindow = Duration(seconds: 2);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final OnlinePlaylistSearch _playlistSearch;
  late final SearchHistoryStore _searchHistory;
  bool _playlistMode = false;
  bool _showPlaylistResults = false;
  bool _historyEditMode = false;
  bool _keyboardVisible = false;
  DateTime? _lastEmptyBackAt;
  MusicUiMessage? _lastStatusSnackMessage;

  MusicController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _playlistSearch = OnlinePlaylistSearch(
      widget.playlistRepository ?? OnlinePlaylistRepository(),
    );
    _searchHistory = widget.searchHistoryStore ?? SearchHistoryStore();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(
      _searchHistory.load().then((_) {
        if (mounted) setState(() {});
      }),
    );
    unawaited(controller.initialize());
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (!_searchFocusNode.hasFocus) _historyEditMode = false;
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final visible = View.of(context).viewInsets.bottom > 0;
    if (_keyboardVisible && !visible && _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    _keyboardVisible = visible;
  }

  void _openMatchedPlaylist(MusicPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PlaylistDetailPage(
          controller: controller,
          selection: _LibraryListSpec.custom(playlist),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playlistSearch.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, _playlistSearch]),
      builder: (context, _) {
        final strings = AppStringsScope.of(context);
        _maybeShowStatusSnack(strings);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _handleRootBack(strings);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(strings.appTitle),
              actions: [
                IconButton(
                  tooltip: strings.downloads,
                  onPressed: _openDownloads,
                  icon: controller.hasActiveDownloads
                      ? const SizedBox.square(
                          key: ValueKey('home-download-spinner'),
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                ),
                IconButton(
                  tooltip: strings.playlists,
                  onPressed: _openLibrary,
                  icon: const Icon(Icons.queue_music),
                ),
                IconButton(
                  tooltip: strings.settings,
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _SearchHeader(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    playlistMode: _playlistMode,
                    onToggleMode: () => setState(() {
                      _playlistMode = !_playlistMode;
                      _historyEditMode = false;
                    }),
                    isSearching: _playlistMode
                        ? _playlistSearch.isLoading
                        : controller.isSearching,
                    onChanged: _handleSearchChanged,
                    onSearch: () => _submitSearch(_searchController.text),
                    onSubmitted: _submitSearch,
                    onImportScreenshots: _openScreenshotImport,
                  ),
                  if (_searchFocusNode.hasFocus)
                    Expanded(
                      child: _SearchHistoryPanel(
                        entries: _searchHistory.entries(
                          _playlistMode
                              ? SearchHistoryKind.playlist
                              : SearchHistoryKind.song,
                        ),
                        editing: _historyEditMode,
                        onLongPress: () =>
                            setState(() => _historyEditMode = true),
                        onDone: () => setState(() => _historyEditMode = false),
                        onSearch: _searchFromHistory,
                        onDelete: _removeHistory,
                      ),
                    )
                  else ...[
                    OnlinePlaylistTaskEntry(
                      controller: controller,
                      onOpenPlaylist: _openMatchedPlaylist,
                    ),
                    if (_showPlaylistResults)
                      Expanded(
                        child: OnlinePlaylistSearchPanel(
                          search: _playlistSearch,
                          controller: controller,
                          onOpenPlaylist: _openMatchedPlaylist,
                        ),
                      )
                    else if (_shouldShowSearchPanel)
                      Expanded(
                        child: _OnlineSearchPanel(
                          candidates: controller.candidates,
                          isSearching: controller.isSearching,
                          isCandidateBusy: controller.isCandidateDownloading,
                          isCandidateCached: controller.isCandidateCached,
                          error:
                              _localizedMessage(
                                strings,
                                controller.errorMessage,
                              ) ??
                              controller.errorDetail,
                          onRetry: () =>
                              controller.search(_searchController.text),
                          onSelect: controller.downloadCandidate,
                          onPlay: controller.playCandidate,
                        ),
                      )
                    else
                      Expanded(
                        child: _SearchBody(
                          controller: controller,
                          showDefaultLibrary: _searchController.text
                              .trim()
                              .isEmpty,
                          onOpenChart: _openChart,
                          onOpenLibrary: _openLibrary,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            bottomNavigationBar: _searchFocusNode.hasFocus
                ? null
                : _MiniPlayer(controller: controller),
          ),
        );
      },
    );
  }

  bool get _shouldShowSearchPanel {
    return _searchController.text.trim().isNotEmpty &&
        (controller.isSearching ||
            controller.candidates.isNotEmpty ||
            controller.errorMessage != null ||
            controller.errorDetail != null);
  }

  void _submitSearch(String query) {
    final term = query.trim();
    if (term.isEmpty) return;
    final kind = _playlistMode
        ? SearchHistoryKind.playlist
        : SearchHistoryKind.song;
    _searchFocusNode.unfocus();
    setState(() => _showPlaylistResults = _playlistMode);
    unawaited(
      _searchHistory.record(kind, term).then((_) {
        if (mounted) setState(() {});
      }),
    );
    if (_playlistMode) {
      _playlistSearch.search(term);
    } else {
      controller.search(term);
    }
  }

  void _searchFromHistory(String query) {
    _searchController.text = query;
    _submitSearch(query);
  }

  void _removeHistory(String query) {
    final kind = _playlistMode
        ? SearchHistoryKind.playlist
        : SearchHistoryKind.song;
    unawaited(
      _searchHistory.remove(kind, query).then((_) {
        if (!mounted) return;
        setState(() {
          if (_searchHistory.entries(kind).isEmpty) _historyEditMode = false;
        });
      }),
    );
  }

  void _handleSearchChanged(String value) {
    _showPlaylistResults = false;
    _playlistSearch.clear();
    _lastEmptyBackAt = null;
    if (controller.hasSearchState) {
      // 输入变化立即清空旧结果，避免旧搜索晚返回后把新关键词页面污染。
      controller.clearSearch();
    }
    setState(() {});
  }

  void _openScreenshotImport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScreenshotImportPage(
          controller: controller,
          openPickerOnStart: true,
        ),
      ),
    );
  }

  void _handleRootBack(AppStrings strings) {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
    if (_searchController.text.trim().isNotEmpty || controller.hasSearchState) {
      // 首页返回第一步只收起搜索态；用户再次返回才触发退出提示。
      _clearSearchInputAndState();
      return;
    }
    final now = DateTime.now();
    if (_lastEmptyBackAt == null ||
        now.difference(_lastEmptyBackAt!) > _exitBackWindow) {
      _lastEmptyBackAt = now;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.pressBackAgainToExit),
          behavior: SnackBarBehavior.floating,
          duration: _exitBackWindow,
        ),
      );
      return;
    }
    SystemNavigator.pop();
  }

  void _clearSearchInputAndState() {
    _lastEmptyBackAt = null;
    _showPlaylistResults = false;
    _searchController.clear();
    _playlistSearch.clear();
    controller.clearSearch();
    setState(() {});
  }

  void _maybeShowStatusSnack(AppStrings strings) {
    final message = controller.statusMessage;
    if (message == null) {
      _lastStatusSnackMessage = null;
      return;
    }
    if (!_shouldShowFloatingStatus(message) ||
        identical(_lastStatusSnackMessage, message)) {
      return;
    }
    _lastStatusSnackMessage = message;
    final text = _localizedMessage(strings, message);
    if (text == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_lastStatusSnackMessage, message)) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: _statusOpensDownloads(message)
              ? SnackBarAction(
                  label: strings.downloadManager,
                  onPressed: () => unawaited(_openDownloads()),
                )
              : null,
        ),
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(controller: controller),
      ),
    );
  }

  Future<void> _openDownloads() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => DownloadManagerPage(
          controller: controller,
          onOpenPlaylist: (playlist) => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => _PlaylistDetailPage(
                controller: controller,
                selection: _LibraryListSpec.custom(playlist),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLibrary() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _LibraryPage(controller: controller),
      ),
    );
  }

  Future<void> _openChart(MusicChart chart) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MusicChartPage(
          chart: chart,
          controller: controller,
          onSearchSong: (entry) {
            Navigator.of(context).pop();
            _searchController.text = entry.title;
            setState(() => _playlistMode = false);
            _submitSearch(entry.title);
          },
        ),
      ),
    );
  }
}

bool _shouldShowFloatingStatus(MusicUiMessage message) {
  return switch (message.code) {
    MusicUiMessageCode.alreadyInCache ||
    MusicUiMessageCode.downloadedToCache ||
    MusicUiMessageCode.downloadAlreadyRunning ||
    MusicUiMessageCode.downloadCanceled ||
    MusicUiMessageCode.playingCachedFile => true,
    _ => false,
  };
}

bool _statusOpensDownloads(MusicUiMessage message) {
  return switch (message.code) {
    MusicUiMessageCode.alreadyInCache ||
    MusicUiMessageCode.downloadedToCache ||
    MusicUiMessageCode.downloadAlreadyRunning ||
    MusicUiMessageCode.downloadCanceled => true,
    _ => false,
  };
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onChanged,
    required this.onSearch,
    required this.onSubmitted,
    required this.onImportScreenshots,
    required this.onToggleMode,
    this.playlistMode = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onImportScreenshots;
  final bool playlistMode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  hintText: playlistMode
                      ? (strings.isZh
                            ? '歌单名称或关键词'
                            : 'Playlist name or keywords')
                      : strings.searchHint,
                  prefixIcon: IconButton(
                    key: const ValueKey('search-mode-toggle'),
                    tooltip: playlistMode
                        ? (strings.isZh
                              ? '当前搜歌单，点击切换歌曲'
                              : 'Playlists: switch to songs')
                        : (strings.isZh
                              ? '当前搜歌曲，点击切换歌单'
                              : 'Songs: switch to playlists'),
                    onPressed: onToggleMode,
                    icon: Icon(
                      playlistMode ? Icons.queue_music : Icons.music_note,
                    ),
                  ),
                  suffixIcon: playlistMode
                      ? null
                      : IconButton(
                          tooltip: strings.importScreenshots,
                          onPressed: onImportScreenshots,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: playlistMode
                  ? (strings.isZh ? '搜歌单' : 'Search playlists')
                  : strings.searchOnline,
              onPressed: isSearching ? null : onSearch,
              icon: isSearching
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHistoryPanel extends StatelessWidget {
  const _SearchHistoryPanel({
    required this.entries,
    required this.editing,
    required this.onLongPress,
    required this.onDone,
    required this.onSearch,
    required this.onDelete,
  });

  final List<String> entries;
  final bool editing;
  final VoidCallback onLongPress;
  final VoidCallback onDone;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    return ListView(
      key: const ValueKey('search-history-panel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Row(
          children: [
            Text(
              strings.isZh ? '搜索历史' : 'Search history',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (editing) ...[
              const Spacer(),
              TextButton(
                onPressed: onDone,
                child: Text(strings.isZh ? '完成' : 'Done'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Text(
            strings.isZh ? '暂无搜索历史' : 'No search history yet',
            style: TextStyle(color: colors.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                Material(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('search-history-$entry'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSearch(entry),
                    onLongPress: onLongPress,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxWidth - (editing ? 28 : 0),
                            ),
                            child: Text(
                              entry,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          if (editing) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              key: ValueKey('search-history-delete-$entry'),
                              onTap: () => onDelete(entry),
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  semanticLabel: strings.isZh
                                      ? '删除$entry'
                                      : 'Delete $entry',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _OnlineSearchPanel extends StatelessWidget {
  const _OnlineSearchPanel({
    required this.candidates,
    required this.isSearching,
    required this.isCandidateBusy,
    required this.isCandidateCached,
    required this.error,
    required this.onRetry,
    required this.onSelect,
    required this.onPlay,
  });

  final List<MusicSearchCandidate> candidates;
  final bool isSearching;
  final bool Function(MusicSearchCandidate candidate) isCandidateBusy;
  final bool Function(MusicSearchCandidate candidate) isCandidateCached;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<MusicSearchCandidate> onSelect;
  final ValueChanged<MusicSearchCandidate> onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return Material(
      color: colors.surfaceContainerLowest,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.outlineVariant),
            bottom: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: Column(
          children: [
            if (isSearching)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            if (error != null)
              ListTile(
                dense: true,
                leading: Icon(Icons.error_outline, color: colors.error),
                title: Text(error!),
                trailing: IconButton(
                  tooltip: strings.retrySearch,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            if (candidates.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    final isBusy = isCandidateBusy(candidate);
                    final isCached = isCandidateCached(candidate);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.secondaryContainer,
                        foregroundColor: colors.onSecondaryContainer,
                        child: isBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _sourceMarker(candidate),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                      ),
                      title: Text(
                        candidate.name.isEmpty
                            ? candidate.keyword
                            : candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _candidateSubtitle(candidate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCached)
                            IconButton(
                              tooltip: strings.play,
                              onPressed: isBusy
                                  ? null
                                  : () => onPlay(candidate),
                              icon: const Icon(Icons.play_arrow),
                            ),
                          IconButton(
                            tooltip: isCached
                                ? strings.downloadAgain
                                : strings.download,
                            onPressed: isBusy
                                ? null
                                : () => onSelect(candidate),
                            icon: const Icon(Icons.download_for_offline),
                          ),
                        ],
                      ),
                      onTap: isBusy
                          ? null
                          : () => isCached
                                ? onPlay(candidate)
                                : onSelect(candidate),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.controller,
    required this.showDefaultLibrary,
    required this.onOpenChart,
    required this.onOpenLibrary,
  });

  final MusicController controller;
  final bool showDefaultLibrary;
  final ValueChanged<MusicChart> onOpenChart;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    if (controller.isSearching) {
      return const SizedBox.shrink();
    }
    if (controller.candidates.isNotEmpty) {
      return const SizedBox.shrink();
    }
    if (!showDefaultLibrary) {
      return const _SearchEmptyPrompt();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      children: [
        _HomeLibrarySection(
          controller: controller,
          onOpenLibrary: onOpenLibrary,
        ),
        const SizedBox(height: 20),
        DiscoverChartsSection(onOpenChart: onOpenChart),
      ],
    );
  }
}

class _SearchEmptyPrompt extends StatelessWidget {
  const _SearchEmptyPrompt();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final child = Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore, size: 52, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            AppStringsScope.of(context).searchEmptyTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            AppStringsScope.of(context).searchEmptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
    return Center(child: child);
  }
}

class _HomeLibrarySection extends StatelessWidget {
  const _HomeLibrarySection({
    required this.controller,
    required this.onOpenLibrary,
  });

  final MusicController controller;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.onlinePlaylistTasks,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final playlists = _playlistsWithActiveSyncFirst(controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.homeLibraryTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('home-manage-playlists'),
              onPressed: onOpenLibrary,
              icon: const Icon(Icons.queue_music),
              label: Text(strings.managePlaylists),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _HomeLibraryTile(
          key: const ValueKey('home-favorites-entry'),
          icon: Icons.favorite,
          title: strings.favorite,
          subtitle: _librarySubtitle(
            strings,
            controller.favoriteTracks,
            emptyText: strings.noFavoritesYet,
          ),
          onTap: () => _openList(context, _LibraryListSpec.favorite()),
        ),
        const SizedBox(height: 20),
        Text(
          strings.customPlaylists,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (playlists.isEmpty)
          _HomeLibraryTile(
            key: const ValueKey('home-empty-custom-playlists'),
            icon: Icons.playlist_add,
            title: strings.noCustomPlaylists,
            subtitle: strings.createPlaylistHomeHint,
            onTap: onOpenLibrary,
          )
        else
          for (final playlist in playlists.take(4)) ...[
            _HomeLibraryTile(
              key: ValueKey('home-playlist-${playlist.id}'),
              icon: Icons.queue_music,
              title: playlist.name,
              subtitle: _homePlaylistSubtitle(controller, playlist, strings),
              onTap: () =>
                  _openList(context, _LibraryListSpec.custom(playlist)),
            ),
            const SizedBox(height: 8),
          ],
        if (playlists.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenLibrary,
              icon: const Icon(Icons.more_horiz),
              label: Text(strings.managePlaylists),
            ),
          ),
      ],
    );
  }

  Future<void> _openList(BuildContext context, _LibraryListSpec selection) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _PlaylistDetailPage(controller: controller, selection: selection),
      ),
    );
  }
}

class _HomeLibraryTile extends StatelessWidget {
  const _HomeLibraryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: colors.surfaceContainerHighest,
      leading: Icon(icon, color: colors.primary),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

String _librarySubtitle(
  AppStrings strings,
  List<Track> tracks, {
  required String emptyText,
  bool includeCount = true,
}) {
  if (tracks.isEmpty) {
    return emptyText;
  }
  final preview = tracks.take(3).map((track) => track.title).join(' / ');
  return includeCount
      ? '${strings.songCount(tracks.length)} · $preview'
      : preview;
}

class _LibraryPage extends StatelessWidget {
  const _LibraryPage({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final strings = AppStringsScope.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.libraryTitle),
            actions: [
              IconButton(
                tooltip: strings.newPlaylist,
                onPressed: () => showCreatePlaylistDialog(context, controller),
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: strings.refresh,
                onPressed: controller.loadCache,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(child: _LibraryLanding(controller: controller)),
          bottomNavigationBar: _MiniPlayer(controller: controller),
        );
      },
    );
  }
}

class _LibraryLanding extends StatelessWidget {
  const _LibraryLanding({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.onlinePlaylistTasks,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final playlists = _playlistsWithActiveSyncFirst(controller);
    final strings = AppStringsScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (controller.isLoadingCache) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LibraryShortcutButton(
              selection: _LibraryListSpec.favorite(),
              count: controller.favoriteTracks.length,
              title: strings.favorite,
              onPressed: () => _openList(context, _LibraryListSpec.favorite()),
            ),
            _LibraryShortcutButton(
              selection: _LibraryListSpec.local(),
              count: controller.cachedTracks.length,
              title: strings.localLibrary,
              onPressed: () => _openList(context, _LibraryListSpec.local()),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          strings.customPlaylists,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (playlists.isEmpty)
          const _EmptyCustomPlaylists()
        else
          for (final playlist in playlists) ...[
            _CustomPlaylistTile(
              playlist: playlist,
              subtitle: _playlistSyncLabel(controller, playlist, strings),
              onTap: () =>
                  _openList(context, _LibraryListSpec.custom(playlist)),
            ),
            const Divider(height: 1),
          ],
        const SizedBox(height: 24),
        Text(
          strings.isZh ? '匹配歌单' : 'Matching playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OnlinePlaylistTaskList(
          controller: controller,
          onOpenPlaylist: (playlist) =>
              _openList(context, _LibraryListSpec.custom(playlist)),
        ),
      ],
    );
  }

  Future<void> _openList(BuildContext context, _LibraryListSpec selection) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _PlaylistDetailPage(controller: controller, selection: selection),
      ),
    );
  }
}

class _LibraryShortcutButton extends StatelessWidget {
  const _LibraryShortcutButton({
    required this.selection,
    required this.count,
    required this.title,
    required this.onPressed,
  });

  final _LibraryListSpec selection;
  final int count;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Icon(selection.icon, size: 18),
      label: Text('$title · ${AppStringsScope.of(context).songCount(count)}'),
    );
  }
}

class _EmptyCustomPlaylists extends StatelessWidget {
  const _EmptyCustomPlaylists();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.queue_music_outlined, size: 40, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            strings.noCustomPlaylists,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            strings.createPlaylistHint,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CustomPlaylistTile extends StatelessWidget {
  const _CustomPlaylistTile({
    required this.playlist,
    required this.subtitle,
    required this.onTap,
  });

  final MusicPlaylist playlist;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('custom-playlist-${playlist.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.queue_music),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

List<MusicPlaylist> _playlistsWithActiveSyncFirst(MusicController controller) {
  final ranked = controller.frequentlyUsedPlaylists;
  final activeIds = {
    for (final task in controller.onlinePlaylistTasks.tasks)
      if (_hasPendingPlaylistSync(task)) ?task.destination?.id,
  };
  return [
    ...ranked.where((playlist) => activeIds.contains(playlist.id)),
    ...ranked.where((playlist) => !activeIds.contains(playlist.id)),
  ];
}

String _playlistSyncLabel(
  MusicController controller,
  MusicPlaylist playlist,
  AppStrings strings,
) {
  final task = controller.onlinePlaylistTasks.autoSyncForDestination(
    playlist.id,
  );
  if (task == null || !_hasPendingPlaylistSync(task)) return '';
  final matched = task.matches.length;
  final total = task.detail?.songs.length ?? task.loadTotal;
  if (task.autoSyncError) {
    return strings.isZh ? '同步失败 · 点击查看' : 'Sync failed · Tap to review';
  }
  if (!task.matching && !task.saving) {
    return strings.isZh
        ? '识别未完成或需核对 · 歌单已有 ${playlist.entries.length} 首'
        : 'Matching incomplete or needs review · ${playlist.entries.length} saved';
  }
  return strings.isZh
      ? '已识别 $matched/$total 首 · 歌单已有 ${playlist.entries.length} 首'
      : 'Matched $matched/$total · ${playlist.entries.length} in playlist';
}

bool _hasPendingPlaylistSync(OnlinePlaylistTask task) {
  final detail = task.detail;
  if (!task.autoSyncEnabled || task.destination == null || detail == null) {
    return false;
  }
  return task.matching ||
      task.saving ||
      task.autoSyncError ||
      task.matches.length < detail.songs.length ||
      detail.unavailable > 0 ||
      task.selected.any((index) => !task.savedRows.containsKey(index));
}

String _homePlaylistSubtitle(
  MusicController controller,
  MusicPlaylist playlist,
  AppStrings strings,
) {
  final status = _playlistSyncLabel(controller, playlist, strings);
  final tracks = controller.tracksForPlaylist(playlist);
  if (status.isNotEmpty && tracks.isEmpty) return status;
  final preview = _librarySubtitle(
    strings,
    tracks,
    emptyText: strings.noSongsInPlaylist,
    includeCount: false,
  );
  return status.isEmpty ? preview : '$status · $preview';
}

enum _LibraryListKind { local, favorite, custom }

enum _LibrarySortMode { time, initial, custom }

class _LibraryListSpec {
  const _LibraryListSpec({
    required this.id,
    required this.title,
    required this.icon,
    required this.kind,
  });

  factory _LibraryListSpec.local() {
    return const _LibraryListSpec(
      id: 'local',
      title: '',
      icon: Icons.library_music,
      kind: _LibraryListKind.local,
    );
  }

  factory _LibraryListSpec.favorite() {
    return const _LibraryListSpec(
      id: favoritePlaylistId,
      title: '',
      icon: Icons.favorite,
      kind: _LibraryListKind.favorite,
    );
  }

  factory _LibraryListSpec.custom(MusicPlaylist playlist) {
    return _LibraryListSpec(
      id: playlist.id,
      title: playlist.name,
      icon: Icons.queue_music,
      kind: _LibraryListKind.custom,
    );
  }

  final String id;
  final String title;
  final IconData icon;
  final _LibraryListKind kind;
}

class _ResolvedLibraryList {
  const _ResolvedLibraryList({
    required this.selection,
    required this.title,
    required this.icon,
    required this.tracks,
    this.playlist,
  });

  final _LibraryListSpec selection;
  final String title;
  final IconData icon;
  final List<Track> tracks;
  final MusicPlaylist? playlist;

  bool get isLocal => selection.kind == _LibraryListKind.local;
  bool get isFavorite => selection.kind == _LibraryListKind.favorite;
  bool get canManage => selection.kind == _LibraryListKind.custom;
  bool get canRemove => !isLocal;
  bool get canCustomSort => isFavorite || canManage;

  _ResolvedLibraryList copyWith({List<Track>? tracks}) {
    return _ResolvedLibraryList(
      selection: selection,
      title: title,
      icon: icon,
      tracks: tracks ?? this.tracks,
      playlist: playlist,
    );
  }
}

_ResolvedLibraryList _resolveLibraryList(
  MusicController controller,
  _LibraryListSpec selection,
  AppStrings strings,
) {
  switch (selection.kind) {
    case _LibraryListKind.local:
      return _ResolvedLibraryList(
        selection: selection,
        title: strings.localLibrary,
        icon: selection.icon,
        tracks: controller.cachedTracks,
      );
    case _LibraryListKind.favorite:
      return _ResolvedLibraryList(
        selection: selection,
        title: strings.favorite,
        icon: selection.icon,
        tracks: controller.favoriteTracks,
      );
    case _LibraryListKind.custom:
      final playlist = controller.customPlaylists
          .where((item) => item.id == selection.id)
          .firstOrNull;
      return _ResolvedLibraryList(
        selection: selection,
        title: playlist?.name ?? selection.title,
        icon: selection.icon,
        tracks: playlist == null
            ? const []
            : controller.tracksForPlaylist(playlist),
        playlist: playlist,
      );
  }
}

class _PlaylistDetailPage extends StatefulWidget {
  const _PlaylistDetailPage({
    required this.controller,
    required this.selection,
  });

  final MusicController controller;
  final _LibraryListSpec selection;

  @override
  State<_PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

/// Only this compact status listens to matching updates. Scrolling song rows
/// do not rebuild for every completed online lookup.
class _OnlinePlaylistSyncProgress extends StatelessWidget {
  const _OnlinePlaylistSyncProgress({
    required this.controller,
    required this.playlistId,
    required this.onOpenTask,
  });

  final MusicController controller;
  final String playlistId;
  final ValueChanged<OnlinePlaylistTask> onOpenTask;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.onlinePlaylistTasks,
    builder: (context, _) {
      final task = controller.onlinePlaylistTasks.autoSyncForDestination(
        playlistId,
      );
      final detail = task?.detail;
      if (task == null || detail == null) return const SizedBox.shrink();

      final total = detail.songs.length;
      final recognized = task.matches.length;
      final selected = task.selected.length;
      final synced = task.selected.where(task.savedRows.containsKey).length;
      final complete =
          !task.matching &&
          !task.saving &&
          !task.autoSyncError &&
          recognized >= total &&
          synced >= selected &&
          detail.unavailable == 0;
      if (complete) return const SizedBox.shrink();

      final zh = AppStringsScope.of(context).isZh;
      final colors = Theme.of(context).colorScheme;
      final String status;
      if (task.autoSyncError) {
        status = zh
            ? '同步失败 · 已同步 $synced/$selected 首'
            : 'Sync failed · $synced/$selected saved';
      } else if (task.saving) {
        status = zh
            ? '正在同步歌曲 · 已同步 $synced/$selected 首'
            : 'Syncing songs · $synced/$selected saved';
      } else if (task.matching) {
        status = zh
            ? '正在识别 $recognized/$total 首 · 已同步 $synced/$selected 首'
            : 'Matching $recognized/$total · $synced/$selected synced';
      } else if (recognized < total) {
        status = zh
            ? '识别未完成 $recognized/$total 首 · 已同步 $synced/$selected 首'
            : 'Matching incomplete $recognized/$total · $synced/$selected synced';
      } else if (synced < selected) {
        status = zh
            ? '还有 ${selected - synced} 首未找到或未同步'
            : '${selected - synced} songs unmatched or unsynced';
      } else {
        status = zh
            ? '${detail.unavailable} 首来源歌曲暂无法读取'
            : '${detail.unavailable} source songs unavailable';
      }
      final progress = task.matching
          ? (total == 0 ? null : recognized / total)
          : task.saving
          ? null
          : (selected == 0 ? 1.0 : synced / selected);
      return Padding(
        key: const ValueKey('online-playlist-sync-progress'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => onOpenTask(task),
                      child: Text(zh ? '查看识别' : 'View matches'),
                    ),
                  ],
                ),
                LinearProgressIndicator(value: progress, minHeight: 3),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  _LibrarySortMode _sortMode = _LibrarySortMode.time;
  String? _preparingTrackId;
  int _playRequestId = 0;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final List<String> _selectedTrackIds = <String>[];
  final List<String> _reorderDraftTrackIds = <String>[];
  String _query = '';
  String? _dateFilter;
  final _collapsedDates = <String>{};
  bool _isReorderEditing = false;
  bool _reorderDraftDirty = false;
  bool? _firstPlaylistOpening;
  bool _claimingPlaylistOpening = false;

  MusicController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    controller.addListener(_maybeStartWifiDownload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeStartWifiDownload();
        if (widget.selection.kind == _LibraryListKind.custom) {
          unawaited(controller.recordPlaylistUsage(widget.selection.id));
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PlaylistDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection.id != widget.selection.id) {
      _firstPlaylistOpening = null;
      _claimingPlaylistOpening = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeStartWifiDownload();
          if (widget.selection.kind == _LibraryListKind.custom) {
            unawaited(controller.recordPlaylistUsage(widget.selection.id));
          }
        }
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(_maybeStartWifiDownload);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _maybeStartWifiDownload() {
    if (!mounted) return;
    if (widget.selection.kind != _LibraryListKind.custom) return;
    final playlist = controller.customPlaylists
        .where((item) => item.id == widget.selection.id)
        .firstOrNull;
    if (playlist == null) return;
    if (_firstPlaylistOpening == null) {
      if (!_claimingPlaylistOpening) {
        _claimingPlaylistOpening = true;
        unawaited(_claimPlaylistOpening(playlist));
      }
      return;
    }
    if (playlist.entries.isEmpty || !controller.downloadPlaylistsOnWifi) {
      _firstPlaylistOpening = false;
      return;
    }
    if (!controller.isConnectivityKnown) return;
    final showProgress = _firstPlaylistOpening! && controller.isOnWifi;
    _firstPlaylistOpening = false;
    final download = controller.startWifiPlaylistDownloadOnce(
      playlist,
      showProgress: showProgress,
    );
    if (download != null) unawaited(download);
  }

  Future<void> _claimPlaylistOpening(MusicPlaylist playlist) async {
    bool first;
    try {
      first = await controller.claimFirstPlaylistOpening(playlist);
    } catch (_) {
      first = false;
    }
    if (!mounted || widget.selection.id != playlist.id) return;
    _firstPlaylistOpening = first;
    _claimingPlaylistOpening = false;
    _maybeStartWifiDownload();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final strings = AppStringsScope.of(context);
        final controller = widget.controller;
        final hasActiveFilter = _query.trim().isNotEmpty || _dateFilter != null;
        final rawList = _resolveLibraryList(
          controller,
          widget.selection,
          strings,
        );
        final effectiveSortMode = rawList.canManage
            ? _LibrarySortMode.custom
            : _sortMode;
        final sortedTracks = _sortLibraryTracks(
          controller,
          rawList,
          effectiveSortMode,
        );
        final visibleTracks = _isReorderEditing
            ? _tracksForDraftOrder(sortedTracks)
            : sortedTracks;
        final list = rawList.copyWith(
          tracks: filterTracksByQuery(visibleTracks, _query)
              .where(
                (track) =>
                    !rawList.isLocal ||
                    matchesDateFilter(track.cachedAt, _dateFilter),
              )
              .toList(),
        );
        final selectedTracks = _selectedTracks(sortedTracks);
        final selecting = _selectedTrackIds.isNotEmpty;
        final canAdjustOrder =
            rawList.canManage ||
            (rawList.isFavorite &&
                effectiveSortMode == _LibrarySortMode.custom);
        final canReorder = _isReorderEditing && !hasActiveFilter && !selecting;
        return PopScope(
          canPop: !_isReorderEditing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isReorderEditing) {
              unawaited(_requestExitReorderEditing(list));
            }
          },
          child: Scaffold(
            appBar: _isReorderEditing
                ? _reorderEditAppBar(context, list)
                : selecting
                ? _selectionAppBar(context, list, selectedTracks)
                : AppBar(
                    title: Text(list.title),
                    actions: [
                      if (list.isLocal)
                        DateFilterButton(
                          dates: rawList.tracks.map((t) => t.cachedAt),
                          value: _dateFilter,
                          zh: strings.isZh,
                          onChanged: (value) => setState(() {
                            _dateFilter = value;
                            _collapsedDates.clear();
                            _selectedTrackIds.clear();
                          }),
                        ),
                      if (canAdjustOrder)
                        IconButton(
                          key: const ValueKey('adjust-order-action'),
                          tooltip: strings.adjustOrder,
                          onPressed: hasActiveFilter
                              ? () => _showClearSearchToAdjustOrder(context)
                              : () => _startReorderEditing(sortedTracks),
                          icon: const Icon(Icons.drag_indicator),
                        ),
                      if (!list.canManage)
                        _LibrarySortButton(
                          mode: _sortMode,
                          timeLabel: list.isLocal
                              ? strings.sortByDownloadTime
                              : strings.sortByAddedTime,
                          showCustomOrder: list.isFavorite,
                          onChanged: (mode) => _changeSortMode(mode),
                        ),
                      if (list.canManage && list.playlist != null) ...[
                        IconButton(
                          tooltip: strings.renamePlaylist,
                          onPressed: () => _rename(context, list.playlist!),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: strings.deletePlaylist,
                          onPressed: () => _delete(context, list.playlist!),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ],
                  ),
            body: SafeArea(
              child: Column(
                children: [
                  if (!_isReorderEditing)
                    ListSearchField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (value) => setState(() {
                        _query = value;
                        _collapsedDates.clear();
                      }),
                      emptySuffix:
                          list.canManage &&
                              list.playlist != null &&
                              sortedTracks.isNotEmpty &&
                              !_searchFocusNode.hasFocus
                          ? Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: IconButton(
                                key: const ValueKey('download-all-playlist'),
                                tooltip:
                                    controller.isPlaylistDownloading(
                                      list.playlist!,
                                    )
                                    ? strings.downloadingPlaylist
                                    : strings.downloadAllPlaylist,
                                onPressed:
                                    controller.isPlaylistDownloading(
                                      list.playlist!,
                                    )
                                    ? null
                                    : () =>
                                          _downloadAllPlaylist(list.playlist!),
                                icon:
                                    controller.isPlaylistDownloading(
                                      list.playlist!,
                                    )
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_for_offline_outlined,
                                      ),
                              ),
                            )
                          : null,
                    ),
                  if (list.canManage && list.playlist != null)
                    _OnlinePlaylistSyncProgress(
                      controller: controller,
                      playlistId: list.playlist!.id,
                      onOpenTask: _openOnlineSyncTask,
                    ),
                  if (list.playlist != null &&
                      controller.playlistDownloadProgress(list.playlist!) !=
                          null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: PlaylistDownloadProgressView(
                        controller: controller,
                        playlist: list.playlist!,
                      ),
                    ),
                  Expanded(
                    child: controller.isLoadingCache
                        ? const Center(child: CircularProgressIndicator())
                        : _TrackList(
                            key: ValueKey(_dateFilter),
                            controller: controller,
                            list: list,
                            hasActiveFilter: hasActiveFilter,
                            expandDatesInitially:
                                _dateFilter != null || _query.trim().isNotEmpty,
                            collapsedDates: _collapsedDates,
                            onToggleDate: (day) => setState(() {
                              if (!_collapsedDates.remove(day)) {
                                _collapsedDates.add(day);
                              }
                            }),
                            groupByDate:
                                list.isLocal &&
                                effectiveSortMode == _LibrarySortMode.time,
                            isSelecting: selecting,
                            isReorderEditing: _isReorderEditing,
                            selectedTrackIds: _selectedTrackIds.toSet(),
                            canReorder: canReorder,
                            preparingTrackId: _preparingTrackId,
                            onPlayTrack: (track, index, tracks) =>
                                unawaited(_playFromList(track, index, tracks)),
                            onStartSelection: _startSelection,
                            onToggleSelection: _toggleSelection,
                            onReorder: (oldIndex, newIndex) =>
                                _reorderDraft(oldIndex, newIndex),
                          ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _isReorderEditing
                ? null
                : _MiniPlayer(controller: controller),
          ),
        );
      },
    );
  }

  void _openOnlineSyncTask(OnlinePlaylistTask task) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OnlinePlaylistPage(
          playlist: task.playlist,
          repository: task.repository,
          controller: controller,
          onOpenPlaylist: (_) => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _playFromList(Track track, int index, List<Track> tracks) async {
    if (_preparingTrackId == track.id) return;
    final requestId = ++_playRequestId;
    setState(() => _preparingTrackId = track.id);
    try {
      await controller.playTrack(
        track,
        index: index,
        queueTracks: tracks,
        playlistId: widget.selection.kind == _LibraryListKind.custom
            ? widget.selection.id
            : null,
      );
    } catch (error) {
      if (!mounted || requestId != _playRequestId) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppStringsScope.of(context).playTrackFailed(friendlyError(error)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted && requestId == _playRequestId) {
        setState(() => _preparingTrackId = null);
      }
    }
  }

  Future<void> _downloadAllPlaylist(MusicPlaylist playlist) async {
    final result = await controller.downloadPlaylist(playlist);
    if (!mounted) return;
    final strings = AppStringsScope.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            strings.playlistDownloadSummary(
              result.downloaded,
              result.skipped,
              result.failed,
            ),
          ),
        ),
      );
  }

  PreferredSizeWidget _selectionAppBar(
    BuildContext context,
    _ResolvedLibraryList list,
    List<Track> selectedTracks,
  ) {
    final strings = AppStringsScope.of(context);
    final hasSelection = selectedTracks.isNotEmpty;
    return AppBar(
      leading: IconButton(
        tooltip: strings.cancel,
        onPressed: _clearSelection,
        icon: const Icon(Icons.close),
      ),
      title: Text(strings.selectedSongCount(selectedTracks.length)),
      actions: [
        IconButton(
          tooltip: strings.selectAllVisible,
          onPressed: list.tracks.isEmpty
              ? null
              : () => _selectAllVisible(list.tracks),
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: strings.addToPlaylist,
          onPressed: hasSelection
              ? () => _addSelectedToPlaylist(context, selectedTracks)
              : null,
          icon: const Icon(Icons.playlist_add),
        ),
        if (list.isLocal)
          IconButton(
            tooltip: strings.deleteLocalMusic,
            onPressed: hasSelection
                ? () => _deleteSelectedLocalTracks(context, selectedTracks)
                : null,
            icon: const Icon(Icons.delete_outline),
          )
        else if (list.canRemove)
          IconButton(
            tooltip: strings.removeSelected,
            onPressed: hasSelection
                ? () => _removeSelectedFromCurrent(list, selectedTracks)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
      ],
    );
  }

  PreferredSizeWidget _reorderEditAppBar(
    BuildContext context,
    _ResolvedLibraryList list,
  ) {
    final strings = AppStringsScope.of(context);
    return AppBar(
      leading: IconButton(
        tooltip: strings.cancel,
        onPressed: () => _requestExitReorderEditing(list),
        icon: const Icon(Icons.close),
      ),
      title: Text(strings.adjustOrder),
      actions: [
        TextButton.icon(
          key: const ValueKey('save-order-action'),
          onPressed: () => _saveReorderDraft(list, exitAfterSave: true),
          icon: const Icon(Icons.check),
          label: Text(strings.finishOrderEdit),
        ),
      ],
    );
  }

  List<Track> _selectedTracks(List<Track> tracks) {
    final byId = {for (final track in tracks) track.id: track};
    return [
      for (final id in _selectedTrackIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  void _startSelection(Track track) {
    setState(() {
      if (!_selectedTrackIds.contains(track.id)) {
        _selectedTrackIds.add(track.id);
      }
    });
  }

  void _toggleSelection(Track track) {
    setState(() {
      if (_selectedTrackIds.contains(track.id)) {
        _selectedTrackIds.remove(track.id);
      } else {
        _selectedTrackIds.add(track.id);
      }
    });
  }

  void _selectAllVisible(List<Track> tracks) {
    setState(() {
      for (final track in tracks) {
        if (!_selectedTrackIds.contains(track.id)) {
          _selectedTrackIds.add(track.id);
        }
      }
    });
  }

  void _clearSelection() {
    setState(_selectedTrackIds.clear);
  }

  void _changeSortMode(_LibrarySortMode mode) {
    setState(() {
      _sortMode = mode;
      _selectedTrackIds.clear();
    });
  }

  void _startReorderEditing(List<Track> tracks) {
    setState(() {
      _isReorderEditing = true;
      _reorderDraftDirty = false;
      _selectedTrackIds.clear();
      _reorderDraftTrackIds
        ..clear()
        ..addAll(tracks.map((track) => track.id));
    });
  }

  List<Track> _tracksForDraftOrder(List<Track> fallbackTracks) {
    if (_reorderDraftTrackIds.isEmpty) {
      return fallbackTracks;
    }
    final byId = {for (final track in fallbackTracks) track.id: track};
    final ordered = <Track>[];
    for (final id in _reorderDraftTrackIds) {
      final track = byId.remove(id);
      if (track != null) {
        ordered.add(track);
      }
    }
    ordered.addAll(byId.values);
    return ordered;
  }

  void _reorderDraft(int oldIndex, int newIndex) {
    setState(() {
      final reorderedIds = reorderIdsForReorderableListView(
        _reorderDraftTrackIds,
        oldIndex,
        newIndex,
      );
      _reorderDraftTrackIds
        ..clear()
        ..addAll(reorderedIds);
      _reorderDraftDirty = true;
    });
  }

  Future<void> _requestExitReorderEditing(_ResolvedLibraryList list) async {
    if (!_reorderDraftDirty) {
      _discardReorderDraft();
      return;
    }
    final action = await _confirmDiscardReorderChanges(context);
    if (!mounted ||
        action == null ||
        action == _ReorderExitAction.keepEditing) {
      return;
    }
    switch (action) {
      case _ReorderExitAction.keepEditing:
        return;
      case _ReorderExitAction.discard:
        _discardReorderDraft();
      case _ReorderExitAction.save:
        await _saveReorderDraft(list, exitAfterSave: true);
    }
  }

  void _discardReorderDraft() {
    setState(() {
      _isReorderEditing = false;
      _reorderDraftDirty = false;
      _reorderDraftTrackIds.clear();
    });
  }

  Future<void> _saveReorderDraft(
    _ResolvedLibraryList list, {
    required bool exitAfterSave,
  }) async {
    final tracks = _tracksForDraftOrder(list.tracks);
    if (list.isFavorite) {
      await controller.reorderFavoriteTracks(tracks);
    } else if (list.playlist != null) {
      await controller.reorderPlaylistTracks(list.playlist!, tracks);
    }
    if (!mounted) {
      return;
    }
    if (exitAfterSave) {
      setState(() {
        _isReorderEditing = false;
        _reorderDraftDirty = false;
        _reorderDraftTrackIds.clear();
      });
    } else {
      setState(() => _reorderDraftDirty = false);
    }
  }

  void _showClearSearchToAdjustOrder(BuildContext context) {
    final strings = AppStringsScope.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.clearSearchToAdjustOrder)));
  }

  Future<void> _addSelectedToPlaylist(
    BuildContext context,
    List<Track> tracks,
  ) async {
    await showAddTracksToPlaylistSheet(context, controller, tracks);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _deleteSelectedLocalTracks(
    BuildContext context,
    List<Track> tracks,
  ) async {
    final confirmed = await _confirmDeleteLocalTracks(context, tracks);
    if (confirmed != true) {
      return;
    }
    await controller.deleteCachedTracks(tracks);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _removeSelectedFromCurrent(
    _ResolvedLibraryList list,
    List<Track> tracks,
  ) async {
    if (list.isFavorite) {
      await controller.removeTracksFromFavorites(tracks);
    } else if (list.playlist != null) {
      await controller.removeTracksFromPlaylist(list.playlist!, tracks);
    }
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _rename(BuildContext context, MusicPlaylist playlist) async {
    final strings = AppStringsScope.of(context);
    final name = await playlistNameDialog(
      context,
      title: strings.renamePlaylist,
      actionLabel: strings.rename,
      initialValue: playlist.name,
    );
    if (name != null) {
      await controller.renamePlaylist(playlist, name);
    }
  }

  Future<void> _delete(BuildContext context, MusicPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStringsScope.of(context);
        return AlertDialog(
          title: Text(strings.deletePlaylistTitle),
          content: Text(strings.deletePlaylistBody(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await controller.deletePlaylist(playlist);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

List<Track> reorderTracksForReorderableListView(
  List<Track> tracks,
  int oldIndex,
  int newIndex,
) {
  final reorderedIds = reorderIdsForReorderableListView(
    tracks.map((track) => track.id).toList(),
    oldIndex,
    newIndex,
  );
  final byId = {for (final track in tracks) track.id: track};
  return [
    for (final id in reorderedIds)
      if (byId[id] != null) byId[id]!,
  ];
}

List<String> reorderIdsForReorderableListView(
  List<String> ids,
  int oldIndex,
  int newIndex,
) {
  final reordered = [...ids];
  if (oldIndex < 0 || oldIndex >= reordered.length) {
    return reordered;
  }
  final id = reordered.removeAt(oldIndex);
  final targetIndex = newIndex.clamp(0, reordered.length).toInt();
  reordered.insert(targetIndex, id);
  return reordered;
}

int reorderTargetIndexFromRawReorder(int oldIndex, int newIndex) {
  return oldIndex < newIndex ? newIndex - 1 : newIndex;
}

class _LibrarySortButton extends StatelessWidget {
  const _LibrarySortButton({
    required this.mode,
    required this.timeLabel,
    required this.showCustomOrder,
    required this.onChanged,
  });

  final _LibrarySortMode mode;
  final String timeLabel;
  final bool showCustomOrder;
  final ValueChanged<_LibrarySortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return PopupMenuButton<_LibrarySortMode>(
      tooltip: strings.sort,
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: _LibrarySortMode.time, child: Text(timeLabel)),
        PopupMenuItem(
          value: _LibrarySortMode.initial,
          child: Text(strings.sortByInitial),
        ),
        if (showCustomOrder)
          PopupMenuItem(
            value: _LibrarySortMode.custom,
            child: Text(strings.customOrder),
          ),
      ],
      icon: const Icon(Icons.sort),
    );
  }
}

List<Track> _sortLibraryTracks(
  MusicController controller,
  _ResolvedLibraryList list,
  _LibrarySortMode mode,
) {
  final sorted = [...list.tracks];
  switch (mode) {
    case _LibrarySortMode.custom:
      break;
    case _LibrarySortMode.initial:
      sorted.sort(_compareTracksByInitial);
      break;
    case _LibrarySortMode.time:
      sorted.sort((a, b) {
        final left = _libraryTrackTime(controller, list, a);
        final right = _libraryTrackTime(controller, list, b);
        final byTime = right.compareTo(left);
        return byTime == 0 ? _compareTracksByInitial(a, b) : byTime;
      });
      break;
  }
  return sorted;
}

DateTime _libraryTrackTime(
  MusicController controller,
  _ResolvedLibraryList list,
  Track track,
) {
  if (list.isLocal) {
    return track.cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  if (list.isFavorite) {
    return controller.favoriteAddedAt(track) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  final playlist = list.playlist;
  if (playlist == null) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return controller.playlistTrackAddedAt(playlist, track) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

int _compareTracksByInitial(Track a, Track b) {
  final title = _trackSortKey(a).compareTo(_trackSortKey(b));
  if (title != 0) {
    return title;
  }
  return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
}

String _trackSortKey(Track track) {
  final raw = track.title.trim().isEmpty ? track.artist : track.title;
  return raw.trim().toLowerCase().replaceFirst(
    RegExp(r'^[^a-z0-9\u4e00-\u9fff]+'),
    '',
  );
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    super.key,
    required this.controller,
    required this.list,
    required this.hasActiveFilter,
    this.groupByDate = false,
    this.collapsedDates = const {},
    this.expandDatesInitially = false,
    this.onToggleDate,
    required this.isSelecting,
    required this.isReorderEditing,
    required this.selectedTrackIds,
    required this.canReorder,
    required this.preparingTrackId,
    required this.onPlayTrack,
    required this.onStartSelection,
    required this.onToggleSelection,
    required this.onReorder,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final bool hasActiveFilter;
  final bool groupByDate;
  final Set<String> collapsedDates;
  final bool expandDatesInitially;
  final ValueChanged<String>? onToggleDate;
  final bool isSelecting;
  final bool isReorderEditing;
  final Set<String> selectedTrackIds;
  final bool canReorder;
  final String? preparingTrackId;
  final void Function(Track track, int index, List<Track> tracks) onPlayTrack;
  final ValueChanged<Track> onStartSelection;
  final ValueChanged<Track> onToggleSelection;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.valueOrNull,
    builder: (context, snapshot) => _buildList(context, snapshot.data?.id),
  );

  Widget _buildList(BuildContext context, String? activeId) {
    final tracks = list.tracks;
    final strings = AppStringsScope.of(context);
    if (tracks.isEmpty) {
      if (hasActiveFilter) {
        return _EmptyPlaylist(title: strings.noMatchingTracks);
      }
      if (list.isLocal) {
        return const _EmptyLibrary();
      }
      return _EmptyPlaylist(
        title: list.isFavorite
            ? strings.noFavoritesYet
            : strings.noSongsInPlaylist,
      );
    }
    if (canReorder) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: tracks.length,
        // flutter_ohos does not support onReorderItem yet.
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) => onReorder(
          oldIndex,
          reorderTargetIndexFromRawReorder(oldIndex, newIndex),
        ),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _TrackTile(
            key: ValueKey('track-${track.id}'),
            active: track.id == activeId,
            controller: controller,
            list: list,
            track: track,
            tracks: tracks,
            index: index,
            isSelecting: isSelecting,
            isReorderEditing: isReorderEditing,
            selected: selectedTrackIds.contains(track.id),
            isPreparing: preparingTrackId == track.id,
            onPlayTrack: onPlayTrack,
            onStartSelection: onStartSelection,
            onToggleSelection: onToggleSelection,
            dragHandle: ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: strings.dragToReorder,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ),
          );
        },
      );
    }
    Widget tile(BuildContext context, int index) {
      final track = tracks[index];
      return _TrackTile(
        active: track.id == activeId,
        controller: controller,
        list: list,
        track: track,
        tracks: tracks,
        index: index,
        isSelecting: isSelecting,
        isReorderEditing: isReorderEditing,
        selected: selectedTrackIds.contains(track.id),
        isPreparing: preparingTrackId == track.id,
        onPlayTrack: onPlayTrack,
        onStartSelection: onStartSelection,
        onToggleSelection: onToggleSelection,
      );
    }

    if (groupByDate) {
      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          for (final group in groupByDateHierarchy(
            tracks.asMap().keys,
            (i) => tracks[i].cachedAt,
          ))
            DateHierarchySliver<int>(
              key: ValueKey(group.key),
              bucket: group,
              summary: (items) =>
                  '${items.length} ${strings.isZh ? '首' : 'songs'}',
              zh: strings.isZh,
              toggled: collapsedDates,
              onToggle: (key) => onToggleDate?.call(key),
              expandInitially: expandDatesInitially,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [tile(context, index), const Divider(height: 1)],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: tile,
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    super.key,
    required this.controller,
    this.active = false,
    required this.list,
    required this.track,
    required this.tracks,
    required this.index,
    required this.isSelecting,
    required this.isReorderEditing,
    required this.selected,
    required this.isPreparing,
    required this.onPlayTrack,
    required this.onStartSelection,
    required this.onToggleSelection,
    this.dragHandle,
  });

  final bool active;
  final MusicController controller;
  final _ResolvedLibraryList list;
  final Track track;
  final List<Track> tracks;
  final int index;
  final bool isSelecting;
  final bool isReorderEditing;
  final bool selected;
  final bool isPreparing;
  final void Function(Track track, int index, List<Track> tracks) onPlayTrack;
  final ValueChanged<Track> onStartSelection;
  final ValueChanged<Track> onToggleSelection;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: isReorderEditing
          ? const Icon(Icons.music_note_outlined)
          : isSelecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelection(track),
            )
          : IconButton.filledTonal(
              tooltip: isPreparing
                  ? strings.preparingPlayback
                  : active
                  ? strings.playing
                  : strings.play,
              onPressed: isPreparing
                  ? null
                  : () => onPlayTrack(track, index, tracks),
              icon: isPreparing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(active ? Icons.equalizer : Icons.play_arrow),
            ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        _trackSubtitle(track),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isReorderEditing
          ? dragHandle
          : isSelecting
          ? null
          : _TrackActions(controller: controller, list: list, track: track),
      onTap: isReorderEditing
          ? null
          : isSelecting
          ? () => onToggleSelection(track)
          : isPreparing
          ? null
          : () => onPlayTrack(track, index, tracks),
      onLongPress: isReorderEditing ? null : () => onStartSelection(track),
    );
  }
}

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.controller,
    required this.list,
    required this.track,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final favorite = controller.isFavorite(track);
    final strings = AppStringsScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: favorite
              ? strings.removeFromFavorites
              : strings.addToFavorites,
          onPressed: () => controller.toggleFavorite(track),
          icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
        ),
        IconButton(
          tooltip: strings.addToPlaylist,
          onPressed: () => showAddToPlaylistSheet(context, controller, track),
          icon: const Icon(Icons.playlist_add),
        ),
        PopupMenuButton<_TrackAction>(
          tooltip: strings.more,
          onSelected: (action) => _handle(context, action),
          itemBuilder: (context) {
            return [
              if (list.isLocal)
                PopupMenuItem(
                  value: _TrackAction.deleteLocal,
                  child: Text(strings.deleteLocalMusic),
                ),
              if (list.canRemove)
                PopupMenuItem(
                  value: _TrackAction.removeFromCurrent,
                  child: Text(
                    list.isFavorite
                        ? strings.removeFromFavorites
                        : strings.removeFromThisPlaylist,
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, _TrackAction action) async {
    switch (action) {
      case _TrackAction.deleteLocal:
        final confirmed = await _confirmDeleteLocalTracks(context, [track]);
        if (confirmed == true) {
          await controller.deleteCachedTrack(track);
        }
      case _TrackAction.removeFromCurrent:
        if (list.isFavorite) {
          await controller.toggleFavorite(track);
          return;
        }
        final playlist = list.playlist;
        if (playlist != null) {
          await controller.removeTrackFromPlaylist(playlist, track);
        }
    }
  }
}

enum _TrackAction { deleteLocal, removeFromCurrent }

enum _ReorderExitAction { keepEditing, discard, save }

Future<_ReorderExitAction?> _confirmDiscardReorderChanges(
  BuildContext context,
) {
  final strings = AppStringsScope.of(context);
  return showDialog<_ReorderExitAction>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.discardOrderChangesTitle),
        content: Text(strings.discardOrderChangesBody),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ReorderExitAction.keepEditing),
            child: Text(strings.keepEditing),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ReorderExitAction.discard),
            child: Text(strings.discardChanges),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ReorderExitAction.save),
            child: Text(strings.saveAndExit),
          ),
        ],
      );
    },
  );
}

Future<bool?> _confirmDeleteLocalTracks(
  BuildContext context,
  List<Track> tracks,
) {
  final strings = AppStringsScope.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.deleteLocalMusicTitle(tracks.length)),
        content: Text(strings.deleteLocalMusicBody(tracks.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      );
    },
  );
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItemStream,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<PlaybackState>(
          stream: controller.playbackStateStream,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data ?? PlaybackState();
            final strings = AppStringsScope.of(context);
            return Material(
              elevation: 12,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SafeArea(
                top: false,
                child: SwipeToSkip(
                  key: const ValueKey('mini-player-swipe-area'),
                  onNext: controller.next,
                  onPrevious: controller.previous,
                  child: InkWell(
                    onTap: () => _openPlayer(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.album),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: strings.previous,
                            onPressed: controller.previous,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          IconButton(
                            tooltip: state.playing
                                ? strings.pause
                                : strings.play,
                            onPressed: controller.togglePlayPause,
                            icon: Icon(
                              state.playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          IconButton(
                            tooltip: strings.next,
                            onPressed: controller.next,
                            icon: const Icon(Icons.skip_next),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPlayer(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => PlayerPage(controller: controller),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined, size: 48, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              strings.noCachedMusic,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              strings.noCachedMusicBody,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 48, color: colors.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              strings.emptyPlaylistBody,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _trackSubtitle(Track track) {
  final parts = [
    if (track.subtitle.isNotEmpty) track.subtitle,
    if (track.sizeLabel.isNotEmpty) track.sizeLabel,
  ];
  return parts.join(' - ');
}

String? _localizedMessage(AppStrings strings, MusicUiMessage? message) {
  if (message == null) {
    return null;
  }
  return switch (message.code) {
    MusicUiMessageCode.noOnlineMatchesFound => strings.noOnlineMatchesFound,
    MusicUiMessageCode.resolving => strings.resolvingTrack(message.subject),
    MusicUiMessageCode.downloading => strings.downloadingTrack(message.subject),
    MusicUiMessageCode.downloadingBytes => strings.downloadingBytes(
      message.value,
    ),
    MusicUiMessageCode.downloadingPercent => strings.downloadingPercent(
      message.value,
    ),
    MusicUiMessageCode.alreadyInCache => strings.alreadyInCache,
    MusicUiMessageCode.downloadedToCache => strings.downloadedToCache,
    MusicUiMessageCode.downloadAlreadyRunning => strings.downloadAlreadyRunning,
    MusicUiMessageCode.downloadCanceled => strings.downloadCanceled,
    MusicUiMessageCode.playingCachedFile => strings.playingCachedFile,
  };
}

String _candidateSubtitle(MusicSearchCandidate candidate) {
  final parts = [
    if (candidate.artist.isNotEmpty) candidate.artist,
    if (candidate.album.isNotEmpty) candidate.album,
    if (_qualityAndSize(candidate).isNotEmpty) _qualityAndSize(candidate),
  ];
  return parts.join(' - ');
}

String _qualityAndSize(MusicSearchCandidate candidate) {
  MusicQuality? quality;
  for (final item in candidate.qualities) {
    if (item.format.trim().isNotEmpty) {
      quality = item;
      break;
    }
  }
  if (quality == null) {
    return '';
  }
  final format = quality.format.trim().toUpperCase();
  final size = quality.size.trim();
  if (candidate.source == MusicDataSource.flac && format == 'FLAC') {
    return size;
  }
  if (size.isEmpty) {
    return format;
  }
  return '$format · $size';
}

String _sourceMarker(MusicSearchCandidate candidate) {
  return switch (candidate.source) {
    MusicDataSource.buguyy => '布谷',
    MusicDataSource.flac => 'FLAC',
    MusicDataSource.auto => 'AUTO',
    MusicDataSource.lan => 'LAN',
  };
}
