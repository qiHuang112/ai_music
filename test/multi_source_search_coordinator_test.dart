import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/data/multi_source_search_coordinator.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('batches the first ready results across sources', () async {
    final gequhai = _ProviderHarness(MusicDataSource.gequhai);
    final kuwo = _ProviderHarness(MusicDataSource.kuwoFullAudio);
    final coordinator = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    );
    final emissions = <MusicSearchProgress>[];
    final done = Completer<void>();

    coordinator
        .searchPage('周杰伦', page: 1)
        .listen(emissions.add, onDone: done.complete);
    await _flushEvents();

    kuwo
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '晴天')],
            isComplete: true,
            page: 1,
            hasNextPage: true,
          ),
        );
    await _flushEvents();
    expect(emissions, isEmpty);

    gequhai
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [_readyCandidate(MusicDataSource.gequhai, '夜曲')],
            isComplete: true,
            page: 1,
            hasNextPage: true,
          ),
        );
    await _flushEvents();
    expect(emissions.last.candidates.map((item) => item.name), ['晴天', '夜曲']);

    await Future.wait([gequhai.close(1), kuwo.close(1)]);
    await done.future;
    expect(emissions.last.isComplete, isTrue);
  });

  test('filters candidates that are not client ready', () async {
    final gequhai = _ProviderHarness(MusicDataSource.gequhai);
    final kuwo = _ProviderHarness(MusicDataSource.kuwoFullAudio);
    final future = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    ).searchPage('Angel', page: 1).toList();
    await _flushEvents();

    gequhai
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [
              _readyCandidate(MusicDataSource.gequhai, 'Angel'),
              _candidate(MusicDataSource.gequhai, 'HTML result'),
            ],
            isComplete: true,
            page: 1,
          ),
        );
    kuwo
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [
              _candidate(MusicDataSource.kuwoFullAudio, 'Validating'),
            ],
            isComplete: true,
            page: 1,
          ),
        );
    await Future.wait([gequhai.close(1), kuwo.close(1)]);

    final emissions = await future;
    expect(emissions.last.candidates.map((item) => item.name), ['Angel']);
  });

  test(
    'batches initial and later additions instead of exposing one row at a time',
    () async {
      final provider = _ImmediateProvider(
        MusicDataSource.kuwoFullAudio,
        (_) => Stream.fromIterable([
          MusicSearchProgress(
            candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '第一首')],
            isComplete: false,
          ),
          MusicSearchProgress(
            candidates: [
              _readyCandidate(MusicDataSource.kuwoFullAudio, '第一首'),
              _readyCandidate(MusicDataSource.kuwoFullAudio, '第二首'),
            ],
            isComplete: false,
          ),
          MusicSearchProgress(
            candidates: [
              _readyCandidate(MusicDataSource.kuwoFullAudio, '第一首'),
              _readyCandidate(MusicDataSource.kuwoFullAudio, '第二首'),
              _readyCandidate(MusicDataSource.kuwoFullAudio, '第三首'),
            ],
            isComplete: true,
          ),
        ]),
      );

      final emissions = await MultiSourceSearchCoordinator(
        providers: [provider.provider],
      ).searchPage('歌手', page: 1).toList();
      final visibleCounts = emissions
          .where((progress) => progress.candidates.isNotEmpty)
          .map((progress) => progress.candidates.length)
          .toList();

      expect(visibleCounts, isNot(contains(1)));
      expect(visibleCounts.first, 2);
      expect(visibleCounts.last, 3);
    },
  );

  test('deduplicates escaped identity text across sources and pages', () async {
    final gequhai = _ProviderHarness(MusicDataSource.gequhai);
    final kuwo = _ProviderHarness(MusicDataSource.kuwoFullAudio);
    final coordinator = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    );
    final escaped = _readyCandidate(
      MusicDataSource.gequhai,
      '晴天',
      artist: r'\u5468\u6770\u4f26',
    );
    final decoded = _readyCandidate(
      MusicDataSource.kuwoFullAudio,
      ' 晴 天 ',
      artist: '周杰伦',
    );
    expect(multiSourceCandidateKey(escaped), multiSourceCandidateKey(decoded));

    final firstPage = coordinator.searchPage('周杰伦', page: 1).toList();
    await _flushEvents();
    gequhai
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [escaped],
            isComplete: true,
            page: 1,
            hasNextPage: true,
          ),
        );
    kuwo
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [decoded],
            isComplete: true,
            page: 1,
            hasNextPage: true,
          ),
        );
    await Future.wait([gequhai.close(1), kuwo.close(1)]);
    expect((await firstPage).last.candidates, hasLength(1));

    final secondPage = coordinator.searchPage('周杰伦', page: 2).toList();
    await _flushEvents();
    gequhai
        .controller(2)
        .add(
          MusicSearchProgress(candidates: [decoded], isComplete: true, page: 2),
        );
    kuwo
        .controller(2)
        .add(
          MusicSearchProgress(
            candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '夜曲')],
            isComplete: true,
            page: 2,
          ),
        );
    await Future.wait([gequhai.close(2), kuwo.close(2)]);
    expect((await secondPage).last.candidates.map((item) => item.name), ['夜曲']);
  });

  test('keeps successful results when another source fails', () async {
    final gequhai = _ProviderHarness(MusicDataSource.gequhai);
    final kuwo = _ProviderHarness(MusicDataSource.kuwoFullAudio);
    final future = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    ).searchPage('Angel', page: 1).toList();
    await _flushEvents();

    gequhai
        .controller(1)
        .addError(
          const SourceDownloadException('timeout', failureCode: 'timeout'),
        );
    kuwo
        .controller(1)
        .add(
          MusicSearchProgress(
            candidates: [
              _readyCandidate(MusicDataSource.kuwoFullAudio, 'Angel'),
            ],
            isComplete: true,
            page: 1,
          ),
        );
    await Future.wait([gequhai.close(1), kuwo.close(1)]);

    final result = (await future).last;
    expect(result.candidates.map((item) => item.name), ['Angel']);
    expect(result.error, isNull);
  });

  test('keeps an empty result when only one source fails', () async {
    final gequhai = _ImmediateProvider(
      MusicDataSource.gequhai,
      (_) => Stream.error(StateError('gequhai failed')),
    );
    final kuwo = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (_) => Stream.value(
        const MusicSearchProgress(candidates: [], isComplete: true),
      ),
    );

    final result = (await MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    ).searchPage('冷门查询', page: 1).toList()).last;

    expect(result.candidates, isEmpty);
    expect(result.error, isNull);
  });

  test('opens a source circuit without blocking another source', () async {
    var now = DateTime(2026, 7, 17, 9);
    final logs = <String>[];
    final gequhai = _ImmediateProvider(
      MusicDataSource.gequhai,
      (_) => Stream.error(
        const SourceDownloadException(
          'blocked',
          failureCode: 'provider_http_429',
        ),
      ),
    );
    final kuwo = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (_) => Stream.value(
        MusicSearchProgress(
          candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '晴天')],
          isComplete: true,
          page: 1,
        ),
      ),
    );
    final coordinator = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
      now: () => now,
      logger: logs.add,
    );

    expect(
      (await coordinator.searchPage('晴天', page: 1).toList()).last.error,
      isNull,
    );
    expect(
      (await coordinator.searchPage('夜曲', page: 1).toList())
          .last
          .candidates
          .single
          .name,
      '晴天',
    );
    expect(gequhai.calls, [1]);
    expect(kuwo.calls, [1, 1]);
    expect(
      logs,
      containsAll([
        contains('source_gequhai failure code=provider_http_429'),
        contains('source_gequhai circuit-open'),
        contains('source_gequhai circuit-skip'),
      ]),
    );

    now = now.add(const Duration(minutes: 2, seconds: 1));
    await coordinator.searchPage('稻香', page: 1).toList();
    expect(gequhai.calls, [1, 1]);
  });

  test('opens a source circuit after a network timeout', () async {
    final gequhai = _ImmediateProvider(
      MusicDataSource.gequhai,
      (_) => Stream.error(TimeoutException('connection timed out')),
    );
    final kuwo = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (_) => Stream.value(
        MusicSearchProgress(
          candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '晴天')],
          isComplete: true,
          page: 1,
        ),
      ),
    );
    final coordinator = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    );

    await coordinator.searchPage('周杰伦', page: 1).toList();
    await coordinator.searchPage('王蓉', page: 1).toList();

    expect(gequhai.calls, [1]);
    expect(kuwo.calls, [1, 1]);
  });

  test('opens a source circuit after a socket timeout', () async {
    final gequhai = _ImmediateProvider(
      MusicDataSource.gequhai,
      (_) => Stream.error(const SocketException('Connection timed out')),
    );
    final kuwo = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (_) => Stream.value(
        MusicSearchProgress(
          candidates: [_readyCandidate(MusicDataSource.kuwoFullAudio, '晴天')],
          isComplete: true,
          page: 1,
        ),
      ),
    );
    final coordinator = MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    );

    await coordinator.searchPage('周杰伦', page: 1).toList();
    await coordinator.searchPage('王蓉', page: 1).toList();

    expect(gequhai.calls, [1]);
    expect(kuwo.calls, [1, 1]);
  });

  test('does not request an exhausted source on the next page', () async {
    final exhausted = _ImmediateProvider(
      MusicDataSource.gequhai,
      (page) => Stream.value(
        MusicSearchProgress(
          candidates: [_readyCandidate(MusicDataSource.gequhai, '晴天')],
          isComplete: true,
          page: page,
        ),
      ),
    );
    final paginated = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (page) => Stream.value(
        MusicSearchProgress(
          candidates: [
            _readyCandidate(MusicDataSource.kuwoFullAudio, '歌曲$page'),
          ],
          isComplete: true,
          page: page,
          hasNextPage: page == 1,
        ),
      ),
    );
    final coordinator = MultiSourceSearchCoordinator(
      providers: [exhausted.provider, paginated.provider],
    );

    await coordinator.searchPage('周杰伦', page: 1).toList();
    await coordinator.searchPage('周杰伦', page: 2).toList();

    expect(exhausted.calls, [1]);
    expect(paginated.calls, [1, 2]);
  });

  test('reports structured failure when every source fails', () async {
    final gequhai = _ImmediateProvider(
      MusicDataSource.gequhai,
      (_) => Stream.error(StateError('gequhai failed')),
    );
    final kuwo = _ImmediateProvider(
      MusicDataSource.kuwoFullAudio,
      (_) => Stream.error(StateError('kuwo failed')),
    );

    final result = (await MultiSourceSearchCoordinator(
      providers: [gequhai.provider, kuwo.provider],
    ).searchPage('周杰伦', page: 1).toList()).last;

    expect(result.error, isA<MultiSourceSearchFailure>());
    expect((result.error! as MultiSourceSearchFailure).errors, hasLength(2));
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

MusicSearchCandidate _readyCandidate(
  MusicDataSource source,
  String name, {
  String artist = '周杰伦',
}) {
  return _candidate(
    source,
    name,
    artist: artist,
    raw: const {
      'clientReady': true,
      'urlType': 'direct_audio',
      'canCacheAudio': true,
    },
  );
}

MusicSearchCandidate _candidate(
  MusicDataSource source,
  String name, {
  String artist = '周杰伦',
  Map<String, dynamic> raw = const {},
}) {
  return MusicSearchCandidate(
    query: name,
    source: source,
    platform: source.storageValue,
    keyword: name,
    page: 1,
    id: '${source.storageValue}-$name',
    name: name,
    artist: artist,
    album: '',
    duration: 180,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: 200,
    raw: raw,
  );
}

final class _ProviderHarness {
  _ProviderHarness(this.source);

  final MusicDataSource source;
  final Map<int, StreamController<MusicSearchProgress>> controllers = {};
  final List<int> calls = [];

  StreamController<MusicSearchProgress> controller(int page) =>
      controllers[page] ??= StreamController<MusicSearchProgress>();

  Future<void> close(int page) => controller(page).close();

  MultiSourceSearchProvider get provider => MultiSourceSearchProvider(
    source: source,
    searchPage: (query, {required page}) {
      calls.add(page);
      return controller(page).stream;
    },
  );
}

final class _ImmediateProvider {
  _ImmediateProvider(this.source, this.result);

  final MusicDataSource source;
  final Stream<MusicSearchProgress> Function(int page) result;
  final List<int> calls = [];

  MultiSourceSearchProvider get provider => MultiSourceSearchProvider(
    source: source,
    searchPage: (query, {required page}) {
      calls.add(page);
      return result(page);
    },
  );
}
