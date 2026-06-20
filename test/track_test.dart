import 'package:flutter_test/flutter_test.dart';
import 'package:music/features/library/domain/track.dart';

void main() {
  test('serializes library tracks with cache metadata', () {
    const track = Track(
      id: 'song-1',
      title: 'Song',
      artist: 'Artist',
      album: 'Local Music',
      fileName: 'Artist-Song.mp3',
      extension: 'mp3',
      size: 1024,
      sourceUrl: 'http://127.0.0.1:8787/media/Artist-Song.mp3',
      localPath: r'C:\app\music\song-1.mp3',
      cacheState: TrackCacheState.cached,
    );

    final body = tracksToLibraryJson([track]);
    final decoded = tracksFromLibraryJson(body);

    expect(decoded, hasLength(1));
    expect(decoded.single.title, 'Song');
    expect(decoded.single.isCached, isTrue);
    expect(decoded.single.localPath, track.localPath);
  });
}
