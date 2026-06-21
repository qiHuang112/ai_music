import 'package:audio_service/audio_service.dart';

import '../data/lyrics_artwork.dart';
import '../data/music_cache.dart';
import '../domain/music_models.dart';

Track trackFromCached(CachedTrack cached) {
  return Track(
    id: cached.cacheId,
    title: cached.music.name.isEmpty ? cached.music.query : cached.music.name,
    artist: cached.music.artist,
    album: cached.music.album,
    filePath: cached.filePath,
    sizeBytes: cached.sizeBytes,
    artworkUri: artworkUriFromText(cached.music.coverUrl),
    cachedAt: cached.cachedAt,
  );
}

MediaItem mediaItemFromTrack(Track track) {
  return MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album.isEmpty ? null : track.album,
    artUri: track.artworkUri,
    duration: track.duration,
    extras: {'filePath': track.playbackSource, 'sizeBytes': track.sizeBytes},
  );
}
