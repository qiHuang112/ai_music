import 'dart:async';
import 'dart:io';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

MusicSearchCandidate candidate(
  String id, {
  MusicDataSource source = MusicDataSource.flac,
}) => MusicSearchCandidate(
  query: '歌曲 歌手',
  source: source,
  platform: 'kuwo',
  keyword: '歌曲',
  page: 1,
  id: id,
  name: '歌曲$id',
  artist: '歌手',
  album: '专辑',
  duration: 180,
  link: 'https://expired.test/audio',
  coverUrl: '',
  qualities: const [MusicQuality(format: 'mp3', bitrate: '128')],
  score: 23.5,
  raw: const {'sign': 'lookup-token', 'url': 'https://expired.test/raw'},
);

void main() {
  test(
    'candidates survive restart with ordering/score/sign but no media URLs',
    () async {
      final root = await Directory.systemTemp.createTemp('song_search_');
      addTearDown(() => root.delete(recursive: true));
      final cache = SongSearchCache(rootProvider: () async => root);
      final key = SongSearchCache.searchKey('歌曲 歌手', MusicDataSource.auto);
      await cache.search(key, () async => [candidate('2'), candidate('1')]);
      final next = SongSearchCache(rootProvider: () async => root);
      final result = await next.search(
        key,
        () => throw StateError('Must reuse cache'),
      );
      expect(result.map((c) => c.id), ['2', '1']);
      expect(result.first.score, 23.5);
      expect(result.first.raw['sign'], 'lookup-token');
      expect(result.first.link, isEmpty);
      expect(result.first.raw.containsKey('url'), isFalse);
      expect(
        (await File(
          '${root.path}/song_search_cache.json',
        ).readAsString()).contains('expired.test'),
        isFalse,
      );
    },
  );

  test(
    'in-flight queries are shared, failures and empty results remain retryable',
    () async {
      final cache = SongSearchCache.memory();
      final gate = Completer<List<MusicSearchCandidate>>();
      var calls = 0;
      final a = cache.search('same', () {
        calls++;
        return gate.future;
      });
      final b = cache.search('same', () {
        calls++;
        return gate.future;
      });
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      gate.complete([candidate('1')]);
      await Future.wait([a, b]);
      await expectLater(
        cache.search('error', () => throw StateError('Offline')),
        throwsStateError,
      );
      expect(
        await cache.search('error', () async => [candidate('ok')]),
        hasLength(1),
      );
      expect(await cache.search('empty', () async => []), isEmpty);
      expect(
        await cache.search('empty', () async => [candidate('ok')]),
        hasLength(1),
      );
    },
  );

  test('query/source separation, explicit refresh and expiry', () async {
    var now = DateTime(2026, 10, 5);
    final cache = SongSearchCache.memory(now: () => now);
    final all = SongSearchCache.searchKey(' A ', MusicDataSource.auto);
    final flac = SongSearchCache.searchKey('a', MusicDataSource.flac);
    await cache.search(all, () async => [candidate('all')]);
    await cache.search(flac, () async => [candidate('flac')]);
    expect(
      (await cache.search(all, () => throw StateError('no'))).single.id,
      'all',
    );
    expect(
      (await cache.search(flac, () => throw StateError('no'))).single.id,
      'flac',
    );
    expect(
      (await cache.search(
        all,
        () async => [candidate('refresh')],
        refresh: true,
      )).single.id,
      'refresh',
    );
    now = now.add(const Duration(days: 2));
    expect(
      (await cache.search(all, () async => [candidate('expired')])).single.id,
      'expired',
    );
  });

  test('damaged disk data is ignored and oldest entries are bounded', () async {
    final root = await Directory.systemTemp.createTemp('song_search_limit_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/song_search_cache.json');
    await file.writeAsString('{bad');
    var now = DateTime(2026, 10, 5);
    final cache = SongSearchCache(
      rootProvider: () async => root,
      now: () => now,
      maxEntries: 2,
    );
    for (final key in ['a', 'b', 'c']) {
      await cache.search(key, () async => [candidate(key)]);
      now = now.add(const Duration(seconds: 1));
    }
    final next = SongSearchCache(
      rootProvider: () async => root,
      now: () => now,
    );
    expect(
      (await next.search('b', () => throw StateError('no'))).single.id,
      'b',
    );
    expect(
      (await next.search('a', () async => [candidate('new')])).single.id,
      'new',
    );
  });
}
