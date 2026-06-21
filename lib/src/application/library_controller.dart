import '../data/music_playlists.dart';
import '../domain/music_models.dart';

class LibraryController {
  const LibraryController();

  List<Track> tracksForIds(List<String> ids, List<Track> cachedTracks) {
    final byId = {for (final track in cachedTracks) track.id: track};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Set<String> validTrackIds(List<Track> cachedTracks) {
    return {for (final track in cachedTracks) track.id};
  }

  List<MusicPlaylist> removeTrackFromPlaylists(
    List<MusicPlaylist> playlists,
    String trackId,
  ) {
    return [
      for (final playlist in playlists)
        playlist.copyWith(
          entries: [
            for (final entry in playlist.entries)
              if (entry.trackId != trackId) entry,
          ],
        ),
    ];
  }
}
