import 'package:ai_music/src/data/legacy_cache_repairer.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy repair writes back high confidence metadata and lyrics',
    () async {
      final cache = _RepairCacheStore([_legacyTrack()]);
      final resolver = _RepairResolver(
        candidates: [_candidate(score: 96)],
        resolved: _resolved(),
      );
      final repairer = LegacyCacheRepairer(
        resolver: resolver,
        cacheStore: cache,
      );

      final count = await repairer.repair(cache.cached);

      expect(count, 1);
      expect(cache.updated.single.music.name, '稻香');
      expect(cache.updated.single.music.artist, '周杰伦');
      expect(cache.updated.single.music.lyrics?.text, '[00:01.00]第一句');
      expect(cache.updated.single.cacheId, cache.cached.single.cacheId);
    },
  );

  test('legacy repair skips low confidence candidates', () async {
    final cache = _RepairCacheStore([_legacyTrack()]);
    final resolver = _RepairResolver(
      candidates: [_candidate(score: 70)],
      resolved: _resolved(),
    );
    final repairer = LegacyCacheRepairer(resolver: resolver, cacheStore: cache);

    final count = await repairer.repair(cache.cached);

    expect(count, 0);
    expect(cache.updated, isEmpty);
  });

  test(
    'legacy repair never rewrites LAN tracks with optional sidecars',
    () async {
      final cache = _RepairCacheStore([_lanTrack()]);
      final resolver = _RepairResolver(
        candidates: [_candidate(score: 99)],
        resolved: _resolved(),
      );
      final repairer = LegacyCacheRepairer(
        resolver: resolver,
        cacheStore: cache,
      );

      final count = await repairer.repair(cache.cached);

      expect(count, 0);
      expect(resolver.searchCalls, 0);
      expect(cache.updated, isEmpty);
    },
  );
}

class _RepairResolver implements MusicResolver {
  _RepairResolver({required this.candidates, required this.resolved});

  final List<MusicSearchCandidate> candidates;
  final ResolvedMusic resolved;
  int searchCalls = 0;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchCalls += 1;
    return candidates;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return resolved;
  }
}

class _RepairCacheStore extends CachedTrackStore {
  _RepairCacheStore(this.cached);

  final List<CachedTrack> cached;
  final updated = <CachedTrack>[];

  @override
  Future<CachedTrack> updateCachedMusic(
    CachedTrack cached,
    ResolvedMusic music,
  ) async {
    final repaired = cached.copyWith(music: music, lyricsPath: '/tmp/song.lrc');
    updated.add(repaired);
    return repaired;
  }
}

CachedTrack _legacyTrack() {
  return CachedTrack(
    cacheId: 'legacy-1',
    music: const ResolvedMusic(
      query: '',
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: '',
      name: '',
      artist: '',
      album: '',
      url: 'file:///tmp/周杰伦-稻香.mp3',
      quality: MusicQuality(format: 'mp3'),
    ),
    filePath: '/tmp/周杰伦-稻香.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
}

CachedTrack _lanTrack() {
  return CachedTrack(
    cacheId: 'lan-track',
    music: const ResolvedMusic(
      query: '跟随医护',
      source: MusicDataSource.lan,
      platform: 'lan:library-one',
      id: 'lamaze-follow-care-team',
      name: '跟随医护',
      artist: 'AI Home',
      album: '拉玛泽呼吸引导',
      url: 'http://192.168.31.57:8787/api/v1/files/Lamaze/04.mp3',
      quality: MusicQuality(format: 'mp3'),
    ),
    filePath: '/tmp/跟随医护.mp3',
    sizeBytes: 4,
    fromCache: true,
  );
}

MusicSearchCandidate _candidate({required double score}) {
  return MusicSearchCandidate(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    keyword: '周杰伦 稻香',
    page: 1,
    id: 'song-1',
    name: '稻香',
    artist: '周杰伦',
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: score,
    raw: const {},
  );
}

ResolvedMusic _resolved() {
  return const ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'song-1',
    name: '稻香',
    artist: '周杰伦',
    album: '',
    url: 'https://cdn.example.test/song-1.mp3',
    quality: MusicQuality(format: 'mp3'),
    lyrics: ResolvedLyrics(
      source: 'buguyy:geturl:lrc',
      text: '[00:01.00]第一句',
      lines: 1,
      timed: true,
    ),
  );
}
