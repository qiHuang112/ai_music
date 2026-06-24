import '../data/lyrics_artwork.dart';
import '../data/music_cache.dart';
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

  Future<void> delete(String trackId) {
    return repository.delete(trackId);
  }
}
