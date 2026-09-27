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

  test('artist conflicts are selected with a warning', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '甲'), candidate('稻香', '乙')],
      fallback: (_, _) async => fail('nonempty primary must stop fallback'),
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft);

    expect(match.recommended, isNotNull);
    expect(match.needsReview, isTrue);
    expect(resolver.resolveCount, 0);
  });

  test('unknown artist is selected with a warning', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '周杰伦')],
      fallback: (_, _) async => fail('nonempty primary must stop fallback'),
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft.copyWith(artist: ''));

    expect(match.recommended, isNotNull);
    expect(match.needsReview, isTrue);
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

  test(
    'real OCR typo recalls title fragments and ranks the actual song first',
    () async {
      final queries = <String>[];
      final resolver = _StagedResolver(
        primary: (query) async {
          queries.add(query);
          return query == '风吹'
              ? [
                  candidate('贝加尔湖畔', '李健'),
                  candidate('风吹麦浪 (Live)', '李健'),
                  candidate('风吹麦浪', '李健'),
                ]
              : [];
        },
        fallback: (_, _) async => [],
      );
      final match = await ScreenshotMatcher(
        resolver: resolver,
        wait: (_) async {},
      ).match(draft.copyWith(title: '风吹表浪', artist: '季健'));
      expect(queries, ['风吹表浪', '风吹', '表浪']);
      expect(match.candidates.first.name, '风吹麦浪');
      expect(match.candidates.first.artist, '李健');
      expect(match.recommended, same(match.candidates.first));
      expect(resolver.resolveCount, 0);
    },
  );

  test(
    'same artist wrong song and wrong version are selected with a warning',
    () async {
      for (final wrong in [
        candidate('晴天', '周杰伦'),
        candidate('稻香 (Live)', '周杰伦'),
      ]) {
        final resolver = _StagedResolver(
          primary: (_) async => [wrong],
          fallback: (_, _) async => [],
        );
        final result = await ScreenshotMatcher(
          resolver: resolver,
          wait: (_) async {},
        ).match(draft);
        expect(result.candidates, contains(wrong));
        expect(result.recommended, isNotNull);
        expect(result.needsReview, isTrue);
      }
    },
  );

  test('a correct title beats an unrelated exact artist result', () async {
    final right = candidate('风吹麦浪', '李健');
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('传奇', '季健'), right],
      fallback: (_, _) async => [],
    );
    final result = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft.copyWith(title: '风吹表浪', artist: '季健'));
    expect(result.candidates.first, same(right));
    expect(result.recommended, same(right));
  });

  test(
    'clear single-field OCR corrections are automatically selected',
    () async {
      for (final input in [
        draft.copyWith(title: '青花磁'),
        draft.copyWith(title: '青花瓷', artist: '周杰仑'),
      ]) {
        final right = candidate('青花瓷', '周杰伦');
        final resolver = _StagedResolver(
          primary: (_) async => [candidate('七里香', '周杰伦'), right],
          fallback: (_, _) async => [],
        );
        final match = await ScreenshotMatcher(
          resolver: resolver,
          wait: (_) async {},
        ).match(input);
        expect(match.recommended, same(right));
      }
    },
  );

  test(
    'close alternative song or artist still requires confirmation',
    () async {
      for (final alternatives in [
        [candidate('风吹麦浪', '李健'), candidate('风吹海浪', '李健')],
        [candidate('风吹麦浪', '李健'), candidate('风吹麦浪', '张健')],
      ]) {
        final resolver = _StagedResolver(
          primary: (_) async => alternatives,
          fallback: (_, _) async => [],
        );
        final match = await ScreenshotMatcher(
          resolver: resolver,
          wait: (_) async {},
        ).match(draft.copyWith(title: '风吹表浪', artist: '季健'));
        expect(match.recommended, isNotNull);
        expect(match.needsReview, isTrue);
      }
    },
  );

  test(
    'short title correction is not enough evidence for automatic selection',
    () async {
      final resolver = _StagedResolver(
        primary: (_) async => [candidate('稻香', '周杰伦')],
        fallback: (_, _) async => [],
      );
      final match = await ScreenshotMatcher(
        resolver: resolver,
        wait: (_) async {},
      ).match(draft.copyWith(title: '稻向'));
      expect(match.recommended, isNotNull);
      expect(match.needsReview, isTrue);
    },
  );

  test(
    'multiple sources of one corrected identity do not require confirmation',
    () async {
      final song = candidate('风吹麦浪', '李健');
      final match = await ScreenshotMatcher(
        resolver: _ManyResolver(song),
        wait: (_) async {},
      ).match(draft.copyWith(title: '风吹表浪', artist: '季健'));
      expect(match.recommended, same(song));
    },
  );

  test(
    'real soundtrack annotations match the title and genuine artist',
    () async {
      for (final sample in [
        ('龙猫(《龙猫》)', '贵族乐团', '龙猫-选自《龙猫》'),
        ('萱草花(电影《你好,李焕英》主题曲)', '张小斐', '萱草花-《你好，李焕英》电影主题曲'),
        ('萱草花 (哼唱版) (电影《你好,李煥英..', '张小斐', '萱草花(哼唱版)'),
      ]) {
        final right = candidate(sample.$3, sample.$2);
        final resolver = _StagedResolver(
          primary: (_) async => [candidate('萱草花-电影《你好，李焕英》主题曲', '窦颖'), right],
          fallback: (_, _) async => [],
        );
        final result = await ScreenshotMatcher(
          resolver: resolver,
          wait: (_) async {},
        ).match(draft.copyWith(title: sample.$1, artist: sample.$2));
        expect(result.recommended, same(right));
      }
    },
  );

  test(
    'humming version does not automatically become vocal or a title credit',
    () async {
      final resolver = _StagedResolver(
        primary: (_) async => [
          candidate('萱草花', '张小斐'),
          candidate('萱草花(哼唱版)《你好，李焕英》电影主题曲 - 张小斐', '千与'),
        ],
        fallback: (_, _) async => [],
      );
      final result = await ScreenshotMatcher(
        resolver: resolver,
        wait: (_) async {},
      ).match(draft.copyWith(title: '萱草花 (哼唱版) (电影《你好,李煥英..', artist: '张小斐'));
      expect(result.recommended, isNotNull);
      expect(result.needsReview, isTrue);
    },
  );

  test(
    'soundtrack annotation is removed from the actual search query',
    () async {
      final queries = <String>[];
      final resolver = _StagedResolver(
        primary: (query) async {
          queries.add(query);
          return [candidate('龙猫', '贵族乐团')];
        },
        fallback: (_, _) async => [],
      );
      await ScreenshotMatcher(
        resolver: resolver,
        wait: (_) async {},
      ).match(draft.copyWith(title: '龙猫(《龙猫》)', artist: '贵族乐团'));
      expect(queries, ['龙猫']);
    },
  );

  test(
    'user examples prefer matching artists even when lullaby version is unavailable',
    () async {
      for (final sample in [
        ('幸攝拍手歌(哄睡版)', '贝乐虎し歌', '幸福拍手歌', '贝乐虎儿歌'),
        ('春天在哪里(吹睡版)', 'し歌多多', '春天在哪里', '儿歌多多'),
        ('大风车(哄睡版)', '贝乐虎し歌', '大风车', '贝乐虎儿歌'),
      ]) {
        final right = candidate(sample.$3, sample.$4);
        final resolver = _StagedResolver(
          primary: (_) async => [
            candidate('${sample.$3}(英文版)', '经典双语儿歌'),
            candidate('${sample.$3}（哄睡版）', '红苹果姐姐'),
            right,
          ],
          fallback: (_, _) async => [],
        );
        final result = await ScreenshotMatcher(
          resolver: resolver,
          wait: (_) async {},
        ).match(draft.copyWith(title: sample.$1, artist: sample.$2));
        expect(result.recommended, same(right));
        expect(result.needsReview, isTrue);
      }
    },
  );

  test('exact song and version is selected without a warning', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [candidate('稻香', '周杰伦')],
      fallback: (_, _) async => [],
    );
    final match = await ScreenshotMatcher(
      resolver: resolver,
      wait: (_) async {},
    ).match(draft);
    expect(match.recommended, isNotNull);
    expect(match.needsReview, isFalse);
  });

  test('fallback cache separates same title with different artists', () async {
    final resolver = _StagedResolver(
      primary: (_) async => [],
      fallback: (title, artist) async => [candidate(title, artist)],
    );
    final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});
    expect((await matcher.match(draft)).recommended?.artist, '周杰伦');
    expect(
      (await matcher.match(draft.copyWith(artist: '另一人'))).recommended?.artist,
      '另一人',
    );
    expect(resolver.fallbackCalls, 2);
  });

  test('429 opens a source circuit for later screenshot rows', () async {
    final resolver = _StagedResolver(
      primary: (_) async => throw Exception('buguyy HTTP 429'),
      fallback: (_, _) async => [candidate('稻香', '周杰伦')],
    );
    final matcher = ScreenshotMatcher(resolver: resolver, wait: (_) async {});

    expect((await matcher.match(draft)).recommended, isNotNull);
    expect(
      (await matcher.match(draft.copyWith(title: '晴天'))).needsReview,
      isTrue,
    );
    expect(resolver.primaryCalls, 1);
    expect(resolver.fallbackCalls, 2);
  });

  test('source circuit stops later rows after an overlapping 429', () async {
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
    // An already-started request may overlap the failure; the circuit still
    // blocks subsequent rows once the 429 arrives.
    final callsAfterFailure = resolver.primaryCalls;
    expect(callsAfterFailure, inInclusiveRange(1, 2));
    await matcher.match(draft.copyWith(title: '后来'));
    expect(resolver.primaryCalls, callsAfterFailure);
    expect(resolver.fallbackCalls, 4);
  });

  test('different songs can search the same source concurrently', () async {
    final gate = Completer<void>();
    final resolver = _StagedResolver(
      primary: (title) async {
        await gate.future;
        return [candidate(title, '周杰伦')];
      },
      fallback: (_, _) async => fail('primary results should suffice'),
    );
    final matcher = ScreenshotMatcher(
      resolver: resolver,
      requestStartSpacing: Duration.zero,
    );

    final first = matcher.match(draft);
    final second = matcher.match(draft.copyWith(title: '晴天'));
    await Future<void>.delayed(Duration.zero);
    expect(resolver.primaryCalls, 2);
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results.map((result) => result.recommended?.name), ['稻香', '晴天']);
  });

  test(
    '429 does not block joining an already-running same-title search',
    () async {
      final firstStarted = Completer<void>();
      final firstGate = Completer<void>();
      final resolver = _StagedResolver(
        primary: (title) async {
          if (title == '稻香') {
            firstStarted.complete();
            await firstGate.future;
            return [candidate('稻香', '周杰伦')];
          }
          throw Exception('HTTP 429');
        },
        fallback: (title, _) async => [candidate(title, '备用歌手')],
      );
      final matcher = ScreenshotMatcher(
        resolver: resolver,
        requestStartSpacing: Duration.zero,
      );

      final first = matcher.match(draft);
      await firstStarted.future;
      await matcher.match(draft.copyWith(title: '晴天'));
      final second = matcher.match(draft.copyWith(artist: '周杰伦'));
      firstGate.complete();
      final results = await Future.wait([first, second]);

      expect(results.map((result) => result.recommended?.artist), [
        '周杰伦',
        '周杰伦',
      ]);
      expect(resolver.primaryCalls, 2);
      expect(resolver.fallbackCalls, 1);
    },
  );

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
