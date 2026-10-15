import 'dart:async';
import 'dart:convert';

import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final query in ['周杰伦 晴天', '晴天 周杰倫', '周杰伦']) {
    test(
      'persisted Jay query keeps YY priority after resolver restart: $query',
      () async {
        final http = _PriorityHttp(
          MusicDataSource.buguyy,
          title: '晴天',
          artist: '周杰伦',
          bothRegular: true,
        );
        final found = await http.resolver().search(query, MusicDataSource.auto);
        expect(found.single.source, MusicDataSource.buguyy);
        final restored = SavedOnlineTrack.fromJson(
          jsonDecode(
            jsonEncode(SavedOnlineTrack(candidate: found.single).toJson()),
          ),
        )!.candidate;
        final cold = _PriorityHttp(
          MusicDataSource.buguyy,
          title: '晴天',
          artist: '周杰伦',
          bothRegular: true,
        );
        final resolved = await cold.resolver().resolveForSourceMode(
          restored,
          MusicDataSource.auto,
        );
        expect(resolved.source, MusicDataSource.buguyy);
        expect(cold.searches, isEmpty);
        expect(cold.resolutions, [MusicDataSource.buguyy]);
      },
    );
  }
  test(
    'cold cached YY failure still falls back to verified same FLAC recording',
    () async {
      final origin = _PriorityHttp(
        MusicDataSource.buguyy,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final found = await origin.resolver().search(
        '周杰伦 晴天',
        MusicDataSource.auto,
      );
      final restored = SavedOnlineTrack.fromJson(
        SavedOnlineTrack(candidate: found.single).toJson(),
      )!.candidate;
      final cold = _PriorityHttp(
        MusicDataSource.buguyy,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      )..failYyResolve = true;
      final resolved = await cold.resolver().resolveForSourceMode(
        restored,
        MusicDataSource.auto,
      );
      expect(resolved.source, MusicDataSource.flac);
      expect(cold.resolutions.first, MusicDataSource.buguyy);
      expect(cold.resolutions.last, MusicDataSource.flac);
      expect(cold.searches.toSet(), {MusicDataSource.flac});
    },
  );
  test(
    'Jay alternative search follows query priority after restoring cache',
    () async {
      final origin = _PriorityHttp(
        MusicDataSource.twentyFourBit,
        title: '晴天',
        artist: '周杰伦',
      );
      final found = await origin.resolver().search(
        '周杰伦 晴天',
        MusicDataSource.auto,
      );
      final restored = SavedOnlineTrack.fromJson(
        SavedOnlineTrack(candidate: found.single).toJson(),
      )!.candidate;
      final cold = _PriorityHttp(
        MusicDataSource.buguyy,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final resolved = await cold.resolver().resolveAlternative(
        restored,
        excludedSources: {MusicDataSource.twentyFourBit},
      );
      expect(resolved.source, MusicDataSource.buguyy);
      expect(cold.searches, [MusicDataSource.buguyy]);
      expect(cold.resolutions, [MusicDataSource.buguyy]);
    },
  );
  for (final mode in [MusicDataSource.buguyy, MusicDataSource.flac]) {
    test('manual cached Jay $mode is not reordered', () async {
      final origin = _PriorityHttp(
        mode,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final found = await origin.resolver().search('周杰伦 晴天', mode);
      final restored = SavedOnlineTrack.fromJson(
        SavedOnlineTrack(candidate: found.single).toJson(),
      )!.candidate;
      final cold = _PriorityHttp(
        mode,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final resolved = await cold.resolver().resolveForSourceMode(
        restored,
        mode,
      );
      expect(resolved.source, mode);
      expect(cold.searches, isEmpty);
      expect(cold.resolutions, [mode]);
    });
  }
  test(
    'cold Jay cache respects unavailable YY and falls back to FLAC',
    () async {
      final origin = _PriorityHttp(
        MusicDataSource.buguyy,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final found = await origin.resolver().search(
        '周杰伦 晴天',
        MusicDataSource.auto,
      );
      final restored = SavedOnlineTrack.fromJson(
        SavedOnlineTrack(candidate: found.single).toJson(),
      )!.candidate;
      final cold = _PriorityHttp(
        MusicDataSource.buguyy,
        title: '晴天',
        artist: '周杰伦',
        bothRegular: true,
      );
      final resolver = cold.resolver();
      for (var i = 0; i < 3; i++) {
        resolver.reportSourceFailure(
          MusicDataSource.buguyy,
          StateError('HTTP 503'),
        );
      }
      final resolved = await resolver.resolveForSourceMode(
        restored,
        MusicDataSource.auto,
      );
      expect(resolved.source, MusicDataSource.flac);
      expect(cold.searches.toSet(), {MusicDataSource.flac});
      expect(cold.resolutions, [MusicDataSource.flac]);
    },
  );
  for (final progressive in [false, true]) {
    for (final preferred in [
      MusicDataSource.flac,
      MusicDataSource.buguyy,
      MusicDataSource.twentyFourBit,
    ]) {
      test('Auto stops at $preferred progressive=$progressive', () async {
        final http = _PriorityHttp(preferred);
        final resolver = http.resolver();
        final found = progressive
            ? (await resolver
                      .searchProgressively('江南 林俊杰', MusicDataSource.auto)
                      .toList())
                  .last
                  .candidates
            : await resolver.search('江南 林俊杰', MusicDataSource.auto);
        expect(found, isNotEmpty);
        expect(found.every((c) => c.source == preferred), isTrue);
        final stages = http.searches.toSet().toList();
        expect(stages, [
          MusicDataSource.flac,
          if (preferred != MusicDataSource.flac) MusicDataSource.buguyy,
          if (preferred == MusicDataSource.twentyFourBit)
            MusicDataSource.twentyFourBit,
        ]);
      });
    }
  }

  test(
    'usable FLAC batch survives another platform failure without fallback',
    () async {
      final http = _PriorityHttp(MusicDataSource.flac)..failWyy = true;
      final results = await http
          .resolver(platforms: ['kuwo', 'wyy'])
          .searchProgressively('江南 林俊杰', MusicDataSource.auto)
          .toList();
      expect(results.last.isComplete, isTrue);
      expect(results.last.error, isNull);
      expect(results.last.candidates.single.source, MusicDataSource.flac);
      expect(http.searches.toSet(), {MusicDataSource.flac});
    },
  );

  test(
    'waiting FLAC query does not launch YY or 24bit and cancellation stops fallback',
    () async {
      final http = _PriorityHttp(MusicDataSource.twentyFourBit)
        ..flacGate = Completer<void>();
      final resolver = http.resolver();
      var cancelled = false;
      final operation = resolver
          .searchWithCancellation(
            '江南 林俊杰',
            MusicDataSource.auto,
            isCancelled: () => cancelled,
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      expect(http.searches.toSet(), {MusicDataSource.flac});
      cancelled = true;
      http.flacGate!.complete();
      expect(await operation, isEmpty);
      expect(http.searches.toSet(), {MusicDataSource.flac});
    },
  );

  for (final savedSource in [
    MusicDataSource.buguyy,
    MusicDataSource.twentyFourBit,
  ]) {
    test(
      'old $savedSource candidate checks FLAC before network resolution',
      () async {
        final http = _PriorityHttp(MusicDataSource.flac);
        final resolver = http.resolver();
        final legacy = _candidate(savedSource);
        final resolved = await resolver.resolveForSourceMode(
          legacy,
          MusicDataSource.auto,
        );
        expect(resolved.source, MusicDataSource.flac);
        expect(http.resolutions, [MusicDataSource.flac]);
        expect(http.searches.toSet(), {MusicDataSource.flac});
      },
    );
  }

  test(
    'current Auto fallback resolves without repeating earlier failed searches',
    () async {
      final http = _PriorityHttp(MusicDataSource.twentyFourBit);
      final resolver = http.resolver();
      final found = await resolver.search('江南 林俊杰', MusicDataSource.auto);
      final previous = List.of(http.searches);
      final resolved = await resolver.resolveForSourceMode(
        found.first,
        MusicDataSource.auto,
      );
      expect(resolved.source, MusicDataSource.twentyFourBit);
      expect(http.searches, previous);
      expect(http.resolutions, [MusicDataSource.twentyFourBit]);
    },
  );

  test(
    'playlist lookup uses FLAC first without touching limited provider',
    () async {
      final http = _PriorityHttp(MusicDataSource.flac);
      final found = await http.resolver().searchScreenshot('江南', '林俊杰');
      expect(found.first.source, MusicDataSource.flac);
      expect(http.searches, [MusicDataSource.flac]);
    },
  );

  test('unavailable YY does not suppress FLAC screenshot matching', () async {
    final http = _PriorityHttp(MusicDataSource.flac);
    final resolver = http.resolver();
    for (var i = 0; i < 3; i++) {
      resolver.reportSourceFailure(
        MusicDataSource.buguyy,
        StateError('HTTP 503'),
      );
    }
    final matched = await ScreenshotMatcher(resolver: resolver).match(
      const ScreenshotSongDraft(
        imageId: 'priority',
        row: 0,
        title: '江南',
        artist: '林俊杰',
        version: '',
        rawText: '江南 林俊杰',
      ),
    );
    expect(matched.candidates.single.source, MusicDataSource.flac);
    expect(http.searches, [MusicDataSource.flac]);
  });

  test(
    'quota status is based on song response and rechecked without audio transfer',
    () async {
      final http = _PriorityHttp(MusicDataSource.twentyFourBit)
        ..quotaPage = true;
      final resolver = http.resolver();
      expect(
        resolver.sourceAvailability(MusicDataSource.twentyFourBit),
        MusicSourceAvailability.unknown,
      );
      await expectLater(
        resolver.resolve(_candidate(MusicDataSource.twentyFourBit)),
        throwsA(isA<SourceAccessException>()),
      );
      expect(
        resolver.sourceAvailability(MusicDataSource.twentyFourBit),
        MusicSourceAvailability.quotaExhausted,
      );
      expect(
        resolver.availableAutoSources,
        isNot(contains(MusicDataSource.twentyFourBit)),
      );
      await resolver.recheckSourceAvailability(networkChanged: true);
      expect(
        resolver.sourceAvailability(MusicDataSource.twentyFourBit),
        MusicSourceAvailability.quotaExhausted,
      );
      http.quotaPage = false;
      await resolver.recheckSourceAvailability(networkChanged: true);
      expect(
        resolver.sourceAvailability(MusicDataSource.twentyFourBit),
        MusicSourceAvailability.available,
      );
      expect(resolver.availableAutoSources.last, MusicDataSource.twentyFourBit);
      expect(http.resolutions, List.filled(3, MusicDataSource.twentyFourBit));
      await resolver.recheckSourceAvailability();
      expect(http.resolutions.length, 3);
    },
  );

  test(
    'legacy 24bit pin is released while song identity and source are retained',
    () {
      final saved = SavedOnlineTrack(
        candidate: _candidate(MusicDataSource.twentyFourBit),
      );
      final now = DateTime(2026, 10, 11);
      final entry = PlaylistTrackEntry.fromJson(
        PlaylistTrackEntry(
          trackId: saved.trackId,
          addedAt: now,
          onlineTrack: saved,
          manualSource: true,
        ).toJson(),
        now,
      )!;
      expect(entry.trackId, saved.trackId);
      expect(
        entry.onlineTrack!.candidate.source,
        MusicDataSource.twentyFourBit,
      );
      expect(entry.manualSource, isFalse);
    },
  );
}

const _id = '943e5cfd3555f45f5847010ebb501086';
MusicSearchCandidate _candidate(MusicDataSource source) => MusicSearchCandidate(
  query: '江南 林俊杰',
  source: source,
  platform: source == MusicDataSource.twentyFourBit
      ? '24bit'
      : source.storageValue,
  keyword: '江南',
  page: 1,
  id: source == MusicDataSource.twentyFourBit ? 'b:$_id' : 'song',
  name: '江南',
  artist: '林俊杰',
  album: '叶惠美',
  duration: 269,
  link: '',
  coverUrl: '',
  qualities: const [MusicQuality(format: 'mp3', bitrate: '320')],
  score: 210,
  raw: const {},
);

class _PriorityHttp implements MusicResolverHttp {
  _PriorityHttp(
    this.preferred, {
    this.title = '江南',
    this.artist = '林俊杰',
    this.bothRegular = false,
  });
  final String title, artist;
  final bool bothRegular;
  bool failYyResolve = false;
  final MusicDataSource preferred;
  final searches = <MusicDataSource>[];
  final resolutions = <MusicDataSource>[];
  Completer<void>? flacGate;
  bool failWyy = false;
  bool quotaPage = false;
  RemoteMusicResolver resolver({List<String> platforms = const ['kuwo']}) =>
      RemoteMusicResolver(
        httpClient: this,
        initialFlacCookie: 'ready',
        pages: 1,
        platforms: platforms,
      );
  ResolverHttpResponse json(Uri uri, Object body) => ResolverHttpResponse(
    statusCode: 200,
    body: jsonEncode(body),
    finalUrl: uri,
  );
  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    if (uri.queryParameters['act'] == 'getUrl') {
      resolutions.add(MusicDataSource.flac);
      return json(uri, {
        'data': {'url': 'https://audio.test/song.mp3'},
      });
    }
    searches.add(MusicDataSource.flac);
    await flacGate?.future;
    if (failWyy && form['platform'] == 'wyy') {
      await Future<void>.delayed(Duration.zero);
      throw StateError('HTTP 503');
    }
    return json(uri, {
      'data': {
        'list': [
          if (bothRegular || preferred == MusicDataSource.flac)
            {
              'id': 'flac-song',
              'name': title,
              'artist': artist,
              'minfo': [
                {'format': 'mp3', 'bitrate': '320'},
              ],
            },
        ],
      },
    });
  }

  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (uri.host == 'www.24bit.net') {
      resolutions.add(MusicDataSource.twentyFourBit);
      if (quotaPage) {
        return ResolverHttpResponse(
          statusCode: 200,
          finalUrl: uri,
          body: '今日访问已达限额，可明日再来',
        );
      }
      return ResolverHttpResponse(
        statusCode: 200,
        finalUrl: uri,
        body:
            '<script>self.__next_f.push(${jsonEncode([
              1,
              'a:${jsonEncode({
                'itemMusic': {'id': _id, 'name': title, 'player': artist, 'album': '叶惠美', 'url': 'https://audio.test/song.flac', 'format': 'flac'},
              })}\n',
            ])})</script>',
      );
    }
    if (uri.path == '/api/geturl') {
      resolutions.add(MusicDataSource.buguyy);
      if (failYyResolve) throw StateError('HTTP 503');
      return json(uri, {'success': true, 'url': 'https://audio.test/song.mp3'});
    }
    searches.add(MusicDataSource.buguyy);
    return json(uri, {
      'data': [
        if (bothRegular || preferred == MusicDataSource.buguyy)
          {'id': 'yy-song', 'title': title, 'singer': artist},
      ],
    });
  }

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    searches.add(MusicDataSource.twentyFourBit);
    return json(uri, {
      'status': true,
      'result': [
        {'id': _id, 'name': title, 'player': artist, 'album': '叶惠美'},
      ],
    });
  }
}
