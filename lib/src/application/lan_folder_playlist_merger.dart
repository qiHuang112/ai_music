import '../data/music_playlists.dart';

class LanFolderTrack {
  const LanFolderTrack({
    required this.index,
    required this.folderPath,
    required this.trackId,
  });

  final int index;
  final String folderPath;
  final String trackId;
}

class LanFolderPlaylistMergeResult {
  const LanFolderPlaylistMergeResult({
    required this.created,
    required this.updated,
  });

  const LanFolderPlaylistMergeResult.empty() : created = 0, updated = 0;

  final int created;
  final int updated;
}

String lanFolderKey(String libraryId, String folderPath) {
  return 'lan:$libraryId:folder:${folderPath.toLowerCase()}';
}

class LanFolderPlaylistMerger {
  LanFolderPlaylistMerger({
    required this.store,
    DateTime Function()? now,
    String Function()? playlistIdFactory,
  }) : _now = now ?? DateTime.now,
       _playlistIdFactory = playlistIdFactory;

  final PlaylistStore store;
  final DateTime Function() _now;
  final String Function()? _playlistIdFactory;
  int _nextId = 0;

  Future<LanFolderPlaylistMergeResult> merge({
    required String libraryId,
    required Iterable<LanFolderTrack> tracks,
    required Set<String> validTrackIds,
  }) async {
    final ordered =
        tracks
            .where(
              (track) =>
                  track.folderPath.isNotEmpty &&
                  validTrackIds.contains(track.trackId),
            )
            .toList(growable: false)
          ..sort((left, right) => left.index.compareTo(right.index));
    if (ordered.isEmpty) {
      return const LanFolderPlaylistMergeResult.empty();
    }

    final groups = <String, _FolderGroup>{};
    for (final track in ordered) {
      final key = lanFolderKey(libraryId, track.folderPath);
      final group = groups.putIfAbsent(
        key,
        () => _FolderGroup(
          folderPath: track.folderPath,
          key: key,
          trackIds: <String>[],
        ),
      );
      if (!group.trackIds.contains(track.trackId)) {
        group.trackIds.add(track.trackId);
      }
    }

    final library = await store.load();
    final playlists = [...library.playlists];
    var created = 0;
    var updated = 0;
    var changed = false;

    for (final group in groups.values) {
      var playlistIndex = playlists.indexWhere(
        (playlist) => playlist.lanFolderKey == group.key,
      );
      if (playlistIndex < 0) {
        playlistIndex = playlists.indexWhere(
          (playlist) =>
              playlist.lanFolderKey.isEmpty &&
              playlist.name == group.folderPath,
        );
      }

      final now = _now();
      if (playlistIndex < 0) {
        final playlist = MusicPlaylist(
          id: _uniquePlaylistId(playlists, now),
          name: _availablePlaylistName(playlists, group.folderPath),
          lanFolderKey: group.key,
          entries: [
            for (final trackId in group.trackIds)
              PlaylistTrackEntry(trackId: trackId, addedAt: now),
          ],
          createdAt: now,
          updatedAt: now,
        );
        playlists.add(playlist);
        created += 1;
        changed = true;
        continue;
      }

      final existing = playlists[playlistIndex];
      final seen = existing.trackIds.toSet();
      final additions = [
        for (final trackId in group.trackIds)
          if (seen.add(trackId))
            PlaylistTrackEntry(trackId: trackId, addedAt: now),
      ];
      final adoptsFolder = existing.lanFolderKey.isEmpty;
      if (!adoptsFolder && additions.isEmpty) {
        continue;
      }
      playlists[playlistIndex] = existing.copyWith(
        lanFolderKey: group.key,
        entries: [...existing.entries, ...additions],
        updatedAt: now,
      );
      updated += 1;
      changed = true;
    }

    if (changed) {
      await store.write(
        library.copyWith(playlists: playlists),
        validTrackIds: validTrackIds,
      );
    }
    return LanFolderPlaylistMergeResult(created: created, updated: updated);
  }

  String _uniquePlaylistId(List<MusicPlaylist> playlists, DateTime now) {
    final base =
        _playlistIdFactory?.call() ??
        'lan-playlist-${now.microsecondsSinceEpoch}-${++_nextId}';
    var candidate = base;
    var suffix = 2;
    final ids = {for (final playlist in playlists) playlist.id};
    while (ids.contains(candidate)) {
      candidate = '$base-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  String _availablePlaylistName(
    List<MusicPlaylist> playlists,
    String folderPath,
  ) {
    final names = {for (final playlist in playlists) playlist.name};
    if (!names.contains(folderPath)) {
      return folderPath;
    }
    var suffix = 2;
    while (names.contains('$folderPath（局域网 $suffix）')) {
      suffix += 1;
    }
    return '$folderPath（局域网 $suffix）';
  }
}

class _FolderGroup {
  _FolderGroup({
    required this.folderPath,
    required this.key,
    required this.trackIds,
  });

  final String folderPath;
  final String key;
  final List<String> trackIds;
}
