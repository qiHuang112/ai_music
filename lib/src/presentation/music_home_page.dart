import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/music_controller.dart';
import '../application/music_ui_message.dart';
import '../data/hotlist.dart';
import '../data/hotlist_playlists.dart';
import '../data/music_playlists.dart';
import '../data/playback_state_store.dart';
import '../data/music_resolver.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'download_manager_page.dart';
import 'list_search.dart';
import 'player_page.dart';
import 'playlist_actions.dart';
import 'settings_page.dart';
import 'swipe_to_skip.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  static const _exitBackWindow = Duration(seconds: 2);

  final _searchController = TextEditingController();
  DateTime? _lastEmptyBackAt;
  MusicUiMessage? _lastStatusSnackMessage;

  MusicController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
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
                  icon: const Icon(Icons.download),
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
                    isSearching: controller.isSearching,
                    onChanged: _handleSearchChanged,
                    onSearch: () => controller.search(_searchController.text),
                    onSubmitted: controller.search,
                  ),
                  if (_shouldShowSearchPanel)
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
                        onOpenLibrary: _openLibrary,
                        onHotlistSearch: _searchFromHotlist,
                      ),
                    ),
                ],
              ),
            ),
            bottomNavigationBar: _MiniPlayer(controller: controller),
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

  void _handleSearchChanged(String value) {
    _lastEmptyBackAt = null;
    if (controller.hasSearchState) {
      // 输入变化立即清空旧结果，避免旧搜索晚返回后把新关键词页面污染。
      controller.clearSearch();
    }
    setState(() {});
  }

  void _handleRootBack(AppStrings strings) {
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
    _searchController.clear();
    controller.clearSearch();
    setState(() {});
  }

  void _searchFromHotlist(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
    controller.search(query);
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
        builder: (context) => DownloadManagerPage(controller: controller),
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
}

bool _shouldShowFloatingStatus(MusicUiMessage message) {
  return switch (message.code) {
    MusicUiMessageCode.alreadyInCache ||
    MusicUiMessageCode.downloadedToCache ||
    MusicUiMessageCode.downloadAlreadyRunning ||
    MusicUiMessageCode.downloadCanceled ||
    MusicUiMessageCode.playingCachedFile ||
    MusicUiMessageCode.playingFullAudioStream ||
    MusicUiMessageCode.playingPreviewAudio ||
    MusicUiMessageCode.previewCannotDownload => true,
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
    required this.isSearching,
    required this.onChanged,
    required this.onSearch,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  final ValueChanged<String> onSubmitted;

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
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  hintText: strings.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: strings.searchOnline,
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
                    final isFullAudio =
                        candidate.source == MusicDataSource.kuwoFullAudio ||
                        candidate.source == MusicDataSource.gequhai;
                    final canPlay = isCached || isFullAudio;
                    final canDownload = isFullAudio;
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
                        _candidateSubtitle(
                          strings,
                          candidate,
                          isCached: isCached,
                          isFullAudio: isFullAudio,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canPlay)
                            IconButton(
                              tooltip: strings.play,
                              onPressed: isBusy
                                  ? null
                                  : () => onPlay(candidate),
                              icon: const Icon(Icons.play_arrow),
                            ),
                          if (canDownload)
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
                          : canPlay
                          ? () => onPlay(candidate)
                          : null,
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
    required this.onOpenLibrary,
    required this.onHotlistSearch,
  });

  final MusicController controller;
  final bool showDefaultLibrary;
  final VoidCallback onOpenLibrary;
  final ValueChanged<String> onHotlistSearch;

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
        const SizedBox(height: 24),
        _HotlistDiscoverySection(
          controller: controller,
          onSearch: onHotlistSearch,
        ),
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
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final playlists = controller.customPlaylists;
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
              subtitle: _librarySubtitle(
                strings,
                controller.tracksForPlaylist(playlist),
                emptyText: strings.noSongsInPlaylist,
              ),
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
        if (controller.hotlistPlaylists.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            strings.hotlistPlaylists,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final playlist in controller.hotlistPlaylists.take(3)) ...[
            _HomeLibraryTile(
              key: ValueKey('home-hotlist-playlist-${playlist.id}'),
              icon: Icons.local_fire_department,
              title: playlist.name,
              subtitle: strings.songCount(playlist.entries.length),
              onTap: () => _openHotlistPlaylist(context, playlist),
            ),
            const SizedBox(height: 8),
          ],
        ],
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

  Future<void> _openHotlistPlaylist(
    BuildContext context,
    HotlistPlaylist playlist,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _HotlistPlaylistPage(controller: controller, playlist: playlist),
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
}) {
  if (tracks.isEmpty) {
    return emptyText;
  }
  final preview = tracks.take(3).map((track) => track.title).join(' / ');
  return '${strings.songCount(tracks.length)} · $preview';
}

class _HotlistDiscoverySection extends StatelessWidget {
  const _HotlistDiscoverySection({
    required this.controller,
    required this.onSearch,
  });

  final MusicController controller;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.hotlistDiscovery,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: strings.refresh,
              onPressed: controller.isLoadingHotlists
                  ? null
                  : () => controller.loadHotlists(forceRefresh: true),
              icon: controller.isLoadingHotlists
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (controller.hotlistCharts.isEmpty)
          _HotlistUnavailable(
            isLoading: controller.isLoadingHotlists,
            message: controller.hotlistError ?? strings.hotlistUnavailable,
          )
        else
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.hotlistCharts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _HotlistChartCard(
                chart: controller.hotlistCharts[index],
                onTap: () => _openHotlistDetail(
                  context,
                  controller.hotlistCharts[index],
                  onSearch,
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          strings.hotlistMetadataNotice,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _openHotlistDetail(
    BuildContext context,
    HotlistChart chart,
    ValueChanged<String> onSearch,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _HotlistDetailPage(
          controller: controller,
          chart: chart,
          onSearch: onSearch,
        ),
      ),
    );
  }
}

class _HotlistUnavailable extends StatelessWidget {
  const _HotlistUnavailable({required this.isLoading, required this.message});

  final bool isLoading;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 104,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: isLoading
          ? const CircularProgressIndicator()
          : ListTile(
              leading: Icon(Icons.wifi_off, color: colors.onSurfaceVariant),
              title: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }
}

class _HotlistChartCard extends StatelessWidget {
  const _HotlistChartCard({required this.chart, required this.onTap});

  final HotlistChart chart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStringsScope.of(context);
    return SizedBox(
      width: 260,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HotlistArtwork(url: chart.coverUrl, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chart.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _chartSubtitle(strings, chart),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final item in chart.items.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${item.rank}. ${item.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _HotlistDetailPage extends StatelessWidget {
  const _HotlistDetailPage({
    required this.controller,
    required this.chart,
    required this.onSearch,
  });

  final MusicController controller;
  final HotlistChart chart;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(chart.title)),
          body: SafeArea(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: chart.items.length + 1,
              separatorBuilder: (_, index) =>
                  index == 0 ? const SizedBox(height: 8) : const Divider(),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _HotlistArtwork(url: chart.coverUrl, size: 86),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chart.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _chartSubtitle(strings, chart),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        key: const ValueKey('hotlist-add-playlist'),
                        onPressed: controller.isSavingHotlistPlaylist
                            ? null
                            : () async {
                                final result = await controller
                                    .saveHotlistChartAsPlaylist(chart);
                                if (!context.mounted || result == null) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      strings.hotlistSaved(
                                        result.addedCount,
                                        result.skippedCount,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        icon: controller.isSavingHotlistPlaylist
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.playlist_add),
                        label: Text(strings.addHotlistToPlaylist),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strings.hotlistMetadataNotice,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                }
                final item = chart.items[index - 1];
                return _HotlistItemTile(
                  item: item,
                  onSearch: () {
                    Navigator.of(context).pop();
                    onSearch(item.searchQuery);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _HotlistPlaylistPage extends StatelessWidget {
  const _HotlistPlaylistPage({
    required this.controller,
    required this.playlist,
  });

  final MusicController controller;
  final HotlistPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.hotlistPlaylists.firstWhere(
          (item) => item.id == playlist.id,
          orElse: () => playlist,
        );
        return Scaffold(
          appBar: AppBar(title: Text(current.name)),
          body: SafeArea(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: current.entries.length + 1,
              separatorBuilder: (_, index) =>
                  index == 0 ? const SizedBox(height: 8) : const Divider(),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.hotlistMetadataNotice,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (controller.hotlistPlaylistError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          controller.hotlistPlaylistError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  );
                }
                final entry = current.entries[index - 1];
                return ListTile(
                  key: ValueKey('hotlist-playlist-entry-${entry.id}'),
                  leading: _HotlistArtwork(url: entry.coverUrl, size: 42),
                  title: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: strings.playFromTransientCache,
                    onPressed: controller.isPlayingHotlist
                        ? null
                        : () => controller.playHotlistPlaylistEntry(
                            current,
                            entry,
                          ),
                    icon: controller.isPlayingHotlist
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_circle),
                  ),
                  onTap: controller.isPlayingHotlist
                      ? null
                      : () =>
                            controller.playHotlistPlaylistEntry(current, entry),
                );
              },
            ),
          ),
          bottomNavigationBar: _MiniPlayer(controller: controller),
        );
      },
    );
  }
}

class _HotlistItemTile extends StatelessWidget {
  const _HotlistItemTile({required this.item, required this.onSearch});

  final HotlistItem item;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 56,
        height: 32,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${item.rank}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _HotlistArtwork(url: item.coverUrl, size: 32),
          ],
        ),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: strings.searchOnline,
        icon: const Icon(Icons.manage_search),
        onPressed: onSearch,
      ),
      onTap: onSearch,
    );
  }
}

class _HotlistArtwork extends StatelessWidget {
  const _HotlistArtwork({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: uri == null || !uri.hasScheme
          ? Container(
              width: size,
              height: size,
              color: colors.surfaceContainerHighest,
              child: Icon(Icons.local_fire_department, color: colors.primary),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: colors.surfaceContainerHighest,
                child: Icon(Icons.local_fire_department, color: colors.primary),
              ),
            ),
    );
  }
}

String _chartSubtitle(AppStrings strings, HotlistChart chart) {
  final source = switch (chart.source) {
    HotlistSource.qq => strings.hotlistSourceQq,
  };
  final updated =
      chart.updatedAt?.toIso8601String().split('T').first ??
      (chart.period.isEmpty ? '' : chart.period);
  if (updated.isEmpty) {
    return source;
  }
  final stale = chart.isStale ? ' · stale' : '';
  return '$source · ${strings.hotlistUpdated(updated)}$stale';
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
  Widget build(BuildContext context) {
    final playlists = controller.customPlaylists;
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
              controller: controller,
              playlist: playlist,
              onTap: () =>
                  _openList(context, _LibraryListSpec.custom(playlist)),
            ),
            const Divider(height: 1),
          ],
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
    required this.controller,
    required this.playlist,
    required this.onTap,
  });

  final MusicController controller;
  final MusicPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = controller.tracksForPlaylist(playlist).length;
    final strings = AppStringsScope.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.queue_music),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(strings.songCount(count)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
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

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  _LibrarySortMode _sortMode = _LibrarySortMode.time;
  final _searchController = TextEditingController();
  final List<String> _selectedTrackIds = <String>[];
  final List<String> _reorderDraftTrackIds = <String>[];
  String _query = '';
  bool _isReorderEditing = false;
  bool _reorderDraftDirty = false;

  MusicController get controller => widget.controller;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final strings = AppStringsScope.of(context);
        final controller = widget.controller;
        final hasActiveFilter = _query.trim().isNotEmpty;
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
          tracks: filterTracksByQuery(visibleTracks, _query),
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
                      if (canAdjustOrder)
                        TextButton.icon(
                          key: const ValueKey('adjust-order-action'),
                          onPressed: hasActiveFilter
                              ? () => _showClearSearchToAdjustOrder(context)
                              : () => _startReorderEditing(sortedTracks),
                          icon: const Icon(Icons.drag_indicator),
                          label: Text(strings.adjustOrder),
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
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  Expanded(
                    child: controller.isLoadingCache
                        ? const Center(child: CircularProgressIndicator())
                        : _TrackList(
                            controller: controller,
                            list: list,
                            hasActiveFilter: hasActiveFilter,
                            isSelecting: selecting,
                            isReorderEditing: _isReorderEditing,
                            selectedTrackIds: _selectedTrackIds.toSet(),
                            canReorder: canReorder,
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
    required this.controller,
    required this.list,
    required this.hasActiveFilter,
    required this.isSelecting,
    required this.isReorderEditing,
    required this.selectedTrackIds,
    required this.canReorder,
    required this.onStartSelection,
    required this.onToggleSelection,
    required this.onReorder,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final bool hasActiveFilter;
  final bool isSelecting;
  final bool isReorderEditing;
  final Set<String> selectedTrackIds;
  final bool canReorder;
  final ValueChanged<Track> onStartSelection;
  final ValueChanged<Track> onToggleSelection;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
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
            controller: controller,
            list: list,
            track: track,
            tracks: tracks,
            index: index,
            isSelecting: isSelecting,
            isReorderEditing: isReorderEditing,
            selected: selectedTrackIds.contains(track.id),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _TrackTile(
          controller: controller,
          list: list,
          track: track,
          tracks: tracks,
          index: index,
          isSelecting: isSelecting,
          isReorderEditing: isReorderEditing,
          selected: selectedTrackIds.contains(track.id),
          onStartSelection: onStartSelection,
          onToggleSelection: onToggleSelection,
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    super.key,
    required this.controller,
    required this.list,
    required this.track,
    required this.tracks,
    required this.index,
    required this.isSelecting,
    required this.isReorderEditing,
    required this.selected,
    required this.onStartSelection,
    required this.onToggleSelection,
    this.dragHandle,
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final Track track;
  final List<Track> tracks;
  final int index;
  final bool isSelecting;
  final bool isReorderEditing;
  final bool selected;
  final ValueChanged<Track> onStartSelection;
  final ValueChanged<Track> onToggleSelection;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItemStream,
      builder: (context, snapshot) {
        final active = snapshot.data?.id == track.id;
        return ListTile(
          selected: selected,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          leading: isReorderEditing
              ? const Icon(Icons.music_note_outlined)
              : isSelecting
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelection(track),
                )
              : IconButton.filledTonal(
                  tooltip: active ? strings.playing : strings.play,
                  onPressed: () => controller.playTrack(
                    track,
                    index: index,
                    queueTracks: tracks,
                    queueSource: _queueSourceForList(list),
                  ),
                  icon: Icon(active ? Icons.equalizer : Icons.play_arrow),
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
              : () => controller.playTrack(
                  track,
                  index: index,
                  queueTracks: tracks,
                  queueSource: _queueSourceForList(list),
                ),
          onLongPress: isReorderEditing ? null : () => onStartSelection(track),
        );
      },
    );
  }
}

PlaybackQueueSource _queueSourceForList(_ResolvedLibraryList list) {
  if (list.isFavorite) {
    return const PlaybackQueueSource.favorite();
  }
  if (list.canManage && list.playlist != null) {
    return PlaybackQueueSource.customPlaylist(list.playlist!.id);
  }
  return const PlaybackQueueSource.localCache();
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
                  onSwipeLeft: controller.next,
                  onSwipeRight: controller.previous,
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
    MusicUiMessageCode.playingFullAudioStream => strings.playingFullAudioStream,
    MusicUiMessageCode.playingPreviewAudio => strings.playingPreviewAudio,
    MusicUiMessageCode.previewCannotDownload => strings.previewCannotDownload,
  };
}

String _candidateSubtitle(
  AppStrings strings,
  MusicSearchCandidate candidate, {
  required bool isCached,
  required bool isFullAudio,
}) {
  final parts = [
    if (candidate.artist.isNotEmpty) candidate.artist,
    if (candidate.album.isNotEmpty) candidate.album,
    if (_qualityAndSize(candidate).isNotEmpty) _qualityAndSize(candidate),
    if (!isCached && !isFullAudio) strings.candidateUnavailableForDownload,
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
    MusicDataSource.source2t58 => '2t58',
    MusicDataSource.source22a5 => '22a5',
    MusicDataSource.gequhai => '歌海',
    MusicDataSource.gequbao => '歌宝',
    MusicDataSource.kuwoFullAudio => '完整',
    MusicDataSource.itunesPreview => '试听',
    MusicDataSource.auto => 'AUTO',
  };
}
