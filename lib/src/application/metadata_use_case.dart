import '../data/lyrics_artwork.dart';
import '../data/music_cache.dart';
import '../data/song_comments.dart' show SongCommentQuery;
import '../domain/music_models.dart';

class MetadataUseCase {
  const MetadataUseCase({required this.repository});

  final TrackMetadataRepository repository;

  Future<TrackMetadata> load(CachedTrack track) {
    return repository.load(track);
  }

  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) {
    return repository.loadBypassingLyricsMiss(track);
  }

  Future<TrackMetadata> prefetchLyrics(CachedTrack track) {
    return repository.prefetchLyrics(track);
  }

  Future<TrackMetadata> upgradeTimedLyrics(
    CachedTrack track, {
    SongCommentQuery? original,
  }) {
    return repository.upgradeTimedLyrics(track, original: original);
  }

  Future<void> delete(String trackId) {
    return repository.delete(trackId);
  }
}
