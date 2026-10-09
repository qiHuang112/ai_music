import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/application/screenshot_song_parser.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Public QQ playlist 9765682818, 凡人百世书-BGM / 张天一.
/// IDs/metadata and candidates were observed on 2026-10-08. No audio is fetched.
void main() {
  final samples = <_Sample>[
    _Sample('归零', '魔鬼花园_李安健', '621769697', 126, false, [
      _song('621769697', '归零', '魔鬼花园_李安健', 126),
    ]),
    _Sample('鸿门旋律 (Version)', 'GTR7', '459611186', 89, false, [
      _song('629844487', 'My Love (Club Version)', 'DJ木南', 53),
      _song('607387905', '鸿门旋律', 'Sixteen&LongTran Final&Now Funk', 182),
      _song('459611186', '鸿门旋律', 'GTR7', 89),
    ]),
    _Sample('Time is Broken (浴室氛围版)', 'Dr.Phonk', '552017600', 241, false, [
      _song('648528624', 'Time Is Broken', 'Moste Getsu&Dr.Phonk', 201),
      _song('552017600', 'Time is Broken (浴室氛围版)', 'Dr.Phonk', 241),
    ]),
    _Sample('回忆观影券 (伴奏)', 'IN-K / 王忻辰', '2020596186', 172, true, [
      _song('147904615', '回忆观影券', 'IN-K&王忻辰', 170),
      _song('2020596186', '回忆观影券 (伴奏)', 'IN-K', 172, platform: 'wyy'),
    ]),
    _Sample('星游记进行曲', 'LUCHANGSHENG', '563925587', 143, false, [
      _song('614064263', '星游记进行曲', 'Sixteen&LongTran Final&404Hz', 142),
      _song('563925587', '星游记进行曲', 'LUCHANGSHENG', 143),
    ]),
    _Sample(
      'Lost Control (feat. Bianca)',
      'Tyron Hapi / Bianca',
      '51567593',
      269,
      false,
      [
        _song(
          '51567593',
          'Lost Control (feat. Bianca)',
          'Tyron Hapi&Bianca',
          269,
        ),
      ],
    ),
    _Sample('Manestein (慢摇氛围版)', 'TF', '516890114', 153, true, [
      _song('524792508', 'Manestein', 'TF', 201),
      _song('516890114', 'Manestein', 'TF', 153),
      _song('594180016', 'Manestein', 'La Mer&Grimmmz&Ameriie&Sixteen', 150),
    ]),
  ];

  for (final mode in [MusicDataSource.flac, MusicDataSource.auto]) {
    for (final sample in samples) {
      test('${mode.name}: exact QQ title ${sample.title}', () async {
        final resolver = _Resolver(sample);
        final match = await ScreenshotMatcher(
          resolver: resolver,
          source: mode,
          allowTitleFragments: false,
          requestStartSpacing: Duration.zero,
        ).match(sample.draft);
        expect(match.recommended?.id, sample.expectedId);
        expect(match.needsReview, sample.needsReview);
        expect(resolver.searches, [(mode, '${sample.artist} ${sample.title}')]);
        expect(resolver.stagedSearches, 0);
      });
    }
  }

  test(
    'requested accompaniment beats full duet credit for the vocal version',
    () {
      final sample = samples[3];
      final match = ScreenshotMatcher(
        resolver: _Resolver(sample),
        allowTitleFragments: false,
      ).rankCached(sample.draft, sample.candidates);
      expect(match.recommended?.id, '2020596186');
      // QQ credits both names, whereas NetEase credits only IN-K: do not claim
      // exact identity just because this is a much better version match.
      expect(match.needsReview, isTrue);
    },
  );
  test(
    'same identity duration distinguishes long edit without inventing version',
    () {
      final sample = samples.last;
      final matcher = ScreenshotMatcher(
        resolver: _Resolver(sample),
        allowTitleFragments: false,
      );
      final result = matcher.rankCached(sample.draft, sample.candidates);
      expect(result.recommended?.duration, 153);
      expect(result.needsReview, isTrue);
      final noDuration = ScreenshotSongDraft(
        imageId: 'no-time',
        row: 0,
        title: sample.title,
        artist: sample.artist,
        version: '',
        rawText: '',
      );
      expect(
        matcher.rankCached(noDuration, sample.candidates).recommended?.duration,
        201,
      );
    },
  );
}

class _Sample {
  _Sample(
    this.title,
    this.artist,
    this.expectedId,
    this.durationSeconds,
    this.needsReview,
    this.candidates,
  );
  final String title;
  final String artist;
  final String expectedId;
  final bool needsReview;
  final int durationSeconds;
  final List<MusicSearchCandidate> candidates;
  ScreenshotSongDraft get draft => ScreenshotSongDraft(
    imageId: 'qq:9765682818',
    row: 0,
    title: title,
    artist: artist,
    version: '',
    durationSeconds: durationSeconds,
    rawText: '$title $artist',
  );
}

class _Resolver implements MusicResolver, StagedScreenshotSearchResolver {
  _Resolver(this.sample);
  final _Sample sample;
  final searches = <(MusicDataSource, String)>[];
  var stagedSearches = 0;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    searches.add((source, query));
    return sample.candidates;
  }

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotPrimary(
    String title,
  ) async {
    stagedSearches++;
    return [];
  }

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotFallback(
    String title,
    String artist,
  ) async {
    stagedSearches++;
    return sample.candidates.take(1).toList();
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}

MusicSearchCandidate _song(
  String id,
  String title,
  String artist,
  int duration, {
  String platform = 'kuwo',
}) => MusicSearchCandidate(
  query: title,
  source: MusicDataSource.flac,
  platform: platform,
  keyword: title,
  page: 1,
  id: id,
  name: title,
  artist: artist,
  album: '',
  duration: duration,
  link: '',
  coverUrl: '',
  qualities: [],
  score: 100,
  raw: {},
);
