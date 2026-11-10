import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'app_page_route.dart';
import 'duo_scaffold.dart';
import 'native_shell.dart';
import 'initial_song_scroll.dart';
import 'desktop_home.dart';
import 'desktop_ui.dart';
import 'desktop_music_shell.dart';
import 'desktop_scope.dart';
import 'app_popup_menu.dart';
import 'playlist_sliver_header.dart';
import 'playlist_sync_button.dart';
import 'mini_player.dart';
import 'mobile_chrome.dart';
import 'playback_queue.dart';
import 'player_page.dart';
import 'date_groups.dart';
import 'distinct_stream_builder.dart';
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
import '../data/playlist_usage_store.dart';
import '../data/music_charts.dart';
import '../data/music_resolver.dart';
import '../data/search_history_store.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'discover_charts.dart';
import 'download_manager_page.dart';
import 'list_search.dart';
import 'playlist_actions.dart';
import 'playlist_download_progress.dart';
import 'settings_page.dart';
import 'screenshot_import_page.dart';
import 'song_source_page.dart';
import 'app_update_page.dart';
import 'song_cache_progress.dart';
import 'playlist_source_progress.dart';
import 'app_theme.dart';
import 'design/controls.dart';
import 'design/glass_tab_bar.dart';
import 'design/record_sleeve.dart';
import 'listening_stats_page.dart';
import 'music_thumbnail.dart';
import 'file_sharing.dart';
import 'song_actions.dart';
import 'design/adaptive_layout.dart';
import 'design/app_icons.dart';

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

  final _desktopKey = GlobalKey<DesktopMusicShellState>();
  NavigatorState get _contentNavigator =>
      _desktopKey.currentState?.navigator ?? Navigator.of(context);
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final OnlinePlaylistSearch _playlistSearch;
  late final SearchHistoryStore _searchHistory;
  int _tab = 0;
  // Tabs are built on first visit: opening the app must not start the
  // download and settings pages' own loading.
  final _visitedTabs = {0};

  // These tabs listen for what they show themselves. Kept as the same
  // widgets, they are left alone when switching tabs rebuilds this page;
  // rebuilding all of them made every switch a 30–45 ms frame on 77.
  late final Widget _libraryTab = _LibraryPage(controller: controller);
  late final Widget _downloadsTab = DownloadManagerPage(
    controller: controller,
    onOpenPlaylist: _openMatchedPlaylist,
  );
  late final Widget _settingsTab = SettingsPage(controller: controller);
  bool _playlistMode = false;
  bool _showPlaylistResults = false;
  bool _historyEditMode = false;
  bool _keyboardVisible = false;
  bool _leftApp = false;
  DateTime? _lastEmptyBackAt;
  MusicUiMessage? _lastStatusSnackMessage;
  String? _preparingCandidateKey;
  int _candidatePlayRequest = 0;
  late final StreamSubscription<PlaybackState> _playbackErrorSubscription;

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
    _playbackErrorSubscription = controller.playbackStateStream.listen((state) {
      if (state.processingState != AudioProcessingState.error ||
          state.errorMessage == null ||
          !mounted) {
        return;
      }
      _showPlaybackError(state.errorMessage!);
    });
    unawaited(
      _searchHistory.load().then((_) {
        if (mounted) setState(() {});
      }),
    );
    unawaited(controller.initialize());
    // The system tab bar on iOS reports taps here; its mini player opens the
    // full player through the same navigator the Flutter strip would use.
    NativeShell.instance.onTabSelected = _selectTab;
    // Android: the floating bars over the navigator report here the same way.
    MobileChrome.instance
      ..onTabSelected = _selectTab
      ..onOpenPlayer = () {
        if (mounted) {
          unawaited(openPlayerPage(_contentNavigator.context, controller));
        }
      }
      ..onOpenQueue = () {
        if (mounted) {
          unawaited(showPlaybackQueue(_contentNavigator.context, controller));
        }
      };
    NativeShell.instance.onOpenPlayer = () {
      if (mounted) unawaited(openPlayerPage(_contentNavigator.context, controller));
    };
    NativeShell.instance.onOpenQueue = () {
      if (mounted) unawaited(showPlaybackQueue(_contentNavigator.context, controller));
    };
    NativeShell.instance.onOpenLyrics = () {
      if (mounted) unawaited(openLyricsPage(_contentNavigator.context, controller));
    };
    NativeShell.instance.onOpenComments = () {
      if (mounted) {
        unawaited(openSongCommentsPage(_contentNavigator.context, controller));
      }
    };
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _leftApp = true;
    if (state == AppLifecycleState.resumed && _leftApp) {
      _leftApp = false;
      unawaited(controller.refreshSourceAvailability(networkChanged: true));
    }
  }

  void _openMatchedPlaylist(MusicPlaylist playlist) {
    _contentNavigator.push(
      AppPageRoute<void>(
        settings: const RouteSettings(name: 'playlist-detail'),
        builder: (_) => _PlaylistDetailPage(
          controller: controller,
          selection: _LibraryListSpec.custom(playlist),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (NativeShell.instance.onTabSelected == _selectTab) {
      NativeShell.instance.onTabSelected = null;
      NativeShell.instance.onOpenPlayer = null;
      NativeShell.instance.onOpenQueue = null;
      NativeShell.instance.onOpenLyrics = null;
      NativeShell.instance.onOpenComments = null;
    }
    if (MobileChrome.instance.onTabSelected == _selectTab) {
      MobileChrome.instance
        ..onTabSelected = null
        ..onOpenPlayer = null
        ..onOpenQueue = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _playlistSearch.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    unawaited(_playbackErrorSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, _playlistSearch]),
      builder: (context, _) {
        final strings = AppStringsScope.of(context);
        _maybeShowStatusSnack(strings);
        if (isMacMusicDesktop) {
          return DesktopMusicShell(
            key: _desktopKey,
            controller: controller,
            home: Scaffold(body: _homeTab(strings)),
            library: _LibraryPage(controller: controller),
            downloads: DownloadManagerPage(
              controller: controller,
              onOpenPlaylist: _openMatchedPlaylist,
            ),
            settings: DesktopSettingsPage(controller: controller),
            focusSearch: _searchFocusNode.requestFocus,
            searchFor: _searchFromHistory,
            playlistBuilder: (id) {
              if (id == favoritePlaylistId) {
                return _PlaylistDetailPage(
                  controller: controller,
                  selection: _LibraryListSpec.favorite(),
                );
              }
              final playlist = controller.allPlaylists
                  .where((p) => p.id == id)
                  .firstOrNull;
              if (playlist == null) return _LibraryPage(controller: controller);
              return _PlaylistDetailPage(
                controller: controller,
                selection: _LibraryListSpec.custom(playlist),
              );
            },
          );
        }
        final tabs = [
          GlassTab(
            label: strings.isZh ? '首页' : 'Home',
            tooltip: strings.isZh ? '首页' : 'Home',
          ),
          GlassTab(
            label: strings.isZh ? '音乐库' : 'Library',
            tooltip: strings.isZh ? '音乐库' : 'Music library',
          ),
          GlassTab(
            label: strings.isZh ? '下载' : 'Downloads',
            tooltip: strings.downloads,
            marker: controller.hasActiveDownloads
                ? const SizedBox.square(
                    key: ValueKey('home-download-spinner'),
                    dimension: 11,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : null,
          ),
          GlassTab(
            label: strings.settings,
            tooltip: strings.settings,
            marker: UpdateBadge(
              updates: controller.appUpdates,
              child: const SizedBox(width: 2, height: 10),
            ),
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final sideNavigation =
                DuoScaffold.usesSystemRail(context) ||
                constraints.maxWidth >= 720 ||
                (constraints.maxWidth >= 560 &&
                    constraints.maxWidth > constraints.maxHeight * 1.25);
            // Phones without the iOS shell: the floating bars live over the
            // navigator and stay put across pushes, so the page draws none.
            final chrome = MobileChrome.instance;
            final floatingChrome = chrome.enabled && !sideNavigation;
            final homeBar = AppBar(
              title: Text(strings.homeLibraryTitle),
              titleTextStyle: MusicType.masthead(context, size: 30),
            );
            if (chrome.enabled) {
              chrome.publishTabs(
                MobileTabs(
                  labels: [for (final tab in tabs) tab.label],
                  index: _tab,
                  floating: !sideNavigation,
                  visible: !(_tab == 0 && _searchFocusNode.hasFocus),
                  downloading: controller.hasActiveDownloads,
                  updateBadge: controller.appUpdates.hasUpdate,
                ),
              );
            }
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _handleRootBack(strings);
              },
              child: DuoScaffold(
                railKey: const ValueKey('home-side-navigation'),
                preferSideNavigation: sideNavigation,
                navigationItems: [
                  for (final (i, tab) in tabs.indexed)
                    DuoRailItem(
                      icon: const [
                        CupertinoIcons.house,
                        CupertinoIcons.music_albums,
                        CupertinoIcons.arrow_down_circle,
                        CupertinoIcons.gear_alt,
                      ][i],
                      selectedIcon: const [
                        CupertinoIcons.house_fill,
                        CupertinoIcons.music_albums_fill,
                        CupertinoIcons.arrow_down_circle_fill,
                        CupertinoIcons.gear_alt_fill,
                      ][i],
                      label: tab.tooltip,
                      navigation: true,
                      selected: i == _tab,
                      marker: tab.marker,
                      badge: i == 3 && controller.appUpdates.hasUpdate
                          ? ''
                          : null,
                      onPressed: () => _selectTab(i),
                    ),
                ],
                extendBody: true,
                // Under the floating bars the home title sits in the home tab
                // itself, so every tab gets the same body: a bar that comes
                // and goes resizes the body, and the stack then lays out
                // every visited tab again on each switch.
                appBar: _tab != 0 || floatingChrome ? null : homeBar,
                body: IndexedStack(
                  index: _tab,
                  children: [
                    for (final (i, tab) in [
                      if (floatingChrome)
                        Column(
                          children: [
                            homeBar,
                            Expanded(
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                child: _homeTab(strings),
                              ),
                            ),
                          ],
                        )
                      else
                        _homeTab(strings),
                      _visitedTabs.contains(1)
                          ? _libraryTab
                          : const SizedBox.shrink(),
                      _visitedTabs.contains(2)
                          ? _downloadsTab
                          : const SizedBox.shrink(),
                      // Android keeps settings alive like the other tabs;
                      // elsewhere it is still made anew on each visit.
                      _tab == 3 || (chrome.enabled && _visitedTabs.contains(3))
                          ? _settingsTab
                          : const SizedBox.shrink(),
                    ].indexed)
                      TickerMode(enabled: i == _tab, child: tab),
                  ],
                ),
                bottomNavigationBar:
                    floatingChrome || (_tab == 0 && _searchFocusNode.hasFocus)
                    ? null
                    // With side navigation the strip is the mini player alone;
                    // pass it bare so the iOS shell recognises it and drops it
                    // (with the body's inset intact) while its own bar shows.
                    : sideNavigation
                    ? MiniPlayer(controller: controller)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MediaQuery.removePadding(
                            context: context,
                            removeBottom: true,
                            child: MiniPlayer(controller: controller),
                          ),
                          NavBlur(
                            child: GlassTabBar(
                              index: _tab,
                              onSelected: _selectTab,
                              tabs: tabs,
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  void _selectTab(int tab) {
    if (isMacMusicDesktop) {
      _desktopKey.currentState?.selectSection(
        const ['home', 'library', 'downloads', 'settings'][tab],
      );
      return;
    }
    if (tab == _tab) return;
    controller.performanceMonitor.setTab(
      const ['home', 'library', 'downloads', 'settings'][tab],
    );
    _searchFocusNode.unfocus();
    setState(() {
      _visitedTabs.add(tab);
      _tab = tab;
    });
  }

  Widget _homeTab(AppStrings strings) {
    final searchHeader = _SearchHeader(
      dense: isMacMusicDesktop,
      controller: _searchController,
      focusNode: _searchFocusNode,
      playlistMode: _playlistMode,
      onToggleMode: _toggleSearchMode,
      isSearching: _playlistMode
          ? _playlistSearch.isLoading
          : controller.isSearching,
      onChanged: _handleSearchChanged,
      onSearch: () => _submitSearch(_searchController.text),
      onSubmitted: _submitSearch,
      onImportScreenshots: _openScreenshotImport,
      onCancel: () {
        _searchFocusNode.unfocus();
        _clearSearchInputAndState();
      },
    );
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (isMacMusicDesktop)
            // Mac: the page title on the left and the search on the right,
            // or under it when a side panel leaves the page narrow.
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 2, 32, 22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        desktopGreeting(strings.isZh),
                        style: MusicType.eyebrow(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.homeLibraryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MusicType.masthead(context, size: 34),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 700) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        const SizedBox(height: 16),
                        searchHeader,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 24),
                      SizedBox(width: 440, child: searchHeader),
                    ],
                  );
                },
              ),
            )
          else
            searchHeader,
          if (_searchFocusNode.hasFocus)
            Expanded(
              child: _SearchHistoryPanel(
                entries: _searchHistory.entries(
                  _playlistMode
                      ? SearchHistoryKind.playlist
                      : SearchHistoryKind.song,
                ),
                editing: _historyEditMode,
                onLongPress: () => setState(() => _historyEditMode = true),
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
                  localTracks: controller.localSearchMatches,
                  isSearching: controller.isSearching,
                  isCandidateBusy: controller.isCandidateDownloading,
                  isCandidateLocal: controller.isCandidateManuallyDownloaded,
                  onPlayLocal: (track) => playOrOpenPlayer(
                    _contentNavigator.context,
                    controller,
                    track.id,
                    () => unawaited(
                      controller.playTrack(
                        track,
                        index: _indexOrNull(
                          controller.cachedTracks.indexOf(track),
                        ),
                      ),
                    ),
                  ),
                  isCandidatePreparing: (candidate) =>
                      _preparingCandidateKey == _candidatePlayKey(candidate),
                  error:
                      _localizedMessage(strings, controller.errorMessage) ??
                      controller.errorDetail,
                  onRetry: () => controller.search(_searchController.text),
                  onPlay: (candidate) =>
                      unawaited(_playSearchCandidate(candidate)),
                ),
              )
            else
              Expanded(
                child: _SearchBody(
                  controller: controller,
                  showDefaultLibrary: _searchController.text.trim().isEmpty,
                  onOpenChart: _openChart,
                  onOpenLibrary: _openLibrary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  bool get _shouldShowSearchPanel {
    return _searchController.text.trim().isNotEmpty &&
        (controller.isSearching ||
            controller.candidates.isNotEmpty ||
            controller.localSearchMatches.isNotEmpty ||
            controller.errorMessage != null ||
            controller.errorDetail != null);
  }

  void _toggleSearchMode() {
    setState(() {
      _playlistMode = !_playlistMode;
      _historyEditMode = false;
    });
    if (_playlistMode) {
      controller.clearSearch();
    } else {
      _playlistSearch.clear();
    }
    _submitSearch(_searchController.text);
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
    _contentNavigator.push(
      AppPageRoute<void>(
        settings: const RouteSettings(name: 'screenshot-import'),
        builder: (_) => ScreenshotImportPage(
          controller: controller,
          openPickerOnStart: true,
        ),
      ),
    );
  }

  void _handleRootBack(AppStrings strings) {
    if (_tab != 0) {
      _selectTab(0);
      return;
    }
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

  String _candidatePlayKey(MusicSearchCandidate candidate) =>
      '${candidate.source.storageValue}:${candidate.platform}:${candidate.id}';

  Future<void> _playSearchCandidate(MusicSearchCandidate candidate) async {
    final key = _candidatePlayKey(candidate);
    if (_preparingCandidateKey == key) return;
    final request = ++_candidatePlayRequest;
    setState(() => _preparingCandidateKey = key);
    try {
      await controller.playCandidate(candidate);
    } catch (error) {
      if (mounted && request == _candidatePlayRequest) {
        _showPlaybackError(friendlyError(error));
      }
    } finally {
      if (mounted && request == _candidatePlayRequest) {
        setState(() => _preparingCandidateKey = null);
      }
    }
  }

  void _showPlaybackError(String detail) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppStringsScope.of(context).playTrackFailed(detail)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDownloads() async => _selectTab(2);

  void _openLibrary() => _selectTab(1);

  Future<void> _openChart(MusicChart chart) {
    return _contentNavigator.push<void>(
      AppPageRoute(builder: (context) => _chartPage(controller, chart)),
    );
  }
}

Widget _chartPage(MusicController controller, MusicChart chart) =>
    MusicChartPage(
      chart: chart,
      controller: controller,
      playlistBuilder: (playlist, refresh, refreshing, error, updatedAt) =>
          buildChartPlaylistDetail(
            controller: controller,
            playlist: playlist,
            onRefresh: refresh,
            refreshing: refreshing,
            error: error,
            updatedAt: updatedAt,
          ),
    );

/// The same detail view used by saved playlists, with chart refresh controls.
Widget buildChartPlaylistDetail({
  required MusicController controller,
  required MusicPlaylist playlist,
  VoidCallback? onRefresh,
  bool refreshing = false,
  String? error,
  String? updatedAt,
}) => _PlaylistDetailPage(
  controller: controller,
  selection: _LibraryListSpec.custom(playlist),
  onRefresh: onRefresh,
  refreshing: refreshing,
  refreshError: error,
  chartUpdatedAt: updatedAt,
);

bool _shouldShowFloatingStatus(MusicUiMessage message) {
  return switch (message.code) {
    MusicUiMessageCode.alreadyInCache ||
    MusicUiMessageCode.downloadedToCache ||
    MusicUiMessageCode.downloadAlreadyRunning ||
    MusicUiMessageCode.downloadCanceled => true,
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
    required this.onCancel,
    required this.onToggleMode,
    this.playlistMode = false,
    this.dense = false,
  });

  /// Mac proportions: a slimmer field that sits beside the page title.
  final bool dense;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onImportScreenshots;
  final VoidCallback onCancel;
  final bool playlistMode;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    final compactMode =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(12) > 16;
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: dense
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: dense ? const TextStyle(fontSize: 14) : null,
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
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: dense ? 11 : 14,
                  ),
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
                    style: IconButton.styleFrom(
                      foregroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size(76, dense ? 38 : 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          MusicUi.fieldRadius,
                        ),
                      ),
                    ),
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!compactMode) ...[
                          Icon(
                            playlistMode ? AppIcons.queue : AppIcons.music,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          strings.isZh
                              ? (playlistMode ? '歌单' : '歌曲')
                              : (playlistMode ? 'Lists' : 'Songs'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Icon(AppIcons.chevronDown, size: 16),
                      ],
                    ),
                  ),
                  // The cancel button is the way out of a search: it clears
                  // the search and puts the home page back.
                  suffixIcon: controller.text.isEmpty
                      ? (playlistMode
                            ? null
                            : IconButton(
                                tooltip: strings.importScreenshots,
                                onPressed: onImportScreenshots,
                                icon: const Icon(AppIcons.scan),
                              ))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const ValueKey('home-search-cancel'),
                              tooltip: strings.isZh ? '取消搜索' : 'Cancel search',
                              onPressed: onCancel,
                              icon: const Icon(AppIcons.cancel, size: 20),
                            ),
                            if (!playlistMode)
                              IconButton(
                                tooltip: strings.importScreenshots,
                                onPressed: onImportScreenshots,
                                icon: const Icon(AppIcons.scan),
                              ),
                          ],
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MusicUi.fieldRadius),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MusicUi.fieldRadius),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: playlistMode
                  ? (strings.isZh ? '搜歌单' : 'Search playlists')
                  : strings.searchOnline,
              onPressed: isSearching ? null : onSearch,
              style: IconButton.styleFrom(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                disabledBackgroundColor: colors.surfaceContainerHighest,
                minimumSize: dense ? const Size(42, 42) : const Size(48, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(dense ? 12 : 15),
                ),
              ),
              icon: isSearching
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimaryContainer,
                      ),
                    )
                  : const Icon(AppIcons.search),
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
    final maxWidth = MediaQuery.sizeOf(context).width - 60;
    return ListView(
      key: const ValueKey('search-history-panel'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.isZh ? '搜索历史' : 'Search history',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (editing) ...[
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
                  color: colors.surfaceContainerHighest,
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
                                  AppIcons.close,
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

int? _indexOrNull(int index) => index < 0 ? null : index;

/// Marks a song already downloaded on this device so it is not fetched twice.
class _LocalSongTag extends StatelessWidget {
  const _LocalSongTag();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('local-song-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        AppStringsScope.of(context).localSong,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Row end for search results: the local tag, then the desktop play button.
/// Kept out of the title so tagging a row never moves its text.
Widget? _searchRowTrailing({required bool local, Widget? play}) {
  if (!local) return play;
  if (play == null) return const _LocalSongTag();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [const _LocalSongTag(), const SizedBox(width: 4), play],
  );
}

class _OnlineSearchPanel extends StatelessWidget {
  const _OnlineSearchPanel({
    required this.candidates,
    required this.localTracks,
    required this.isSearching,
    required this.isCandidateBusy,
    required this.isCandidateLocal,
    required this.onPlayLocal,
    required this.isCandidatePreparing,
    required this.error,
    required this.onRetry,
    required this.onPlay,
  });

  final List<MusicSearchCandidate> candidates;
  final List<Track> localTracks;
  final bool isSearching;
  final bool Function(MusicSearchCandidate candidate) isCandidateBusy;
  final bool Function(MusicSearchCandidate candidate) isCandidateLocal;
  final ValueChanged<Track> onPlayLocal;
  final bool Function(MusicSearchCandidate candidate) isCandidatePreparing;
  final String? error;
  final VoidCallback onRetry;
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
                leading: Icon(AppIcons.error, color: colors.error),
                title: Text(error!),
                trailing: IconButton(
                  tooltip: strings.retrySearch,
                  onPressed: onRetry,
                  icon: const Icon(AppIcons.refresh),
                ),
              ),
            if (candidates.isNotEmpty || localTracks.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: localTracks.length + candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index < localTracks.length) {
                      final track = localTracks[index];
                      return DesktopSongInteraction(
                        id: 'search-local:${track.id}',
                        onPlay: () => onPlayLocal(track),
                        builder: (tap, selected) => ListTile(
                          key: ValueKey('search-local-${track.id}'),
                          selected: selected,
                          trailing: _searchRowTrailing(
                            local: true,
                            play: DesktopMusicScope.maybeOf(context) == null
                                ? null
                                : IconButton(
                                    tooltip: strings.play,
                                    onPressed: () => onPlayLocal(track),
                                    icon: const Icon(AppIcons.play),
                                  ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: colors.primaryContainer,
                            foregroundColor: colors.onPrimaryContainer,
                            child: const Icon(AppIcons.downloaded, size: 20),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (track.artist.isNotEmpty) track.artist,
                              if (track.album.isNotEmpty) track.album,
                            ].join(' - '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: tap,
                        ),
                      );
                    }
                    final candidate = candidates[index - localTracks.length];
                    final isBusy = isCandidateBusy(candidate);
                    final isPreparing = isCandidatePreparing(candidate);
                    return DesktopSongInteraction(
                      id: 'search:${candidate.source}:${candidate.id}',
                      onPlay: isBusy || isPreparing
                          ? null
                          : () => onPlay(candidate),
                      builder: (tap, selected) => ListTile(
                        selected: selected,
                        trailing: _searchRowTrailing(
                          local: isCandidateLocal(candidate),
                          play: DesktopMusicScope.maybeOf(context) == null
                              ? null
                              : IconButton(
                                  tooltip: strings.play,
                                  onPressed: isBusy || isPreparing
                                      ? null
                                      : () => onPlay(candidate),
                                  icon: const Icon(AppIcons.play),
                                ),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                          child: isBusy || isPreparing
                              ? SizedBox.square(
                                  key: isPreparing
                                      ? const ValueKey('search-play-spinner')
                                      : null,
                                  dimension: 18,
                                  child: const CircularProgressIndicator(
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
                        onTap: tap,
                      ),
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
    if (DesktopMusicScope.maybeOf(context) != null) {
      Future<void> open(_LibraryListSpec selection) =>
          Navigator.of(context).push<void>(
            AppPageRoute(
              settings: const RouteSettings(name: 'playlist-detail'),
              builder: (context) => _PlaylistDetailPage(
                controller: controller,
                selection: selection,
              ),
            ),
          );
      return DesktopHomeDashboard(
        controller: controller,
        onOpenFavorites: () => open(_LibraryListSpec.favorite()),
        onOpenPlaylist: (playlist) => open(_LibraryListSpec.custom(playlist)),
        onOpenLibrary: onOpenLibrary,
        onOpenChart: onOpenChart,
      );
    }
    final library = _HomeLibrarySection(
      controller: controller,
      onOpenLibrary: onOpenLibrary,
    );
    final discover = DiscoverChartsSection(onOpenChart: onOpenChart);
    return LayoutBuilder(
      builder: (context, constraints) {
        final insets = MusicUi.scrollInsets(
          context,
          base: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        );
        // From the medium class up (Duo opened, tablets) the vertical stack
        // reflows into two columns instead of stretching across.
        if (constraints.maxWidth >= MusicLayout.mediumWidth) {
          return Row(
            key: const ValueKey('home-two-columns'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  key: const PageStorageKey('home-library-column'),
                  padding: insets.copyWith(right: 12),
                  children: [library],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const PageStorageKey('home-discover-column'),
                  padding: insets.copyWith(left: 12),
                  children: [discover],
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: insets,
          children: [library, const SizedBox(height: 24), discover],
        );
      },
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
          Icon(AppIcons.search, size: 52, color: colors.primary),
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
    final playlists = controller.frequentlyUsedPlaylists;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeLibraryTile(
          key: const ValueKey('home-favorites-entry'),
          icon: AppIcons.heart,
          highlighted: true,
          title: strings.isZh ? '我的收藏' : 'Favorites',
          subtitle: _librarySubtitle(
            strings,
            controller.favoriteTracks,
            emptyText: strings.noFavoritesYet,
          ),
          onTap: () => _openList(context, _LibraryListSpec.favorite()),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.isZh ? '常听歌单' : 'Your playlists',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('home-playlist-sort'),
              onPressed: () => controller.setPlaylistSortOrder(
                controller.playlistSortOrder == PlaylistSortOrder.recentlyOpened
                    ? PlaylistSortOrder.visitCount
                    : PlaylistSortOrder.recentlyOpened,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Tooltip(
                message:
                    controller.playlistSortOrder ==
                        PlaylistSortOrder.recentlyOpened
                    ? (strings.isZh
                          ? '切换为访问次数（近30天）'
                          : 'Switch to visits (30 days)')
                    : (strings.isZh ? '切换为最近打开' : 'Switch to recently opened'),
                child: MediaQuery.textScalerOf(context).scale(14) > 18
                    ? const Icon(AppIcons.swapVertical, size: 22)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.playlistSortOrder ==
                                    PlaylistSortOrder.recentlyOpened
                                ? (strings.isZh ? '最近打开' : 'Recent')
                                : (strings.isZh ? '访问次数' : 'Visits'),
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(width: 2),
                          const Icon(AppIcons.swapVertical, size: 18),
                        ],
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (playlists.isEmpty)
          _HomeLibraryTile(
            key: const ValueKey('home-empty-custom-playlists'),
            icon: AppIcons.playlistAdd,
            title: strings.noCustomPlaylists,
            subtitle: strings.createPlaylistHomeHint,
            onTap: onOpenLibrary,
          )
        else
          for (final playlist in playlists.take(4)) ...[
            _HomeLibraryTile(
              key: ValueKey('home-playlist-${playlist.id}'),
              icon: AppIcons.queue,
              artworkUri: _homePlaylistArtwork(controller, playlist),
              artworkLabel: playlist.name,
              title: playlist.name,
              subtitle: _homePlaylistSubtitle(controller, playlist, strings),
              onTap: () =>
                  _openList(context, _LibraryListSpec.custom(playlist)),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _openList(BuildContext context, _LibraryListSpec selection) {
    return Navigator.of(context).push<void>(
      AppPageRoute(
        settings: const RouteSettings(name: 'playlist-detail'),
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
    this.artworkUri,
    this.artworkLabel = '',
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Uri? artworkUri;
  final String artworkLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: highlighted ? colors.surfaceContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(MusicUi.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: highlighted
              ? const EdgeInsets.all(14)
              : const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              if (highlighted)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(MusicUi.coverRadius),
                  ),
                  child: Icon(icon, color: colors.primary, size: 21),
                )
              else
                MusicThumbnail(
                  uri: artworkUri,
                  label: artworkLabel,
                  icon: icon,
                ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                AppIcons.chevronRight,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uri? _homePlaylistArtwork(MusicController controller, MusicPlaylist playlist) {
  for (final track in controller.tracksForPlaylist(playlist)) {
    if (track.artworkUri != null) return track.artworkUri;
  }
  for (final entry in playlist.entries) {
    final url = entry.song?.coverUrl ?? '';
    if (url.isNotEmpty) return Uri.tryParse(url);
  }
  return null;
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
        return DuoScaffold(
          extendBody: true,
          appBar: AppBar(
            titleTextStyle: MusicType.masthead(context, size: 30),
            title: Text(strings.isZh ? '音乐库' : 'Music library'),
            actions: [
              IconButton(
                tooltip: strings.newPlaylist,
                onPressed: () => showCreatePlaylistDialog(context, controller),
                icon: const Icon(AppIcons.playlistAdd),
              ),
              IconButton(
                tooltip: strings.refresh,
                onPressed: controller.loadCache,
                icon: const Icon(AppIcons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: _LibraryLanding(controller: controller),
          ),
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
    final desktop = DesktopMusicScope.maybeOf(context) != null;
    // The Mac shows playlists as sleeves on a shelf.
    Widget sleeves(List<MusicPlaylist> playlists) => DesktopSleeveGrid(
      cards: [
        for (final playlist in playlists)
          DesktopSleeveCard(
            key: ValueKey('library-playlist-${playlist.id}'),
            title: playlist.name,
            subtitle: _playlistSyncLabel(controller, playlist, strings).isEmpty
                ? strings.songCount(playlist.entries.length)
                : _playlistSyncLabel(controller, playlist, strings),
            artwork: playlistArtworkUri(controller, playlist),
            onTap: () => _openList(context, _LibraryListSpec.custom(playlist)),
          ),
      ],
    );
    final heading = desktop
        ? DesktopUi.sectionTitle(context)
        : Theme.of(context).textTheme.titleMedium;
    return ListView(
      padding: MusicUi.scrollInsets(
        context,
        base: desktop
            ? const EdgeInsets.fromLTRB(32, 8, 32, 32)
            : const EdgeInsets.fromLTRB(
                MusicUi.pagePadding,
                12,
                MusicUi.pagePadding,
                24,
              ),
      ),
      children: [
        if (controller.isLoadingCache) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        // Phones: the two shortcuts share a row and listening sits below.
        // Wider: all three share one row instead of stretching into slabs.
        LayoutBuilder(
          builder: (context, box) {
            final favorite = _LibraryShortcutButton(
              selection: _LibraryListSpec.favorite(),
              count: controller.favoriteTracks.length,
              title: strings.favorite,
              onPressed: () => _openList(context, _LibraryListSpec.favorite()),
            );
            final local = _LibraryShortcutButton(
              selection: _LibraryListSpec.local(),
              count: controller.cachedTracks.length,
              title: strings.localLibrary,
              onPressed: () => _openList(context, _LibraryListSpec.local()),
            );
            final listening = Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const Key('library-listening-stats'),
                leading: Icon(
                  AppIcons.insights,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(strings.isZh ? '我的听歌' : 'My listening'),
                subtitle: Text(
                  strings.isZh
                      ? '时长、排行与每日记录'
                      : 'Time, rankings and daily history',
                ),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute<void>(
                    settings: const RouteSettings(name: 'listening-stats'),
                    builder: (_) => ListeningStatsPage(
                      controller: controller,
                      bottomPlayer: MiniPlayer(controller: controller),
                      onOpenPlaylist: (playlist) =>
                          _openList(context, _LibraryListSpec.custom(playlist)),
                    ),
                  ),
                ),
              ),
            );
            if (box.maxWidth >= MusicLayout.mediumWidth) {
              return Row(
                children: [
                  Expanded(child: favorite),
                  const SizedBox(width: 12),
                  Expanded(child: local),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: listening),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: favorite),
                    const SizedBox(width: 12),
                    Expanded(child: local),
                  ],
                ),
                const SizedBox(height: 24),
                listening,
              ],
            );
          },
        ),
        SizedBox(height: desktop ? 30 : 24),
        Text(strings.customPlaylists, style: heading),
        SizedBox(height: desktop ? 14 : 8),
        if (playlists.isEmpty)
          const _EmptyCustomPlaylists()
        else if (desktop)
          sleeves(playlists)
        else
          // One list on a phone, two or three side by side when wider.
          AdaptiveTiles(
            minTileWidth: 340,
            minColumns: 1,
            maxColumns: 3,
            runSpacing: 4,
            fullRows: false,
            children: [
              for (final playlist in playlists)
                _CustomPlaylistTile(
                  playlist: playlist,
                  artwork: _homePlaylistArtwork(controller, playlist),
                  subtitle: _homePlaylistSubtitle(
                    controller,
                    playlist,
                    strings,
                  ),
                  onTap: () =>
                      _openList(context, _LibraryListSpec.custom(playlist)),
                ),
            ],
          ),
        const SizedBox(height: 24),
        if (controller.builtInPlaylists.isNotEmpty) ...[
          if (desktop) const SizedBox(height: 6),
          Text(strings.isZh ? '榜单歌单' : 'Charts', style: heading),
          SizedBox(height: desktop ? 14 : 8),
          if (desktop)
            sleeves(controller.builtInPlaylists)
          else
            AdaptiveTiles(
              minTileWidth: 340,
              minColumns: 1,
              maxColumns: 3,
              runSpacing: 4,
              fullRows: false,
              children: [
                for (final playlist in controller.builtInPlaylists)
                  _CustomPlaylistTile(
                    playlist: playlist,
                    artwork: _homePlaylistArtwork(controller, playlist),
                    subtitle: _homePlaylistSubtitle(
                      controller,
                      playlist,
                      strings,
                    ),
                    onTap: () =>
                        _openList(context, _LibraryListSpec.custom(playlist)),
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
        Text(strings.isZh ? '匹配歌单' : 'Matching playlists', style: heading),
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
    final chart = [
      ...qqMusicCharts,
      ...neteaseMusicCharts,
    ].where((c) => c.playlistId == selection.id).firstOrNull;
    if (chart != null) {
      return Navigator.of(
        context,
      ).push<void>(AppPageRoute(builder: (_) => _chartPage(controller, chart)));
    }
    return Navigator.of(context).push<void>(
      AppPageRoute(
        settings: const RouteSettings(name: 'playlist-detail'),
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

  /// A flat tile, one of two side by side: icon and name on the left, the
  /// count on the right in the engraved voice. No shadow; the tint alone
  /// separates it from the page.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(MusicUi.radius);
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Icon(selection.icon, size: 20, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              // Shrinks before it overflows on narrow phones with large type.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    AppStringsScope.of(context).songCount(count),
                    maxLines: 1,
                    style: MusicType.readout(context, size: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
          Icon(AppIcons.queue, size: 40, color: colors.primary),
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
    this.artwork,
    required this.onTap,
  });

  final MusicPlaylist playlist;
  final Uri? artwork;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('custom-playlist-${playlist.id}'),
      contentPadding: EdgeInsets.zero,
      leading: MusicThumbnail(uri: artwork, label: playlist.name),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(AppIcons.chevronRight),
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

/// The playlist most likely opened next (the most used one, else the
/// favorites), for [PlayerWarmUp] to draw once out of sight. It records no
/// visit.
Widget playlistPageForWarmUp(MusicController controller) {
  final playlist = controller.frequentlyUsedPlaylists.firstOrNull;
  return _PlaylistDetailPage(
    controller: controller,
    selection: playlist == null
        ? _LibraryListSpec.favorite()
        : _LibraryListSpec.custom(playlist),
    warmUp: true,
  );
}

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
      icon: AppIcons.library,
      kind: _LibraryListKind.local,
    );
  }

  factory _LibraryListSpec.favorite() {
    return const _LibraryListSpec(
      id: favoritePlaylistId,
      title: '',
      icon: AppIcons.heartFill,
      kind: _LibraryListKind.favorite,
    );
  }

  factory _LibraryListSpec.custom(MusicPlaylist playlist) {
    return _LibraryListSpec(
      id: playlist.id,
      title: playlist.name,
      icon: AppIcons.queue,
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
  bool get isBuiltIn => playlist?.isBuiltIn == true;
  bool get canManage => selection.kind == _LibraryListKind.custom && !isBuiltIn;
  bool get canRemove => !isLocal && !isBuiltIn;
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
      final playlist = controller.allPlaylists
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
    this.onRefresh,
    this.refreshing = false,
    this.refreshError,
    this.chartUpdatedAt,
    this.warmUp = false,
  });

  final MusicController controller;
  final _LibraryListSpec selection;

  /// Drawn out of sight by [PlayerWarmUp]: not a visit.
  final bool warmUp;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final String? refreshError;
  final String? chartUpdatedAt;

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
  int _locateRevision = 0;
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

  MusicController get controller => widget.controller;

  ValueNotifier<({String id, int revision})?>? _desktopLocation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordUsageAfterEntrance();
    final location = DesktopMusicScope.maybeOf(context)?.locate;
    if (identical(location, _desktopLocation)) return;
    _desktopLocation?.removeListener(_locateFromDesktop);
    _desktopLocation = location;
    location?.addListener(_locateFromDesktop);
  }

  void _locateFromDesktop() {
    if (!mounted || _desktopLocation?.value?.id != widget.selection.id) return;
    setState(() {
      _query = '';
      _dateFilter = null;
      _searchController.clear();
      _locateRevision++;
    });
  }

  bool _usageRecorded = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  void _recordUsageAfterEntrance() {
    if (_usageRecorded || widget.warmUp) return;
    _usageRecorded = true;
    // Recording notifies the whole app (the library reorders by use); doing
    // it mid-push redrew every page under the sliding list.
    afterRouteEntrance(context, () {
      if (mounted && widget.selection.kind == _LibraryListKind.custom) {
        unawaited(controller.recordPlaylistUsage(widget.selection.id));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PlaylistDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection.id != widget.selection.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.selection.kind == _LibraryListKind.custom) {
            unawaited(controller.recordPlaylistUsage(widget.selection.id));
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _desktopLocation?.removeListener(_locateFromDesktop);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
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
        final effectiveSortMode = rawList.canManage || rawList.isBuiltIn
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
        final desktop = DesktopMusicScope.maybeOf(context) != null;
        // On the Mac every list opens under its own header with the sleeve,
        // except the date-grouped local list.
        final desktopHero =
            desktop &&
            !_isReorderEditing &&
            !(rawList.isLocal && effectiveSortMode == _LibrarySortMode.time);
        final immersive =
            desktopHero || (list.playlist != null && !_isReorderEditing);
        final appBar = _isReorderEditing
            ? _reorderEditAppBar(context, list)
            : selecting
            ? _selectionAppBar(context, list, selectedTracks)
            : AppBar(
                title: Text(
                  // The system bar carries the list's own name.
                  list.playlist != null && !NativeShell.active
                      ? (strings.isZh ? '歌单详情' : 'Playlist')
                      : list.title,
                ),
                actions: [
                  if (desktop)
                    IconButton(
                      tooltip: strings.isZh ? '定位当前歌曲' : 'Locate current song',
                      onPressed: () => setState(() => _locateRevision++),
                      icon: const Icon(AppIcons.locate),
                    ),
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
                  if (canAdjustOrder && !list.canManage)
                    IconButton(
                      key: const ValueKey('adjust-order-action'),
                      tooltip: strings.adjustOrder,
                      onPressed: hasActiveFilter
                          ? () => _showClearSearchToAdjustOrder(context)
                          : () => _startReorderEditing(sortedTracks),
                      icon: const Icon(AppIcons.reorder),
                    ),
                  if (widget.onRefresh != null)
                    IconButton(
                      tooltip: strings.refresh,
                      onPressed: widget.refreshing ? null : widget.onRefresh,
                      icon: const Icon(AppIcons.refresh),
                    ),
                  if (!list.canManage && !list.isBuiltIn)
                    _LibrarySortButton(
                      mode: _sortMode,
                      timeLabel: list.isLocal
                          ? strings.sortByDownloadTime
                          : strings.sortByAddedTime,
                      showCustomOrder: list.isFavorite,
                      onChanged: (mode) => _changeSortMode(mode),
                    ),
                  if (list.canManage &&
                      list.playlist != null &&
                      list.playlist!.onlineOriginKey.isNotEmpty)
                    PlaylistSyncButton(
                      controller: controller,
                      playlist: list.playlist!,
                    ),
                  if (list.canManage && list.playlist != null)
                    MusicPopupMenuButton<_PlaylistAction>(
                      key: const ValueKey('playlist-actions-menu'),
                      tooltip: strings.isZh ? '歌单操作' : 'Playlist actions',
                      icon: const Icon(AppIcons.more),
                      onSelected: (action) {
                        switch (action) {
                          case _PlaylistAction.reorder:
                            if (hasActiveFilter) {
                              _showClearSearchToAdjustOrder(context);
                            } else {
                              _startReorderEditing(sortedTracks);
                            }
                          case _PlaylistAction.rename:
                            _rename(context, list.playlist!);
                          case _PlaylistAction.deduplicate:
                            _deduplicate(context, list.playlist!);
                          case _PlaylistAction.delete:
                            _delete(context, list.playlist!);
                        }
                      },
                      itemBuilder: (context) => [
                        if (canAdjustOrder)
                          PopupMenuItem(
                            key: const ValueKey('adjust-order-action'),
                            value: _PlaylistAction.reorder,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(AppIcons.reorder),
                              title: Text(strings.adjustOrder),
                            ),
                          ),
                        PopupMenuItem(
                          key: const ValueKey('deduplicate-playlist-action'),
                          value: _PlaylistAction.deduplicate,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(AppIcons.playlistRemove),
                            title: Text(
                              strings.isZh ? '歌单去重' : 'Remove duplicates',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: _PlaylistAction.rename,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(AppIcons.edit),
                            title: Text(strings.renamePlaylist),
                          ),
                        ),
                        PopupMenuItem(
                          value: _PlaylistAction.delete,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(AppIcons.delete),
                            title: Text(strings.deletePlaylist),
                          ),
                        ),
                      ],
                    ),
                ],
              );
        final searchField = ListSearchField(
          padding: desktopHero ? EdgeInsets.zero : null,
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (value) => setState(() {
            _query = value;
            _collapsedDates.clear();
          }),
          emptySuffix:
              (list.canManage || list.isBuiltIn) &&
                  list.playlist != null &&
                  sortedTracks.isNotEmpty &&
                  !_searchFocusNode.hasFocus
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    key: const ValueKey('download-all-playlist'),
                    tooltip: controller.isPlaylistDownloading(list.playlist!)
                        ? strings.downloadingPlaylist
                        : strings.downloadAllPlaylist,
                    onPressed: controller.isPlaylistDownloading(list.playlist!)
                        ? null
                        : () => _downloadAllPlaylist(list.playlist!),
                    icon: controller.isPlaylistDownloading(list.playlist!)
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppIcons.download),
                  ),
                )
              : null,
        );
        final headerChildren = <Widget>[
          if (widget.refreshing) const LinearProgressIndicator(),
          if (widget.refreshError != null)
            ListTile(
              dense: true,
              leading: const Icon(AppIcons.error),
              title: Text(widget.refreshError!),
              subtitle: Text(
                strings.isZh ? '暂时显示上次保存的榜单' : 'Showing the last saved chart',
              ),
            ),
          if (!_isReorderEditing && !desktopHero) searchField,
          if (list.canManage && list.playlist != null)
            PlaylistSourceProgress(
              controller: controller,
              playlistId: list.playlist!.id,
            ),
          if (list.canManage && list.playlist != null)
            _OnlinePlaylistSyncProgress(
              controller: controller,
              playlistId: list.playlist!.id,
              onOpenTask: _openOnlineSyncTask,
            ),
          if (list.playlist != null &&
              controller.playlistDownloadProgress(list.playlist!) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PlaylistDownloadProgressView(
                controller: controller,
                playlist: list.playlist!,
              ),
            ),
        ];
        final headerSlivers = desktopHero
            ? <Widget>[
                SliverToBoxAdapter(
                  child: _DesktopListHero(
                    controller: controller,
                    list: list,
                    note: widget.chartUpdatedAt == null
                        ? null
                        : strings.chartUpdated(widget.chartUpdatedAt!),
                    actions: selecting ? const [] : appBar.actions ?? const [],
                    search: _isReorderEditing ? null : searchField,
                    onPlayAll: sortedTracks.isEmpty
                        ? null
                        : () => unawaited(
                            _playFromList(sortedTracks.first, 0, sortedTracks),
                          ),
                  ),
                ),
                SliverToBoxAdapter(child: Column(children: headerChildren)),
                if (list.tracks.isNotEmpty)
                  const SliverToBoxAdapter(child: _DesktopTrackHeader()),
              ]
            : immersive
            ? <Widget>[
                if (NativeShell.active)
                  // The title sits in the system bar; keep only the note.
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 4),
                    sliver: SliverToBoxAdapter(
                      child: widget.chartUpdatedAt == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                strings.chartUpdated(widget.chartUpdatedAt!),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                    ),
                  )
                else
                  PlaylistSliverHeader(
                    title: list.title,
                    note: widget.chartUpdatedAt == null
                        ? null
                        : strings.chartUpdated(widget.chartUpdatedAt!),
                    actions: DuoScaffold.usesSystemRail(context)
                        ? const []
                        : appBar.actions ?? const [],
                    leading: DuoScaffold.usesSystemRail(context)
                        ? const SizedBox.shrink()
                        : appBar.leading,
                    toolbarTitle: selecting ? appBar.title : null,
                  ),
                SliverToBoxAdapter(child: Column(children: headerChildren)),
              ]
            : null;
        final trackList = controller.isLoadingCache
            ? (immersive
                  ? PlaylistScrollView(
                      slivers: [
                        ...headerSlivers!,
                        const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()))
            : _TrackList(
                key: ValueKey('$_dateFilter:$_locateRevision'),
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
                    list.isLocal && effectiveSortMode == _LibrarySortMode.time,
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
                    _reorderDraft(oldIndex, newIndex, list.selection.id),
                headerSlivers: headerSlivers,
              );
        return PopScope(
          canPop: !_isReorderEditing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isReorderEditing) {
              unawaited(_requestExitReorderEditing(list));
            }
          },
          child: DuoScaffold(
            extendBody: true,
            // On the Mac a selection keeps its bar above the header.
            appBar: immersive && !(desktopHero && selecting) ? null : appBar,
            railAppBar: immersive ? appBar : null,
            body: SafeArea(
              top: !immersive,
              bottom: false,
              child: immersive
                  ? trackList
                  : Column(
                      children: [
                        ...headerChildren,
                        Expanded(child: trackList),
                      ],
                    ),
            ),
            bottomNavigationBar: _isReorderEditing
                ? null
                : MiniPlayer(controller: controller),
          ),
        );
      },
    );
  }

  void _openOnlineSyncTask(OnlinePlaylistTask task) {
    Navigator.of(context).push<void>(
      AppPageRoute(
        settings: const RouteSettings(name: 'online-playlist'),
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
        playlistId:
            widget.selection.kind == _LibraryListKind.custom ||
                widget.selection.kind == _LibraryListKind.favorite
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

  AppBar _selectionAppBar(
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
        icon: const Icon(AppIcons.close),
      ),
      title: Text(strings.selectedSongCount(selectedTracks.length)),
      actions: [
        IconButton(
          tooltip: strings.selectAllVisible,
          onPressed: list.tracks.isEmpty
              ? null
              : () => _selectAllVisible(list.tracks),
          icon: const Icon(AppIcons.checkCircle),
        ),
        IconButton(
          tooltip: strings.addToPlaylist,
          onPressed: hasSelection
              ? () => _addSelectedToPlaylist(context, selectedTracks)
              : null,
          icon: const Icon(AppIcons.playlistAdd),
        ),
        if (list.isLocal)
          IconButton(
            tooltip: strings.deleteLocalMusic,
            onPressed: hasSelection
                ? () => _deleteSelectedLocalTracks(context, selectedTracks)
                : null,
            icon: const Icon(AppIcons.delete),
          )
        else if (list.canRemove)
          IconButton(
            tooltip: strings.removeSelected,
            onPressed: hasSelection
                ? () => _removeSelectedFromCurrent(list, selectedTracks)
                : null,
            icon: const Icon(AppIcons.remove),
          ),
      ],
    );
  }

  AppBar _reorderEditAppBar(BuildContext context, _ResolvedLibraryList list) {
    final strings = AppStringsScope.of(context);
    return AppBar(
      leading: IconButton(
        tooltip: strings.cancel,
        onPressed: () => _requestExitReorderEditing(list),
        icon: const Icon(AppIcons.close),
      ),
      title: Text(strings.adjustOrder),
      actions: [
        TextButton.icon(
          key: const ValueKey('save-order-action'),
          onPressed: () => _saveReorderDraft(list, exitAfterSave: true),
          icon: const Icon(AppIcons.check),
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

  void _reorderDraft(int oldIndex, int newIndex, String playlistId) {
    setState(() {
      final reorderedIds = reorderIdsForReorderableListView(
        _reorderDraftTrackIds,
        oldIndex,
        newIndex,
        pinnedIds: controller.pinnedTrackIds(playlistId).toSet(),
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

  Future<void> _deduplicate(
    BuildContext context,
    MusicPlaylist playlist,
  ) async {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    try {
      final plan = controller.playlistDuplicates(playlist);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(zh ? '歌单去重' : 'Remove duplicates'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.removeCount == 0
                        ? (zh ? '没有发现重复歌曲' : 'No duplicate songs found')
                        : (zh
                              ? '发现 ${plan.groups.length} 组重复歌曲，可删除 ${plan.removeCount} 首多余歌曲。'
                              : '${plan.groups.length} duplicate groups; ${plan.removeCount} extra entries to remove.'),
                  ),
                  if (plan.removeCount > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      zh
                          ? '每组保留歌单中最先出现的一首，仅移除本歌单的重复条目。'
                          : 'Keep the first entry in each group. Only this playlist is changed.',
                    ),
                    for (final group in plan.groups)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '${group.title}\n${group.artist}\n${zh ? '共 ${group.trackIds.length} 首，删除 ${group.removeCount} 首' : '${group.trackIds.length} entries; remove ${group.removeCount}'}',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                plan.removeCount == 0 ? (zh ? '知道了' : 'OK') : strings.cancel,
              ),
            ),
            if (plan.removeCount > 0)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(zh ? '确认删除' : 'Confirm deletion'),
              ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await controller.removePlaylistDuplicates(plan);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              zh
                  ? '已移除 ${plan.removeCount} 首重复歌曲'
                  : 'Removed ${plan.removeCount} duplicate entries',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
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
  int newIndex, {
  Set<String> pinnedIds = const {},
}) {
  final reordered = [...ids];
  if (oldIndex < 0 || oldIndex >= reordered.length) {
    return reordered;
  }
  final id = reordered.removeAt(oldIndex);
  final pinCount = ids.where(pinnedIds.contains).length;
  final targetIndex = pinnedIds.contains(id)
      ? newIndex.clamp(0, pinCount - 1).toInt()
      : newIndex.clamp(pinCount, reordered.length).toInt();
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
    return MusicPopupMenuButton<_LibrarySortMode>(
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
      icon: const Icon(AppIcons.sort),
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
  return list.canCustomSort
      ? controller.orderPinnedTracks(sorted, list.selection.id)
      : sorted;
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
    this.headerSlivers,
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

  final List<Widget>? headerSlivers;
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
  Widget build(BuildContext context) => DistinctStreamBuilder<String?>(
    stream: controller.mediaItemStream.map((item) => item?.id),
    initialData: controller.audioHandler.mediaItem.valueOrNull?.id,
    builder: (context, activeId) => DistinctStreamBuilder<bool>(
      stream: controller.playbackStateStream.map((state) => state.playing),
      initialData: controller.audioHandler.playbackState.value.playing,
      builder: (context, playing) => _buildList(context, activeId, playing),
    ),
  );

  Widget _buildList(BuildContext context, String? activeId, bool playing) =>
      InitialSongScroll(
        targetIndex: list.isLocal
            ? null
            : controller.indexOfCurrentSong(list.tracks),
        builder: (context, scrollController, anchor) => _buildPositionedList(
          context,
          activeId,
          playing,
          scrollController,
          anchor,
        ),
      );

  Widget _buildPositionedList(
    BuildContext context,
    String? activeId,
    bool playing,
    ScrollController scrollController,
    SongRowAnchor anchor,
  ) {
    final tracks = list.tracks;
    final strings = AppStringsScope.of(context);
    if (tracks.isEmpty && headerSlivers != null) {
      return PlaylistScrollView(
        controller: scrollController,
        slivers: [
          ...headerSlivers!,
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyPlaylist(
              title: hasActiveFilter
                  ? strings.noMatchingTracks
                  : strings.noSongsInPlaylist,
            ),
          ),
        ],
      );
    }
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
        scrollController: scrollController,
        buildDefaultDragHandles: false,
        padding: MusicUi.scrollInsets(
          context,
          base: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        ),
        itemCount: tracks.length,
        // flutter_ohos does not support onReorderItem yet.
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) => onReorder(
          oldIndex,
          reorderTargetIndexFromRawReorder(oldIndex, newIndex),
        ),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return anchor(
            index,
            track.id,
            _TrackTile(
              key: ValueKey('track-${track.id}'),
              active: track.id == activeId,
              playing: playing && track.id == activeId,
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
                    child: Icon(AppIcons.reorder),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    Widget row(int index) {
      final track = tracks[index];
      return _TrackTile(
        active: track.id == activeId,
        playing: playing && track.id == activeId,
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

    Widget tile(BuildContext context, int index) =>
        anchor(index, tracks[index].id, row(index));

    final desktop = DesktopMusicScope.maybeOf(context) != null;
    if (headerSlivers != null) {
      return PlaylistScrollView(
        controller: scrollController,
        key: PageStorageKey('playlist-scroll-${list.selection.id}'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          ...headerSlivers!,
          // Always present: rows must not jump when selection or search starts.
          // The Mac header carries its own sleeve.
          if (!desktop)
            SliverToBoxAdapter(
              child: _PlaylistSleeve(
                controller: controller,
                list: list,
                playing: playing && tracks.any((track) => track.id == activeId),
                onPlayAll: () => onPlayTrack(tracks.first, 0, tracks),
              ),
            ),
          SliverPadding(
            padding: MusicUi.scrollInsets(
              context,
              base: desktop
                  ? const EdgeInsets.fromLTRB(20, 2, 20, 24)
                  : const EdgeInsets.fromLTRB(12, 8, 12, 16),
            ),
            sliver: desktop
                ? SliverList.separated(
                    itemCount: tracks.length,
                    itemBuilder: tile,
                    separatorBuilder: (_, _) => const SizedBox(height: 1),
                  )
                // Phone rows are one height (single-line title and subtitle),
                // so opening at the playing song lays out only the rows on
                // screen; a plain list built every row above it in one frame.
                : SliverPrototypeExtentList.builder(
                    prototypeItem: _DividedRow(divider: true, child: row(0)),
                    itemCount: tracks.length,
                    itemBuilder: (context, index) => _DividedRow(
                      divider: index < tracks.length - 1,
                      child: tile(context, index),
                    ),
                  ),
          ),
        ],
      );
    }

    if (groupByDate) {
      return CustomScrollView(
        controller: scrollController,
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
          SliverToBoxAdapter(
            child: SizedBox(height: MusicUi.scrollInsets(context).bottom),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: MusicUi.scrollInsets(
        context,
        base: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      ),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: tile,
    );
  }
}

class _TrackTile extends StatefulWidget {
  const _TrackTile({
    super.key,
    required this.controller,
    this.active = false,
    this.playing = false,
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

  final bool active, playing;
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
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  // Route/focus updates can rebuild the row while its menu is open. Keep the
  // button state alive so PopupMenuButton can deliver the selected action.
  final menuKey = GlobalKey<PopupMenuButtonState<_TrackAction>>();

  @override
  Widget build(BuildContext context) {
    final _TrackTile(
      :controller,
      :active,
      :playing,
      :list,
      :track,
      :tracks,
      :index,
      :isSelecting,
      :isReorderEditing,
      :selected,
      :isPreparing,
      :onPlayTrack,
      :onStartSelection,
      :onToggleSelection,
      :dragHandle,
    ) = widget;
    final strings = AppStringsScope.of(context);
    final needsSourceReview =
        !isSelecting &&
        !isReorderEditing &&
        controller.songSourceNeedsReview(track);
    return SongCacheProgressRow(
      controller: controller,
      track: track,
      rowBuilder: (context, cached) {
        final colors = Theme.of(context).colorScheme;
        // Not yet cached, but still playable: quieter, never disabled-looking.
        final faded = colors.onSurface.withValues(alpha: .72);
        return IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: cached ? null : faded),
          ),
          child: DesktopSongInteraction(
            id: '${list.selection.id}:${track.id}',
            enabled: !isSelecting && !isReorderEditing,
            onPlay: isReorderEditing
                ? null
                : isSelecting
                ? () => onToggleSelection(track)
                : isPreparing
                ? null
                : () => playOrOpenPlayer(
                    context,
                    controller,
                    track.id,
                    () => onPlayTrack(track, index, tracks),
                  ),
            onContextMenu: () => menuKey.currentState?.showButtonMenu(),
            builder: (tap, desktopSelected) =>
                !isSelecting &&
                    !isReorderEditing &&
                    DesktopMusicScope.maybeOf(context) != null
                ? _DesktopTrackRow(
                    controller: controller,
                    list: list,
                    track: track,
                    index: index,
                    active: active,
                    playing: playing,
                    cached: cached,
                    preparing: isPreparing,
                    selected: selected || desktopSelected,
                    needsSourceReview: needsSourceReview,
                    menuKey: menuKey,
                    onTap: tap,
                    onPlay: isPreparing
                        ? null
                        : () => playOrOpenPlayer(
                            context,
                            controller,
                            track.id,
                            () => onPlayTrack(track, index, tracks),
                          ),
                    onLongPress: () => onStartSelection(track),
                  )
                : ListTile(
                    selected: selected || desktopSelected,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    leading: isReorderEditing
                        ? const Icon(AppIcons.music)
                        : isSelecting
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => onToggleSelection(track),
                          )
                        : _TrackCover(
                            track: track,
                            active: active,
                            playing: playing,
                            preparing: isPreparing,
                            dimmed: !cached,
                            tooltip: isPreparing
                                ? strings.preparingPlayback
                                : active && playing
                                ? strings.playing
                                : strings.play,
                            onPressed: isPreparing
                                ? null
                                : () => playOrOpenPlayer(
                                    context,
                                    controller,
                                    track.id,
                                    () => onPlayTrack(track, index, tracks),
                                  ),
                          ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? colors.primary
                            : cached
                            ? null
                            : faded,
                      ),
                    ),
                    // One line, so every row is the same height.
                    subtitle: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _trackSubtitle(track),
                            style: cached ? null : TextStyle(color: faded),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (needsSourceReview) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: strings.isZh
                                ? '切换来源核对歌曲'
                                : 'Choose source to check this match',
                            child: TextButton(
                              key: ValueKey('song-match-review-${track.id}'),
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: colors.onTertiaryContainer,
                                backgroundColor: colors.tertiaryContainer
                                    .withValues(alpha: .55),
                                textStyle: Theme.of(
                                  context,
                                ).textTheme.labelSmall,
                              ),
                              onPressed: () => showSongSourcePicker(
                                context,
                                controller,
                                track,
                              ),
                              child: Text(strings.isZh ? '需核对' : 'Check match'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: isReorderEditing
                        ? dragHandle
                        : isSelecting
                        ? null
                        : _WideAlbumColumn(
                            album: track.album,
                            color: cached ? colors.onSurfaceVariant : faded,
                            child: _TrackActions(
                              menuKey: menuKey,
                              controller: controller,
                              list: list,
                              track: track,
                            ),
                          ),
                    onTap: tap,
                    onLongPress: isReorderEditing
                        ? null
                        : () => onStartSelection(track),
                  ),
          ),
        );
      },
    );
  }
}

/// A phone song row with the hairline under it.
class _DividedRow extends StatelessWidget {
  const _DividedRow({required this.divider, required this.child});

  final bool divider;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [child, if (divider) const Divider(height: 1)],
  );
}

/// The playlist as a record in its sleeve, with the one lit action: play it.
class _PlaylistSleeve extends StatelessWidget {
  const _PlaylistSleeve({
    required this.controller,
    required this.list,
    required this.playing,
    required this.onPlayAll,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final bool playing;
  final VoidCallback onPlayAll;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final playlist = list.playlist;
    Uri? artwork = playlist == null
        ? null
        : _homePlaylistArtwork(controller, playlist);
    for (final track in list.tracks) {
      if (artwork != null) break;
      artwork = track.artworkUri;
    }
    const size = 104.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          RecordSleeve(
            size: size,
            reveal: playing ? .34 : .16,
            spinning: playing,
            cover: MusicThumbnail(
              uri: artwork,
              label: list.title,
              size: size,
              radius: 0,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.songCount(list.tracks.length),
                  style: MusicType.readout(context, size: 13),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('playlist-play-all'),
                  onPressed: onPlayAll,
                  icon: const Icon(AppIcons.play),
                  label: Text(strings.isZh ? '播放全部' : 'Play all'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The row's cover. It plays on tap like the old play button did, and shows
/// the level meter over the art while its song is the one playing.
class _TrackCover extends StatelessWidget {
  const _TrackCover({
    required this.track,
    required this.active,
    required this.playing,
    required this.preparing,
    required this.dimmed,
    required this.tooltip,
    required this.onPressed,
  });

  final Track track;
  final bool active, playing, preparing, dimmed;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final radius = BorderRadius.circular(MusicUi.sleeveRadius);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: dimmed && !active ? .8 : 1,
                  child: MusicThumbnail(
                    uri: track.artworkUri,
                    label: track.title,
                    size: size,
                    radius: MusicUi.sleeveRadius,
                  ),
                ),
                if (active || preparing)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .5),
                      borderRadius: radius,
                    ),
                    child: Center(
                      child: preparing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : EqualizerBars(
                              playing: playing,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
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
}

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.controller,
    required this.list,
    required this.track,
    this.menuKey,
    this.dense = false,
    this.showMenu = true,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final Track track;
  final GlobalKey<PopupMenuButtonState<_TrackAction>>? menuKey;

  /// Mac rows: small buttons; the menu button appears under the pointer
  /// but stays in place for the right-click menu.
  final bool dense, showMenu;

  @override
  Widget build(BuildContext context) {
    final favorite = controller.isFavorite(track);
    final strings = AppStringsScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dense)
          DesktopToolButton(
            tooltip: favorite
                ? strings.removeFromFavorites
                : strings.addToFavorites,
            onPressed: () => controller.toggleFavorite(track),
            icon: favorite ? AppIcons.heartFill : AppIcons.heart,
            color: favorite ? Theme.of(context).colorScheme.primary : null,
            size: 30,
            iconSize: 17,
          )
        else
          IconButton(
            tooltip: favorite
                ? strings.removeFromFavorites
                : strings.addToFavorites,
            onPressed: () => controller.toggleFavorite(track),
            icon: Icon(favorite ? AppIcons.heartFill : AppIcons.heart),
          ),
        if (dense) ...[
          const SizedBox(width: 2),
          Opacity(opacity: showMenu ? 1 : 0, child: _menu(context, strings)),
        ] else
          _menu(context, strings),
      ],
    );
  }

  Widget _menu(BuildContext context, AppStrings strings) =>
      MusicPopupMenuButton<_TrackAction>(
        key: menuKey,
        icon: dense ? const Icon(AppIcons.more, size: 18) : null,
        tooltip: strings.more,
        onSelected: (action) => _handle(context, action),
        itemBuilder: (context) {
          return [
            PopupMenuItem(
              value: _TrackAction.addToQueue,
              child: Text(strings.isZh ? '添加到播放列表' : 'Add to queue'),
            ),
            PopupMenuItem(
              value: _TrackAction.addToPlaylist,
              child: Text(strings.addToPlaylist),
            ),
            if (FileSharing.supported)
              PopupMenuItem(
                value: _TrackAction.share,
                child: Text(strings.isZh ? '分享' : 'Share'),
              ),
            if (list.canCustomSort)
              PopupMenuItem(
                value: _TrackAction.pin,
                child: Text(
                  controller.isTrackPinned(track, list.selection.id)
                      ? (strings.isZh ? '取消置顶' : 'Unpin')
                      : (strings.isZh ? '置顶' : 'Pin to top'),
                ),
              ),
            PopupMenuItem(
              enabled: controller.canSwitchSongSource(track),
              value: _TrackAction.switchSource,
              child: SongSourceMenuLabel(
                source: controller.songSourceLabel(track, isZh: strings.isZh),
              ),
            ),
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
      );

  Future<void> _handle(BuildContext context, _TrackAction action) async {
    try {
      switch (action) {
        case _TrackAction.addToQueue:
          final messenger = ScaffoldMessenger.of(context);
          final zh = AppStringsScope.of(context).isZh;
          final added = await controller.addToQueue([track]);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  added > 0
                      ? (zh ? '已添加到播放列表' : 'Added to the queue')
                      : (zh ? '已经在播放列表里' : 'Already in the queue'),
                ),
              ),
            );
        case _TrackAction.addToPlaylist:
          await showAddToPlaylistSheet(context, controller, track);
        case _TrackAction.share:
          await shareSong(context, controller, track);
        case _TrackAction.pin:
          await controller.setTrackPinned(
            track,
            list.selection.id,
            pinned: !controller.isTrackPinned(track, list.selection.id),
          );
        case _TrackAction.switchSource:
          await showSongSourcePicker(context, controller, track);
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
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }
}

enum _TrackAction {
  share,
  pin,
  deleteLocal,
  removeFromCurrent,
  switchSource,
  addToQueue,
  addToPlaylist,
}

enum _PlaylistAction { reorder, deduplicate, rename, delete }

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
            Icon(AppIcons.library, size: 48, color: colors.primary),
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
            Icon(AppIcons.queue, size: 48, color: colors.primary),
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
    MusicUiMessageCode.playingOnlineStream =>
      strings.isZh ? '正在在线播放并缓存' : 'Streaming and caching',
  };
}

String _candidateSubtitle(MusicSearchCandidate candidate) {
  final parts = [
    if (candidate.artist.isNotEmpty) candidate.artist,
    if (candidate.album.isNotEmpty) candidate.album,
    if (candidate.source == MusicDataSource.twentyFourBit) '有限额下载',
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
    MusicDataSource.twentyFourBit => '24bit',
    MusicDataSource.auto => 'AUTO',
    MusicDataSource.lan => 'LAN',
  };
}

/// The Mac header of a list: its sleeve with the record half out, what kind
/// of list it is, its name, and one row of everything it can do.
class _DesktopListHero extends StatelessWidget {
  const _DesktopListHero({
    required this.controller,
    required this.list,
    required this.actions,
    required this.onPlayAll,
    this.search,
    this.note,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final List<Widget> actions;
  final VoidCallback? onPlayAll;
  final Widget? search;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final playlist = list.playlist;
    Uri? artwork = playlist == null
        ? null
        : playlistArtworkUri(controller, playlist);
    for (final track in list.tracks) {
      if (artwork != null) break;
      artwork = track.artworkUri;
    }
    final kind = list.isFavorite
        ? (zh ? '我的收藏' : 'FAVORITES')
        : list.isLocal
        ? (zh ? '本地音乐' : 'ON THIS MAC')
        : list.isBuiltIn
        ? (zh ? '榜单' : 'CHART')
        : (zh ? '歌单' : 'PLAYLIST');
    final title = list.title.isNotEmpty
        ? list.title
        : list.isFavorite
        ? (zh ? '我的收藏' : 'Favorites')
        : (zh ? '本地音乐' : 'Local music');
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItemStream,
      initialData: controller.audioHandler.mediaItem.valueOrNull,
      builder: (context, media) => StreamBuilder<bool>(
        stream: controller.playbackStateStream
            .map((state) => state.playing)
            .distinct(),
        initialData: controller.audioHandler.playbackState.value.playing,
        builder: (context, state) {
          final playing =
              (state.data ?? false) &&
              list.tracks.any((track) => track.id == media.data?.id);
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 4, 32, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RecordSleeve(
                      size: 176,
                      reveal: playing ? .34 : .2,
                      spinning: playing,
                      cover: ColoredBox(
                        color: MusicTokens.of(context).panel,
                        child: MusicThumbnail(
                          uri: artwork,
                          label: title,
                          size: 176,
                          radius: 0,
                        ),
                      ),
                      label: artwork == null
                          ? null
                          : MusicThumbnail(
                              uri: artwork,
                              label: title,
                              size: 64,
                              radius: 0,
                            ),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(kind, style: MusicType.eyebrow(context)),
                          const SizedBox(height: 10),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MusicType.masthead(context, size: 38),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            [
                              strings.songCount(list.tracks.length),
                              ?note,
                            ].join('  ·  '),
                            style: TextStyle(
                              fontSize: 13,
                              color: DesktopUi.muted(context),
                            ),
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final buttons = Row(
                                children: [
                                  FilledButton.icon(
                                    key: const ValueKey('playlist-play-all'),
                                    onPressed: onPlayAll,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      shape: const StadiumBorder(),
                                      textStyle: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    icon: const Icon(AppIcons.play, size: 20),
                                    label: Text(zh ? '播放全部' : 'Play all'),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: IconButtonTheme(
                                      data: IconButtonThemeData(
                                        style: IconButton.styleFrom(
                                          iconSize: 19,
                                          minimumSize: const Size(34, 34),
                                          foregroundColor: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(children: actions),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              if (search == null) return buttons;
                              // The search sits beside the buttons, or under
                              // them in a narrow window.
                              if (constraints.maxWidth < 480) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    buttons,
                                    const SizedBox(height: 10),
                                    search!,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: buttons),
                                  const SizedBox(width: 12),
                                  SizedBox(width: 220, child: search),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mac track table geometry, shared by the column header and its rows.
/// On wide screens a phone-style song row gains the album column the desktop
/// table has, so a tablet uses its width for information, not empty space.
class _WideAlbumColumn extends StatelessWidget {
  const _WideAlbumColumn({
    required this.album,
    required this.color,
    required this.child,
  });

  final String album;
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide =
        album.isNotEmpty &&
        MusicLayout.classOf(MediaQuery.sizeOf(context).width).isExpanded &&
        DesktopMusicScope.maybeOf(context) == null;
    if (!wide) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 220,
          child: Text(
            album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
        const SizedBox(width: 16),
        child,
      ],
    );
  }
}

abstract final class _DesktopColumns {
  static const index = 30.0;
  static const cover = 38.0;
  static const size = 70.0;
  static const actions = 88.0;
  static bool showAlbum(double width) => width >= 620;
}

class _DesktopTrackHeader extends StatelessWidget {
  const _DesktopTrackHeader();

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: DesktopUi.muted(context).withValues(alpha: .8),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 0),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 28,
              child: Row(
                children: [
                  SizedBox(
                    width: _DesktopColumns.index,
                    child: Text('#', textAlign: TextAlign.center, style: style),
                  ),
                  const SizedBox(width: 12 + _DesktopColumns.cover + 12),
                  Expanded(
                    flex: 5,
                    child: Text(zh ? '标题' : 'Title', style: style),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(zh ? '歌手' : 'Artist', style: style),
                  ),
                  if (_DesktopColumns.showAlbum(constraints.maxWidth)) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(zh ? '专辑' : 'Album', style: style),
                    ),
                  ],
                  SizedBox(
                    width: _DesktopColumns.size,
                    child: Text(
                      zh ? '大小' : 'Size',
                      textAlign: TextAlign.right,
                      style: style,
                    ),
                  ),
                  const SizedBox(width: _DesktopColumns.actions),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// A song as a row of the Mac track table. The number turns into a play
/// button under the pointer and into a level meter while the song plays.
class _DesktopTrackRow extends StatelessWidget {
  const _DesktopTrackRow({
    required this.controller,
    required this.list,
    required this.track,
    required this.index,
    required this.active,
    required this.playing,
    required this.cached,
    required this.preparing,
    required this.selected,
    required this.needsSourceReview,
    required this.menuKey,
    required this.onTap,
    required this.onPlay,
    required this.onLongPress,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final Track track;
  final int index;
  final bool active, playing, cached, preparing, selected, needsSourceReview;
  final GlobalKey<PopupMenuButtonState<_TrackAction>> menuKey;
  final VoidCallback? onTap, onPlay;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final faded = colors.onSurface.withValues(alpha: cached ? 1 : .62);
    final muted = DesktopUi.muted(context).withValues(alpha: cached ? 1 : .7);
    return DesktopHover(
      builder: (context, hovered) => GestureDetector(
        onLongPress: onLongPress,
        child: DesktopRow(
          selected: selected,
          onTap: onTap,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: _DesktopColumns.index,
                  child: Center(
                    child: preparing
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : hovered && !(active && playing)
                        ? DesktopToolButton(
                            icon: AppIcons.play,
                            tooltip: strings.play,
                            size: 28,
                            iconSize: 20,
                            color: colors.onSurface,
                            onPressed: onPlay,
                          )
                        : active
                        ? EqualizerBars(
                            playing: playing,
                            size: 15,
                            color: colors.primary,
                          )
                        : Text(
                            '${index + 1}',
                            style: MusicType.readout(context, size: 12),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Opacity(
                  opacity: cached ? 1 : .8,
                  child: MusicThumbnail(
                    uri: track.artworkUri,
                    label: track.title,
                    size: _DesktopColumns.cover,
                    radius: 5,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active ? colors.primary : faded,
                          ),
                        ),
                      ),
                      if (needsSourceReview) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: strings.isZh
                              ? '切换来源核对歌曲'
                              : 'Choose source to check this match',
                          child: DesktopRow(
                            key: ValueKey('song-match-review-${track.id}'),
                            height: 20,
                            radius: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            onTap: () => showSongSourcePicker(
                              context,
                              controller,
                              track,
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                strings.isZh ? '需核对' : 'Check match',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
                if (_DesktopColumns.showAlbum(constraints.maxWidth + 24)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      track.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                ],
                SizedBox(
                  width: _DesktopColumns.size,
                  child: Text(
                    track.sizeLabel,
                    textAlign: TextAlign.right,
                    style: MusicType.readout(context, size: 11.5),
                  ),
                ),
                SizedBox(
                  width: _DesktopColumns.actions,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _TrackActions(
                      menuKey: menuKey,
                      controller: controller,
                      list: list,
                      track: track,
                      dense: true,
                      showMenu: hovered || selected,
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
}
