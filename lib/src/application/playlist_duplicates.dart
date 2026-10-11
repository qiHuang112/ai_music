import 'dart:convert';

import '../data/music_playlists.dart';
import '../data/song_match_identity.dart';
import '../domain/music_models.dart';

class PlaylistDuplicateGroup {
  PlaylistDuplicateGroup(this.title, this.artist, List<String> trackIds)
    : trackIds = List.unmodifiable(trackIds);

  final String title;
  final String artist;
  // Original playlist order: retain the first entry.
  final List<String> trackIds;
  int get removeCount => trackIds.length - 1;
}

class PlaylistDuplicatePlan {
  PlaylistDuplicatePlan(this.playlistId, List<PlaylistDuplicateGroup> groups)
    : groups = List.unmodifiable(groups);

  final String playlistId;
  final List<PlaylistDuplicateGroup> groups;
  Set<String> get removedIds => {
    for (final group in groups) ...group.trackIds.skip(1),
  };
  int get removeCount => removedIds.length;
  String get signature => jsonEncode([
    playlistId,
    for (final group in groups) [group.title, group.artist, group.trackIds],
  ]);
}

PlaylistDuplicatePlan findPlaylistDuplicates(
  MusicPlaylist playlist,
  List<Track> tracks,
) {
  final byId = {for (final track in tracks) track.id: track};
  final groups = <String, List<String>>{};
  final labels = <String, (String, String)>{};
  for (final entry in playlist.entries) {
    // Compare the user's original song, rather than a possibly wrong match.
    final title =
        entry.song?.title ??
        entry.onlineTrack?.candidate.name ??
        byId[entry.trackId]?.title ??
        '';
    final artist =
        entry.song?.artist ??
        entry.onlineTrack?.candidate.artist ??
        byId[entry.trackId]?.artist ??
        '';
    final artists = artistNamesForMatch(artist).toList()..sort();
    // Keep complete version/venue labels for destructive deduplication.
    // SongMatchIdentity's broad Live category is suitable for matching, but
    // would merge distinct live performances here.
    final name = normalizeSongText(
      title.replaceAll(
        RegExp(r'[（(]\s*version\s*[）)]', caseSensitive: false),
        '',
      ),
    );
    if (name.isEmpty || artists.isEmpty) continue;
    final key = jsonEncode([name, artists]);
    groups.putIfAbsent(key, () => []).add(entry.trackId);
    labels.putIfAbsent(key, () => (title, artist));
  }
  return PlaylistDuplicatePlan(playlist.id, [
    for (final group in groups.entries)
      if (group.value.length > 1)
        PlaylistDuplicateGroup(
          labels[group.key]!.$1,
          labels[group.key]!.$2,
          group.value,
        ),
  ]);
}
