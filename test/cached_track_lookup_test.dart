import 'package:ai_music/src/data/cached_track_lookup.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:flutter_test/flutter_test.dart';

MusicSearchCandidate candidate({
  String id = 'online',
  String name = '鲜花',
  String artist = '回春丹',
  MusicDataSource source = MusicDataSource.buguyy,
}) => MusicSearchCandidate(
  query: '$name $artist',
  source: source,
  platform: 'kuwo',
  keyword: name,
  page: 1,
  id: id,
  name: name,
  artist: artist,
  album: '',
  duration: 180,
  link: '',
  coverUrl: '',
  qualities: const [],
  score: 0,
  raw: const {},
);

CachedTrack cached(
  String id, {
  String name = '鲜花',
  String artist = '回春丹乐队',
  MusicDataSource source = MusicDataSource.flac,
}) => CachedTrack(
  cacheId: id,
  filePath: '/cache/$id.mp3',
  sizeBytes: 100,
  fromCache: true,
  music: ResolvedMusic(
    query: '',
    source: source,
    platform: 'kuwo',
    id: id,
    name: name,
    artist: artist,
    album: '',
    url: '',
    quality: const MusicQuality(format: 'mp3', bitrate: '320'),
  ),
);

class CountingTrack extends CachedTrack {
  CountingTrack(CachedTrack track)
    : super(
        cacheId: track.cacheId,
        music: track.music,
        filePath: track.filePath,
        sizeBytes: track.sizeBytes,
        fromCache: track.fromCache,
      );
  int reads = 0;
  @override
  ResolvedMusic get music {
    reads++;
    return super.music;
  }
}

void main() {
  test('LAN queries never reuse online recording matches in Auto', () {
    final lookup = CachedTrackLookup()
      ..replace([cached('online'), cached('lan', source: MusicDataSource.lan)]);
    expect(
      lookup.matching(
        candidate(id: 'missing', source: MusicDataSource.lan),
        allowOtherSources: true,
      ),
      isEmpty,
    );
    expect(
      lookup
          .matching(
            candidate(id: 'lan', source: MusicDataSource.lan),
            allowOtherSources: true,
          )
          .map((t) => t.cacheId),
      ['lan'],
    );
  });

  test(
    'Auto combines exact IDs and same recordings in original order once',
    () {
      final lookup = CachedTrackLookup()
        ..replace([
          cached('alternate'),
          cached('online', name: '旧标题', source: MusicDataSource.buguyy),
          cached('both', source: MusicDataSource.buguyy),
          cached('live', name: '鲜花 (Live)'),
          cached('cover', artist: '另一位歌手'),
          cached('lan', source: MusicDataSource.lan),
        ]);
      expect(
        lookup
            .matching(candidate(), allowOtherSources: true)
            .map((t) => t.cacheId),
        ['alternate', 'online', 'both'],
      );
      expect(
        lookup
            .matching(candidate(id: 'both'), allowOtherSources: true)
            .map((t) => t.cacheId),
        ['alternate', 'both'],
      );
      expect(
        lookup
            .matching(candidate(), allowOtherSources: false)
            .map((t) => t.cacheId),
        ['online'],
      );
    },
  );

  test(
    'empty IDs use literal title/artist while blank identities do not merge',
    () {
      final lookup = CachedTrackLookup()
        ..replace([
          cached('same', artist: '回春丹', source: MusicDataSource.buguyy),
          cached('alias', source: MusicDataSource.buguyy),
          cached('empty', name: '', artist: ''),
        ]);
      expect(
        lookup
            .matching(candidate(id: ''), allowOtherSources: false)
            .map((t) => t.cacheId),
        ['same'],
      );
      expect(
        lookup.matching(
          candidate(id: '', name: '', artist: ''),
          allowOtherSources: true,
        ),
        isEmpty,
      );
    },
  );

  test('replacement removes deleted records and updates changed metadata', () {
    final lookup = CachedTrackLookup()
      ..replace([cached('first'), cached('second')]);
    expect(lookup.matching(candidate(), allowOtherSources: true), hasLength(2));
    lookup.replace([cached('second', name: '鲜花 (Live)')]);
    expect(lookup.matching(candidate(), allowOtherSources: true), isEmpty);
    expect(
      lookup
          .matching(candidate(name: '鲜花 (Live)'), allowOtherSources: true)
          .single
          .cacheId,
      'second',
    );
    lookup.replace([]);
    expect(
      lookup.matching(candidate(name: '鲜花 (Live)'), allowOtherSources: true),
      isEmpty,
    );
  });

  test('in-flight cache validation retains its original library snapshot', () {
    final lookup = CachedTrackLookup()
      ..replace([cached('first'), cached('second')]);
    final inFlight = lookup.matching(candidate(), allowOtherSources: true);
    final iterator = inFlight.iterator;
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current.cacheId, 'first');
    // A download can await file validation between records while another
    // download or cache cleanup publishes a replacement library.
    lookup.replace([cached('new', name: '另一首歌')]);
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current.cacheId, 'second');
    expect(iterator.moveNext(), isFalse);
  });

  test('result rows do not rescan hundreds of cached recordings', () {
    final records = List.generate(
      350,
      (i) => CountingTrack(cached('$i', name: '歌曲$i')),
    );
    final lookup = CachedTrackLookup()..replace(records);
    for (final track in records) {
      track.reads = 0;
    }
    for (var pass = 0; pass < 3; pass++) {
      for (var row = 0; row < 40; row++) {
        expect(
          lookup
              .matching(candidate(name: '歌曲$row'), allowOtherSources: true)
              .single
              .cacheId,
          '$row',
        );
      }
    }
    expect(records.fold(0, (total, track) => total + track.reads), 0);
  });
}
