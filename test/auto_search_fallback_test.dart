import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/auto_search_policy.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/provider_request_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Jay priority respects filtered sources and keeps limited fallback last',
    () {
      final policy = AutoSearchPolicy(
        '周杰倫/费玉清 千里之外',
        catalog: MusicSourceCatalog.standard,
      );
      expect(
        policy.orderSources([
          MusicDataSource.flac,
          MusicDataSource.buguyy,
          MusicDataSource.twentyFourBit,
        ]),
        [
          MusicDataSource.buguyy,
          MusicDataSource.flac,
          MusicDataSource.twentyFourBit,
        ],
      );
      expect(
        policy.orderSources([
          MusicDataSource.flac,
          MusicDataSource.twentyFourBit,
        ]),
        [MusicDataSource.flac, MusicDataSource.twentyFourBit],
      );
    },
  );
  test('Jay weak regular sources reach limited fallback in order', () async {
    final http = _SearchHttp(
      flacTitle: '晴天',
      flacArtist: '其他歌手',
      yyTitle: '晴天',
      yyArtist: '其他歌手',
      limitedTitle: '晴天',
      limitedArtist: '周杰伦',
    );
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'ready',
      pages: 1,
      platforms: ['kuwo'],
    );
    final found = await resolver.search('周杰伦 晴天', MusicDataSource.auto);
    expect(http.stages, [
      MusicDataSource.buguyy,
      MusicDataSource.flac,
      MusicDataSource.twentyFourBit,
    ]);
    expect(found.first.source, MusicDataSource.twentyFourBit);
  });
  for (final progressive in [false, true]) {
    for (final query in ['周杰伦 晴天', '晴天 周杰倫', '周杰伦 / 晴天']) {
      test(
        'Jay queries start YY and stop on a strong pair: $query progressive=$progressive',
        () async {
          final http = _SearchHttp(
            flacTitle: '晴天',
            flacArtist: '其他歌手',
            yyTitle: '晴天',
            yyArtist: '周杰伦',
          );
          final resolver = RemoteMusicResolver(
            httpClient: http,
            initialFlacCookie: 'ready',
            pages: 1,
            platforms: ['kuwo'],
          );
          final found = progressive
              ? (await resolver
                        .searchProgressively(query, MusicDataSource.auto)
                        .toList())
                    .last
                    .candidates
              : await resolver.search(query, MusicDataSource.auto);
          expect(http.calls, [MusicDataSource.buguyy]);
          expect(found.single.source, MusicDataSource.buguyy);
        },
      );
    }
    for (final failure in ['weak', 'empty', 'failure']) {
      test(
        'Jay YY $failure falls back to FLAC progressive=$progressive',
        () async {
          final http = _SearchHttp(
            flacTitle: '晴天',
            flacArtist: '周杰伦',
            yyTitle: '晴天',
            yyArtist: '其他歌手',
            yyFails: failure == 'failure',
            yyEmpty: failure == 'empty',
          );
          final resolver = RemoteMusicResolver(
            httpClient: http,
            initialFlacCookie: 'ready',
            pages: 1,
            platforms: ['kuwo'],
          );
          final found = progressive
              ? (await resolver
                        .searchProgressively('周杰伦 晴天', MusicDataSource.auto)
                        .toList())
                    .last
                    .candidates
              : await resolver.search('周杰伦 晴天', MusicDataSource.auto);
          expect(http.calls.first, MusicDataSource.buguyy);
          expect(http.calls.last, MusicDataSource.flac);
          expect(found.first.artist, '周杰伦');
          expect(found.first.source, MusicDataSource.flac);
          expect(http.limitedCalls, 0);
        },
      );
    }
  }
  test(
    'Jay single keyword supplements FLAC and keeps YY for the same recording',
    () async {
      final http = _SearchHttp(
        flacTitle: '晴天',
        flacArtist: '周杰伦',
        yyTitle: '晴天',
        yyArtist: '周杰伦',
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      final found = await resolver.search('周杰伦', MusicDataSource.auto);
      expect(http.calls, [MusicDataSource.buguyy, MusicDataSource.flac]);
      expect(found.single.source, MusicDataSource.buguyy);
    },
  );
  test(
    'Jay cancellation after YY batch prevents FLAC and limited fallback',
    () async {
      var cancelled = false;
      final http = _SearchHttp(
        flacTitle: '晴天',
        flacArtist: '周杰伦',
        yyTitle: '晴天',
        yyArtist: '周杰伦',
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      await resolver
          .searchWithCancellation(
            '周杰伦',
            MusicDataSource.auto,
            isCancelled: () => cancelled,
          )
          .forEach((e) {
            if (e.candidates.isNotEmpty) cancelled = true;
          });
      expect(http.calls, [MusicDataSource.buguyy]);
    },
  );
  test('Jay manual FLAC selection remains a single source', () async {
    final http = _SearchHttp(flacTitle: '晴天', flacArtist: '周杰伦');
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'ready',
      pages: 1,
      platforms: ['kuwo'],
    );
    await resolver.search('周杰伦 晴天', MusicDataSource.flac);
    expect(http.calls, [MusicDataSource.flac]);
  });
  for (final query in ['小周杰伦', '我不是周杰伦', '再次寻找周杰伦', '晴天', '林俊杰 江南']) {
    test('No artist substring inference for $query', () async {
      final http = _SearchHttp(flacTitle: query, flacArtist: '林俊杰');
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      await resolver.search(query, MusicDataSource.auto);
      expect(http.calls.first, MusicDataSource.flac);
    });
  }

  for (final progressive in [false, true]) {
    for (final scenario in [
      (
        name: 'single weak artist',
        query: '林俊杰',
        flacTitle: '如果我是林俊杰',
        flacArtist: '其他歌手',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: true,
      ),
      (
        name: 'single strong artist still supplements',
        query: '林俊杰',
        flacTitle: '曹操',
        flacArtist: '林俊杰',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: true,
      ),
      (
        name: 'pair wrong artist',
        query: '林俊杰 江南',
        flacTitle: '江南',
        flacArtist: '其他歌手',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: true,
      ),
      (
        name: 'pair wrong title',
        query: '林俊杰 江南',
        flacTitle: '曹操',
        flacArtist: '林俊杰',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: true,
      ),
      (
        name: 'pair strong stops',
        query: '林俊杰 江南',
        flacTitle: '江南',
        flacArtist: '林俊杰',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: false,
      ),
      (
        name: 'pair live is not original',
        query: '林俊杰 江南',
        flacTitle: '江南 (Live)',
        flacArtist: '林俊杰',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yy: true,
      ),
      (
        name: 'ambiguous English title',
        query: 'Love Story',
        flacTitle: 'Love Story',
        flacArtist: 'Taylor Swift',
        yyTitle: 'Love Story',
        yyArtist: 'Taylor Swift',
        yy: true,
      ),
    ]) {
      test(
        'auto confidence ${scenario.name} progressive=$progressive',
        () async {
          final http = _SearchHttp(
            flacTitle: scenario.flacTitle,
            flacArtist: scenario.flacArtist,
            yyTitle: scenario.yyTitle,
            yyArtist: scenario.yyArtist,
          );
          final resolver = RemoteMusicResolver(
            httpClient: http,
            initialFlacCookie: 'ready',
            pages: 1,
            platforms: ['kuwo'],
          );
          final found = progressive
              ? (await resolver
                        .searchProgressively(
                          scenario.query,
                          MusicDataSource.auto,
                        )
                        .toList())
                    .last
                    .candidates
              : await resolver.search(scenario.query, MusicDataSource.auto);
          expect(http.yyCalls > 0, scenario.yy);
          expect(
            http.limitedCalls,
            0,
            reason:
                'Reliable regular results must not consume the limited source',
          );
          expect(
            found.any((c) => c.source == MusicDataSource.flac),
            isTrue,
            reason: 'Supplementing another source must retain FLAC results',
          );
          if (scenario.yy && scenario.flacArtist == '其他歌手' ||
              scenario.name == 'pair wrong title' ||
              scenario.name == 'pair live is not original') {
            expect(found.first.source, MusicDataSource.buguyy);
            expect(found.first.artist, '林俊杰');
          }
          if (scenario.name == 'single strong artist still supplements') {
            expect(found.map((c) => c.name), containsAll(['曹操', '江南']));
          }
          if (scenario.name == 'ambiguous English title') {
            expect(
              found,
              hasLength(1),
              reason: 'Confirmed same recording is merged',
            );
          }
        },
      );
    }
  }

  test(
    'auto emits FLAC while YY is pending and preserves both after it returns',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final http = _SearchHttp(
        flacTitle: '曹操',
        flacArtist: '林俊杰',
        yyTitle: '江南',
        yyArtist: '林俊杰',
        yyGate: gate.future,
        yyStarted: started,
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      final events = <MusicSearchProgress>[];
      final done = resolver
          .searchProgressively('林俊杰', MusicDataSource.auto)
          .forEach(events.add);
      await started.future.timeout(const Duration(seconds: 2));
      expect(
        events.any(
          (e) => !e.isComplete && e.candidates.any((c) => c.name == '曹操'),
        ),
        isTrue,
      );
      gate.complete();
      await done;
      expect(events.last.isComplete, isTrue);
      expect(
        events.last.candidates.map((c) => c.name),
        containsAll(['曹操', '江南']),
      );
    },
  );

  test(
    'auto retains reliable FLAC when YY fails without spending limited quota',
    () async {
      final http = _SearchHttp(
        flacTitle: '曹操',
        flacArtist: '林俊杰',
        yyFails: true,
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      expect(
        (await resolver.search('林俊杰', MusicDataSource.auto)).single.name,
        '曹操',
      );
      expect(http.yyCalls, 1);
      expect(http.limitedCalls, 0);
    },
  );

  test(
    'auto tries limited fallback only after both regular sources are weak',
    () async {
      final http = _SearchHttp(
        flacTitle: '曹操',
        flacArtist: '其他歌手',
        yyTitle: '江南',
        yyArtist: '其他歌手',
        limitedTitle: '江南',
        limitedArtist: '林俊杰',
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      final found = await resolver.search('林俊杰 江南', MusicDataSource.auto);
      expect(http.yyCalls, greaterThan(0));
      expect(http.limitedCalls, greaterThan(0));
      expect(found.first.source, MusicDataSource.twentyFourBit);
    },
  );

  test(
    'auto cancellation after first batch prevents YY and limited requests',
    () async {
      var cancelled = false;
      final http = _SearchHttp(flacTitle: '曹操', flacArtist: '林俊杰');
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      await resolver
          .searchWithCancellation(
            '林俊杰',
            MusicDataSource.auto,
            isCancelled: () => cancelled,
          )
          .forEach((e) {
            if (e.candidates.isNotEmpty) cancelled = true;
          });
      expect(http.yyCalls, 0);
      expect(http.limitedCalls, 0);
    },
  );

  test(
    'future auto search preserves inherited cancellation without recursion',
    () async {
      var cancelled = false;
      final http = _SearchHttp(
        flacTitle: '曹操',
        flacArtist: '林俊杰',
        afterFlac: () => cancelled = true,
      );
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: ['kuwo'],
      );
      await expectLater(
        runZoned(
          () => resolver.search('林俊杰', MusicDataSource.auto),
          zoneValues: {providerCancellationKey: () => cancelled},
        ),
        throwsStateError,
      );
      expect(http.yyCalls, 0);
      expect(http.limitedCalls, 0);
    },
  );

  test('manual FLAC never supplements YY', () async {
    final http = _SearchHttp(flacTitle: '曹操', flacArtist: '林俊杰');
    final resolver = RemoteMusicResolver(
      httpClient: http,
      initialFlacCookie: 'ready',
      pages: 1,
      platforms: ['kuwo'],
    );
    expect(await resolver.search('林俊杰', MusicDataSource.flac), isNotEmpty);
    expect(http.yyCalls, 0);
    expect(http.limitedCalls, 0);
  });

  test('search confidence excludes credits and accepts real duet singers', () {
    final policy = AutoSearchPolicy(
      '林俊杰 江南',
      catalog: MusicSourceCatalog.standard,
    );
    expect(policy.canStopEarly([_candidate('江南（原唱：林俊杰）', '其他歌手')]), isFalse);
    expect(policy.canStopEarly([_candidate('江南', '林俊杰/费玉清')]), isTrue);
    expect(policy.canStopEarly([_candidate('江南', '林俊傑')]), isTrue);
    expect(
      AutoSearchPolicy(
        '林俊杰 江南 Live',
        catalog: MusicSourceCatalog.standard,
      ).canStopEarly([_candidate('江南 (Live)', '林俊杰')]),
      isTrue,
    );
  });

  test('specified live year or venue cannot match another performance', () {
    for (final detail in ['2004', 'In Paris']) {
      final policy = AutoSearchPolicy(
        '林俊杰 江南 (Live $detail)',
        catalog: MusicSourceCatalog.standard,
      );
      final wrong = _candidate('江南 (Live 2007)', '林俊杰');
      final correct = _candidate(
        '江南 (Live $detail)',
        '林俊杰',
        source: MusicDataSource.buguyy,
      );
      expect(policy.canStopEarly([wrong]), isFalse);
      expect(policy.hasStrongMatch([wrong]), isFalse);
      expect(policy.canStopEarly([correct]), isTrue);
      expect(
        policy.rank([wrong, correct]).first.source,
        MusicDataSource.buguyy,
      );
    }
    expect(
      AutoSearchPolicy(
        '林俊杰 江南 现场版',
        catalog: MusicSourceCatalog.standard,
      ).canStopEarly([_candidate('江南 (Live)', '林俊杰')]),
      isTrue,
    );
  });

  test(
    'recording merge retains distinct performance names and missing artists',
    () {
      final policy = AutoSearchPolicy(
        '江南',
        catalog: MusicSourceCatalog.standard,
      );
      expect(
        policy.rank([
          _candidate('江南 (Live 2004)', '林俊杰'),
          _candidate('江南 (Live 2007)', '林俊杰', source: MusicDataSource.buguyy),
        ]),
        hasLength(2),
      );
      expect(
        policy.rank([
          _candidate('江南', ''),
          _candidate('江南', '林俊杰', source: MusicDataSource.buguyy),
        ]),
        hasLength(2),
      );
    },
  );
}

MusicSearchCandidate _candidate(
  String name,
  String artist, {
  MusicDataSource source = MusicDataSource.flac,
}) => MusicSearchCandidate(
  query: '',
  source: source,
  platform: source.storageValue,
  keyword: '',
  page: 1,
  id: '$name-$artist',
  name: name,
  artist: artist,
  album: '',
  duration: 0,
  link: '',
  coverUrl: '',
  qualities: const [],
  score: 0,
  raw: const {},
);

class _SearchHttp implements MusicResolverHttp {
  _SearchHttp({
    required this.flacTitle,
    required this.flacArtist,
    this.yyTitle = '江南',
    this.yyArtist = '林俊杰',
    this.yyFails = false,
    this.yyEmpty = false,
    this.yyGate,
    this.yyStarted,
    this.afterFlac,
    this.limitedTitle,
    this.limitedArtist,
  });
  final String flacTitle, flacArtist, yyTitle, yyArtist;
  final String? limitedTitle, limitedArtist;
  final bool yyFails, yyEmpty;
  final Future<void>? yyGate;
  final Completer<void>? yyStarted;
  final void Function()? afterFlac;
  int yyCalls = 0, limitedCalls = 0;
  final calls = <MusicDataSource>[];
  List<MusicDataSource> get stages => [
    for (var i = 0; i < calls.length; i++)
      if (i == 0 || calls[i] != calls[i - 1]) calls[i],
  ];
  ResolverHttpResponse _json(Uri uri, Object body) => ResolverHttpResponse(
    statusCode: 200,
    body: jsonEncode(body),
    finalUrl: uri,
  );
  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    yyCalls++;
    calls.add(MusicDataSource.buguyy);
    if (yyStarted != null && !yyStarted!.isCompleted) yyStarted!.complete();
    await yyGate;
    if (yyFails) throw const HttpException('HTTP 503');
    return _json(uri, {
      'data': [
        if (!yyEmpty) {'id': 'yy', 'title': yyTitle, 'singer': yyArtist},
      ],
    });
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    calls.add(MusicDataSource.flac);
    afterFlac?.call();
    return _json(uri, {
      'data': {
        'list': [
          {
            'id': 'flac',
            'name': flacTitle,
            'artist': flacArtist,
            'duration': 240,
            'minfo': [
              {'format': 'flac', 'bitrate': '900'},
            ],
          },
        ],
      },
    });
  }

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    limitedCalls++;
    calls.add(MusicDataSource.twentyFourBit);
    return _json(uri, {
      'status': true,
      'result': [
        if (limitedTitle != null)
          {
            'id': '0123456789abcdef0123456789abcdef',
            'name': limitedTitle,
            'player': limitedArtist,
          },
      ],
    });
  }
}
