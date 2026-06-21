import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../application/music_ui_message.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';
import 'download_manager_page.dart';
import 'list_search.dart';
import 'player_page.dart';
import 'playlist_actions.dart';
import 'settings_page.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final _searchController = TextEditingController();

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
        return Scaffold(
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
                          _localizedMessage(strings, controller.errorMessage) ??
                          controller.errorDetail,
                      status: _localizedMessage(
                        strings,
                        controller.statusMessage,
                      ),
                      onRetry: () => controller.search(_searchController.text),
                      onSelect: controller.downloadCandidate,
                      onPlay: controller.playCandidate,
                      onOpenDownloads: _openDownloads,
                    ),
                  )
                else
                  Expanded(child: _SearchBody(controller: controller)),
              ],
            ),
          ),
          bottomNavigationBar: _MiniPlayer(controller: controller),
        );
      },
    );
  }

  bool get _shouldShowSearchPanel {
    return controller.isSearching ||
        controller.candidates.isNotEmpty ||
        controller.errorMessage != null ||
        controller.errorDetail != null ||
        controller.statusMessage != null;
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

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSearching;
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
    required this.status,
    required this.onRetry,
    required this.onSelect,
    required this.onPlay,
    required this.onOpenDownloads,
  });

  final List<MusicSearchCandidate> candidates;
  final bool isSearching;
  final bool Function(MusicSearchCandidate candidate) isCandidateBusy;
  final bool Function(MusicSearchCandidate candidate) isCandidateCached;
  final String? error;
  final String? status;
  final VoidCallback onRetry;
  final ValueChanged<MusicSearchCandidate> onSelect;
  final ValueChanged<MusicSearchCandidate> onPlay;
  final VoidCallback onOpenDownloads;

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
            if (status != null && error == null)
              InkWell(
                onTap: onOpenDownloads,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.downloading),
                  title: Text(
                    status!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
                            : const Icon(Icons.music_note),
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
  const _SearchBody({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (controller.isSearching) {
      return const SizedBox.shrink();
    }
    if (controller.candidates.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Padding(
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
      ),
    );
  }
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

enum _LibrarySortMode { time, initial }

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
  String _query = '';

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
        final rawList = _resolveLibraryList(
          controller,
          widget.selection,
          strings,
        );
        final list = rawList.copyWith(
          tracks: filterTracksByQuery(
            _sortLibraryTracks(controller, rawList, _sortMode),
            _query,
          ),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(list.title),
            actions: [
              _LibrarySortButton(
                mode: _sortMode,
                timeLabel: list.isLocal
                    ? strings.sortByDownloadTime
                    : strings.sortByAddedTime,
                onChanged: (mode) => setState(() => _sortMode = mode),
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
                          hasActiveFilter: _query.trim().isNotEmpty,
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _MiniPlayer(controller: controller),
        );
      },
    );
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

class _LibrarySortButton extends StatelessWidget {
  const _LibrarySortButton({
    required this.mode,
    required this.timeLabel,
    required this.onChanged,
  });

  final _LibrarySortMode mode;
  final String timeLabel;
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
  });

  final MusicController controller;
  final _ResolvedLibraryList list;
  final bool hasActiveFilter;

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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return StreamBuilder<MediaItem?>(
          stream: controller.mediaItemStream,
          builder: (context, snapshot) {
            final active = snapshot.data?.id == track.id;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              leading: IconButton.filledTonal(
                tooltip: active ? strings.playing : strings.play,
                onPressed: () => controller.playTrack(
                  track,
                  index: index,
                  queueTracks: tracks,
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
              trailing: _TrackActions(
                controller: controller,
                list: list,
                track: track,
              ),
              onTap: () => controller.playTrack(
                track,
                index: index,
                queueTracks: tracks,
              ),
            );
          },
        );
      },
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
        PopupMenuButton<_TrackAction>(
          tooltip: strings.more,
          onSelected: (action) => _handle(context, action),
          itemBuilder: (context) {
            return [
              PopupMenuItem(
                value: _TrackAction.addToPlaylist,
                child: Text(strings.addToPlaylist),
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
      case _TrackAction.addToPlaylist:
        await showAddToPlaylistSheet(context, controller, track);
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

enum _TrackAction { addToPlaylist, removeFromCurrent }

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
                          tooltip: state.playing ? strings.pause : strings.play,
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
    if (candidate.platform.isNotEmpty &&
        candidate.platform.toLowerCase() != 'buguyy')
      candidate.platform,
    if (candidate.qualityLabel.isNotEmpty) candidate.qualityLabel,
    if (candidate.duration > 0)
      _formatCandidateDuration(Duration(seconds: candidate.duration)),
  ];
  return parts.join(' - ');
}

String _formatCandidateDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
