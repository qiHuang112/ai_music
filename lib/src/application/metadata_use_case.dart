import '../data/lyrics_artwork.dart';
import '../data/music_cache.dart';
import '../domain/music_models.dart';

class MetadataUseCase {
  const MetadataUseCase({required this.repository});

  final TrackMetadataRepository repository;

  Future<TrackMetadata> load(CachedTrack track) {
    return repository.load(track);
  }

  Future<TrackMetadata> loadBypassingMetadataMiss(CachedTrack track) {
    return repository.loadBypassingMetadataMiss(track);
  }

  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) {
    return loadBypassingMetadataMiss(track);
  }

  Future<void> delete(String trackId) {
    return repository.delete(trackId);
  }
}
