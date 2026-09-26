import 'dart:async';

import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const draft = ScreenshotSongDraft(
    imageId: 'image-1',
    row: 0,
    title: '稻香',
    artist: '周杰伦',
    version: '',
    rawText: '稻香 周杰伦',
  );

  MusicSearchCandidate candidate(String title, String artist) =>
      MusicSearchCandidate(
        query: title,
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: title,
        page: 1,
        id: '$title-$artist',
        name: title,
        artist: artist,
        album: '',
        duration: 220,
        link: '',
        coverUrl: '',
        qualities: const [],
        score: 100,
        raw: const {},
      );

  test('same-artist result is selected without resolving audio', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '别的歌手'), candidate('稻香', '周杰伦')],
      fallback: (_, _) async => fail('nonempty primary must stop fallback'),
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft);

    expect(match.candidates, hasLength(2));
    expect(match.recommended?.artist, '周杰伦');
    expect(resolver.primaryCalls, 1);
    expect(resolver.fallbackCalls, 0);
    expect(resolver.resolveCount, 0);
  });

  test('when artist cannot match, select first source result', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '甲'), candidate('稻香', '乙')],
      fallback: (_, _) async => fail('nonempty primary must stop fallback'),
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft);

    expect(match.recommended, same(match.candidates.first));
    expect(resolver.resolveCount, 0);
  });

  test('unknown artist still searches the title and selects first', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '周杰伦')],
      fallback: (_, _) async => fail('nonempty primary must stop fallback'),
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft.copyWith(artist: ''));

    expect(match.recommended, same(match.candidates.first));
    expect(resolver.primaryCalls, 1);
    expect(resolver.resolveCount, 0);
  });

  test('empty primary uses fallback results without probing audio', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [],
      fallback: (_, _) async => [candidate('稻香', '周杰伦')],
    );
    final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

    expect((await matcher.match(draft)).recommended?.name, '稻香');
    await matcher.match(draft);
    expect(resolver.primaryCalls, 2);
    expect(resolver.fallbackCalls, 1);
    expect(resolver.resolveCount, 0);
  });

  test(
    'an empty response is not cached against a later explicit retry',
    () async {
      var calls = 0;
      final resolver = _StagedResolver(
        primary: (_) async {
          calls += 1;
          return calls == 1 ? [] : [candidate('稻香', '周杰伦')];
        },
        fallback: (_, _) async => [],
      );
      final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

      expect((await matcher.match(draft)).recommended, isNull);
      expect((await matcher.match(draft)).recommended?.artist, '周杰伦');
      expect(resolver.primaryCalls, 2);
      expect(resolver.fallbackCalls, 1);
    },
  );

  test('candidate count follows actual response, without a ten cap', () async {
    final matcher = ScreenshotMatcher(
      resolver: _ManyResolver(candidate('稻香', '周杰伦')),
      wait: (_) async {},
    );
    expect((await matcher.match(draft)).candidates, hasLength(12));
  });

  test('429 opens a source circuit for later screenshot rows', () async {
    final resolver = _StagedResolver(
      primary: (_) async => throw Exception('buguyy HTTP 429'),
      fallback: (_, _) async => [candidate('稻香', '周杰伦')],
    );
    final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

    expect((await matcher.match(draft)).recommended, isNotNull);
    expect(
      (await matcher.match(draft.copyWith(title: '晴天'))).recommended,
      isNotNull,
    );
    expect(resolver.primaryCalls, 1);
    expect(resolver.fallbackCalls, 2);
  });

  test('queued rows do not hit a source after its first 429', () async {
    final resolver = _StagedResolver(
      primary: (_) async => throw Exception('HTTP 429'),
      fallback: (_, _) async => [candidate('稻香', '周杰伦')],
    );
    final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

    await Future.wait([
      matcher.match(draft),
      matcher.match(draft.copyWith(title: '晴天')),
      matcher.match(draft.copyWith(title: '外婆')),
    ]);
    expect(resolver.primaryCalls, 1);
    expect(resolver.fallbackCalls, 3);
  });

  test(
    'duplicate titles share one request but choose artists separately',
    () async {
      final gate = Completer<void>();
      final resolver = _StagedResolver(
        primary: (_) async {
          await gate.future;
          return [candidate('稻香', '甲'), candidate('稻香', '周杰伦')];
        },
        fallback: (_, _) async => fail('nonempty primary must stop fallback'),
      );
      final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

      final first = matcher.match(draft);
      final second = matcher.match(draft.copyWith(artist: '甲'));
      await Future<void>.delayed(Duration.zero);
      expect(resolver.primaryCalls, 1);
      gate.complete();
      final results = await Future.wait([first, second]);
      expect(results[0].recommended?.artist, '周杰伦');
      expect(results[1].recommended?.artist, '甲');
      expect(resolver.resolveCount, 0);
    },
  );
}

class _StagedResolver implements MusicResolver, StagedScreenshotSearchResolver {
  _StagedResolver({required this.primary, required this.fallback});

  final Future<List<MusicSearchCandidate>> Function(String) primary;
  final Future<List<MusicSearchCandidate>> Function(String, String) fallback;
  int primaryCalls = 0;
  int fallbackCalls = 0;
  int resolveCount = 0;

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotPrimary(String title) {
    primaryCalls += 1;
    return primary(title);
  }

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotFallback(
    String title,
    String artist,
  ) {
    fallbackCalls += 1;
    return fallback(title, artist);
  }

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) => searchScreenshotPrimary(query);

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    resolveCount += 1;
    throw StateError('screenshot matching must not resolve media');
  }
}

class _ManyResolver implements MusicResolver {
  _ManyResolver(this.song);

  final MusicSearchCandidate song;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => List<MusicSearchCandidate>.filled(12, song);

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw StateError('screenshot matching must not resolve media');
}
