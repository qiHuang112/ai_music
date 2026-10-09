import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matcher = ScreenshotMatcher(
    resolver: _Resolver(),
    allowTitleFragments: false,
  );

  test(
    'all duet artists match regardless of provider order and separators',
    () {
      final right = _candidate('罗生门', '刘至佳 & 谢宇伦');
      final result = matcher.rankCached(_draft('罗生门', '谢宇伦 / 刘至佳'), [
        _candidate('罗生门', '刘至佳'),
        right,
      ]);
      expect(result.recommended, same(right));
      expect(result.needsReview, isFalse);
    },
  );

  test('Live accompaniment is not the requested Live vocal recording', () {
    final right = _candidate('稻香 (Live)', '周杰伦');
    final result = matcher.rankCached(_draft('稻香 (Live)', '周杰伦'), [
      _candidate('稻香 (Live 伴奏)', '周杰伦'),
      right,
    ]);
    expect(result.recommended, same(right));
  });

  test('DJ is an explicit version and plain audio requires review', () {
    final result = matcher.rankCached(_draft('稻香', '周杰伦'), [
      _candidate('稻香 (DJ版)', '周杰伦'),
    ]);
    expect(result.recommended, isNotNull);
    expect(result.needsReview, isTrue);
    final dj = matcher.rankCached(_draft('稻香 (DJ版)', '周杰伦'), [
      _candidate('稻香', '周杰伦'),
    ]);
    expect(dj.needsReview, isTrue);
  });

  test('traditional metadata matches simplified title and actual singer', () {
    final right = _candidate('后来', '刘若英');
    final result = matcher.rankCached(_draft('後來', '劉若英'), [
      _candidate('后来', '别的歌手'),
      right,
    ]);
    expect(result.recommended, same(right));
    expect(result.needsReview, isFalse);
  });

  test(
    'online metadata does not silently receive OCR character correction',
    () {
      final result = matcher.rankCached(_draft('青花磁', '周杰伦'), [
        _candidate('青花瓷', '周杰伦'),
      ]);
      expect(result.recommended, isNotNull);
      expect(result.needsReview, isTrue);
    },
  );

  test('unknown song keeps upstream first fallback and warns', () {
    final first = _candidate('七里香', '周杰伦');
    final result = matcher.rankCached(_draft('凡人百事书', '张天一'), [
      first,
      _candidate('凡人', '段奥娟'),
    ]);
    expect(result.recommended, same(first));
    expect(result.needsReview, isTrue);
  });

  test(
    'online Auto requests full title and artist from combined search',
    () async {
      final right = _candidate('稻香', '周杰伦');
      final resolver = _Resolver(
        primary: [_candidate('稻香', '别的歌手')],
        fallback: [right],
      );
      final result = await ScreenshotMatcher(
        resolver: resolver,
        allowTitleFragments: false,
        requestStartSpacing: Duration.zero,
      ).match(_draft('稻香', '周杰伦'));
      expect(result.recommended, same(right));
      expect(result.needsReview, isFalse);
      expect(resolver.searches, [(MusicDataSource.auto, '周杰伦 稻香')]);
      expect(resolver.fallbackCalls, 0);
    },
  );

  test('Alive in a title is not a Live version marker', () {
    const policy = ScreenshotMatchPolicy();
    final match = policy.resolvedStillMatches(
      _draft('Alive', 'Sia'),
      const ResolvedMusic(
        query: 'Alive',
        source: MusicDataSource.flac,
        platform: 'kuwo',
        id: 'live',
        name: 'Alive (Live)',
        artist: 'Sia',
        album: '',
        url: 'https://example.test/live.mp3',
        quality: MusicQuality(format: 'mp3'),
      ),
    );
    expect(match, isFalse);
  });

  test('explicit source bypasses staged auto matching', () async {
    final resolver = _Resolver(primary: [_candidate('稻香', '周杰伦')]);
    final matcher = ScreenshotMatcher(
      resolver: resolver,
      source: MusicDataSource.flac,
      allowTitleFragments: false,
      requestStartSpacing: Duration.zero,
    );
    await matcher.match(_draft('稻香', '周杰伦'));
    expect(resolver.searches, [(MusicDataSource.flac, '周杰伦 稻香')]);
    expect(resolver.primaryCalls, 0);
    expect(resolver.fallbackCalls, 0);
  });

  test(
    'existing matcher follows settings and caches each source separately',
    () async {
      var source = MusicDataSource.flac;
      final resolver = _Resolver(primary: [_candidate('稻香', '周杰伦')]);
      final matcher = ScreenshotMatcher(
        resolver: resolver,
        sourceProvider: () => source,
        requestStartSpacing: Duration.zero,
      );
      await matcher.match(_draft('稻香', '周杰伦'));
      source = MusicDataSource.buguyy;
      await matcher.match(_draft('稻香', '周杰伦'));
      source = MusicDataSource.flac;
      await matcher.match(_draft('稻香', '周杰伦'));
      expect(resolver.searches, [
        (MusicDataSource.flac, '稻香'),
        (MusicDataSource.buguyy, '稻香'),
      ]);
      expect(resolver.primaryCalls, 0);
    },
  );

  test('one match captures its selected source once', () async {
    var reads = 0;
    final resolver = _Resolver(primary: [_candidate('稻香', '周杰伦')]);
    final matcher = ScreenshotMatcher(
      resolver: resolver,
      sourceProvider: () =>
          ++reads == 1 ? MusicDataSource.flac : MusicDataSource.buguyy,
      requestStartSpacing: Duration.zero,
    );
    await matcher.match(_draft('稻香', '周杰伦'));
    expect(reads, 1);
    expect(resolver.searches.single.$1, MusicDataSource.flac);
  });
}

ScreenshotSongDraft _draft(String title, String artist) => ScreenshotSongDraft(
  imageId: 'metadata',
  row: 0,
  title: title,
  artist: artist,
  version: '',
  rawText: '$title $artist',
);

MusicSearchCandidate _candidate(String title, String artist) =>
    MusicSearchCandidate(
      query: title,
      source: MusicDataSource.flac,
      platform: 'kuwo',
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

class _Resolver implements MusicResolver, StagedScreenshotSearchResolver {
  _Resolver({this.primary = const [], this.fallback = const []});
  final List<MusicSearchCandidate> primary;
  final List<MusicSearchCandidate> fallback;
  var primaryCalls = 0;
  var fallbackCalls = 0;
  final searches = <(MusicDataSource, String)>[];

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotPrimary(
    String title,
  ) async {
    primaryCalls++;
    return primary;
  }

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotFallback(
    String title,
    String artist,
  ) async {
    fallbackCalls++;
    return fallback;
  }

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searches.add((source, query));
    return source == MusicDataSource.auto ? [...primary, ...fallback] : primary;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}
