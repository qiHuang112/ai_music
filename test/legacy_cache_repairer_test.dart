import 'dart:async';

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
      expect(cache.updated.single.music.source, MusicDataSource.flac);
      expect(resolver.searchedSources, [MusicDataSource.flac]);
    },
  );

  test(
    'metadata repair preserves existing FLAC identity and known display credits',
    () async {
      final track = _knownTrack();
      final cache = _RepairCacheStore([track]);
      final resolver = _RepairResolver(
        candidates: [_candidate(score: 96, source: MusicDataSource.buguyy)],
        resolved: _resolved(source: MusicDataSource.buguyy),
      );
      final repairer = LegacyCacheRepairer(
        resolver: resolver,
        cacheStore: cache,
        sourceProvider: () => MusicDataSource.buguyy,
      );
      expect(await repairer.repair(cache.cached), 1);
      final updated = cache.updated.single.music;
      expect(resolver.searchedSources, [MusicDataSource.buguyy]);
      expect(updated.source, MusicDataSource.flac);
      expect(updated.platform, 'wyy');
      expect(updated.id, 'real-flac-id');
      expect(updated.name, '稻香');
      expect(updated.artist, '周杰倫');
      expect(updated.url, track.music.url);
      expect(updated.quality, same(track.music.quality));
      expect(updated.lyrics, isNotNull);
    },
  );

  test(
    'high numeric score cannot overwrite metadata of a different recording',
    () async {
      for (final candidate in [
        _candidate(score: 99, title: '晴天'),
        _candidate(score: 99, artist: '林俊杰'),
        _candidate(score: 99, title: '稻香 (Live)'),
      ]) {
        final cache = _RepairCacheStore([_knownTrack()]);
        final resolver = _RepairResolver(
          candidates: [candidate],
          resolved: _resolved(),
        );
        expect(
          await LegacyCacheRepairer(
            resolver: resolver,
            cacheStore: cache,
          ).repair(cache.cached),
          0,
        );
        expect(cache.updated, isEmpty);
        expect(resolver.resolveCalls, 0);
      }
    },
  );

  test(
    'resolve returning a different song cannot change existing metadata',
    () async {
      final cache = _RepairCacheStore([_knownTrack()]);
      final resolver = _RepairResolver(
        candidates: [_candidate(score: 99)],
        resolved: _resolved(title: '晴天'),
      );
      expect(
        await LegacyCacheRepairer(
          resolver: resolver,
          cacheStore: cache,
        ).repair(cache.cached),
        0,
      );
      expect(cache.updated, isEmpty);
    },
  );

  test(
    'a known title stays protected when query is identical and artist is missing',
    () async {
      final cache = _RepairCacheStore([
        _knownTrack().copyWith(
          music: const ResolvedMusic(
            query: '稻香',
            source: MusicDataSource.flac,
            platform: 'wyy',
            id: 'real-flac-id',
            name: '稻香',
            artist: '',
            album: '',
            url: 'https://flac.example/old-audio.flac',
            quality: MusicQuality(format: 'flac'),
          ),
        ),
      ]);
      final resolver = _RepairResolver(
        candidates: [_candidate(score: 99, title: '晴天')],
        resolved: _resolved(title: '晴天'),
      );
      expect(
        await LegacyCacheRepairer(
          resolver: resolver,
          cacheStore: cache,
        ).repair(cache.cached),
        0,
      );
      expect(cache.updated, isEmpty);
      expect(resolver.resolveCalls, 0);
    },
  );

  for (final changeDuringResolve in [false, true]) {
    test(
      'source switch during ${changeDuringResolve ? 'resolution' : 'search'} drops stale repair and retries',
      () async {
        var source = MusicDataSource.buguyy;
        final cache = _RepairCacheStore([_knownTrack()]);
        final resolver = _RepairResolver(
          candidates: [_candidate(score: 99, source: MusicDataSource.buguyy)],
          resolved: _resolved(source: MusicDataSource.buguyy),
        );
        final gate = Completer<void>();
        if (changeDuringResolve) {
          resolver.resolveGate = gate;
        } else {
          resolver.searchGate = gate;
        }
        final work = LegacyCacheRepairer(
          resolver: resolver,
          cacheStore: cache,
          sourceProvider: () => source,
        ).repair(cache.cached);
        await (changeDuringResolve
                ? resolver.resolveStarted
                : resolver.searchStarted)
            .future;
        source = MusicDataSource.flac;
        resolver.candidates = [_candidate(score: 99)];
        resolver.resolved = _resolved();
        gate.complete();
        expect(await work, 1);
        expect(resolver.searchedSources, [
          MusicDataSource.buguyy,
          MusicDataSource.flac,
        ]);
        expect(cache.updated, hasLength(1));
        expect(cache.updated.single.music.id, 'real-flac-id');
        expect(cache.updated.single.music.source, MusicDataSource.flac);
      },
    );
  }

  test(
    'auto repair respects the optional health-aware resolution policy',
    () async {
      final cache = _RepairCacheStore([_legacyTrack()]);
      final resolver = _HealthRepairResolver();
      final repairer = LegacyCacheRepairer(
        resolver: resolver,
        cacheStore: cache,
        sourceProvider: () => MusicDataSource.auto,
      );
      expect(await repairer.repair(cache.cached), 1);
      expect(resolver.searchedSources, [MusicDataSource.auto]);
      expect(resolver.resolvedModes, [MusicDataSource.auto]);
      expect(resolver.resolveCalls, 0);
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

  List<MusicSearchCandidate> candidates;
  ResolvedMusic resolved;
  int searchCalls = 0;
  int resolveCalls = 0;
  final searchedSources = <MusicDataSource>[];
  Completer<void>? searchGate;
  Completer<void>? resolveGate;
  final searchStarted = Completer<void>();
  final resolveStarted = Completer<void>();

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searchCalls += 1;
    searchedSources.add(source);
    final result = candidates;
    if (!searchStarted.isCompleted) searchStarted.complete();
    await searchGate?.future;
    return result;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveCalls++;
    final result = resolved;
    if (!resolveStarted.isCompleted) resolveStarted.complete();
    await resolveGate?.future;
    return result;
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

MusicSearchCandidate _candidate({
  required double score,
  MusicDataSource source = MusicDataSource.flac,
  String title = '稻香',
  String artist = '周杰伦',
}) {
  return MusicSearchCandidate(
    query: '周杰伦 稻香',
    source: source,
    platform: source.storageValue,
    keyword: '周杰伦 稻香',
    page: 1,
    id: 'song-1',
    name: title,
    artist: artist,
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: score,
    raw: const {},
  );
}

ResolvedMusic _resolved({
  MusicDataSource source = MusicDataSource.flac,
  String title = '稻香',
}) {
  return ResolvedMusic(
    query: '周杰伦 稻香',
    source: source,
    platform: source.storageValue,
    id: 'song-1',
    name: title,
    artist: '周杰伦',
    album: '',
    url: 'https://cdn.example.test/song-1.mp3',
    quality: const MusicQuality(format: 'mp3'),
    lyrics: const ResolvedLyrics(
      source: 'buguyy:geturl:lrc',
      text: '[00:01.00]第一句',
      lines: 1,
      timed: true,
    ),
  );
}

CachedTrack _knownTrack() => const CachedTrack(
  cacheId: 'known-cache',
  music: ResolvedMusic(
    query: '周杰伦 稻香',
    source: MusicDataSource.flac,
    platform: 'wyy',
    id: 'real-flac-id',
    name: '稻香',
    artist: '周杰倫',
    album: '',
    url: 'https://flac.example/old-audio.flac',
    quality: MusicQuality(format: 'flac'),
  ),
  filePath: '/tmp/known.flac',
  sizeBytes: 123,
  fromCache: true,
);

class _HealthRepairResolver extends _RepairResolver
    implements AutoSourceHealthResolver {
  _HealthRepairResolver()
    : super(candidates: [_candidate(score: 99)], resolved: _resolved());
  final resolvedModes = <MusicDataSource>[];

  @override
  Future<ResolvedMusic> resolveForSourceMode(
    MusicSearchCandidate candidate,
    MusicDataSource mode, {
    MusicQualityLevel? quality,
  }) async {
    resolvedModes.add(mode);
    return resolved;
  }

  @override
  List<MusicDataSource> get availableAutoSources => [MusicDataSource.flac];

  @override
  bool isSourceAvailableForAuto(MusicDataSource source) =>
      source == MusicDataSource.flac;

  @override
  String? sourceDegradationReason(MusicDataSource source) => null;

  @override
  void reportSourceFailure(MusicDataSource source, Object error) {}

  @override
  void reportSourceSuccess(MusicDataSource source) {}
}
