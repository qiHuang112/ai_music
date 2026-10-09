import 'package:ai_music/src/data/candidate_scorer.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/data/song_match_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scorer = CandidateScorer();

  double score(
    String title,
    String artist,
    String query, {
    bool flac = false,
  }) => scorer.scoreCandidate(
    {
      'name': title,
      'artist': artist,
      'minfo': [
        if (flac) {'format': 'flac', 'bitrate': '1000'},
      ],
    },
    query,
    'kuwo',
    query,
    1,
  );

  test(
    'better codec does not put unwanted live or DJ ahead of studio audio',
    () {
      final studio = score('后来', '刘若英', '刘若英 后来');
      for (final title in ['后来 (Live)', '后来 (DJ版)', '后来 (伴奏)']) {
        expect(score(title, '刘若英', '刘若英 后来', flac: true), lessThan(studio));
      }
    },
  );

  test('explicit version request prefers that performance', () {
    expect(
      score('后来 (Live)', '刘若英', '刘若英 后来 (Live)'),
      greaterThan(score('后来', '刘若英', '刘若英 后来 (Live)', flac: true)),
    );
  });

  test('title credits cannot impersonate the actual singer', () {
    final original = score('稻香', '周杰伦', '周杰伦 稻香');
    final cover = score('稻香 (原唱：周杰伦)', '另一位', '周杰伦 稻香', flac: true);
    expect(original, greaterThan(cover));
    expect(
      SongMatchIdentity(
        '稻香 (原唱：周杰伦)',
        '另一位',
      ).sameRecording(SongMatchIdentity('稻香', '周杰伦')),
      isFalse,
    );
  });

  test('shared characters are not an artist match', () {
    expect(
      scorer.isLooseArtistTitleCandidate(_candidate('后来', '张天一'), '张天 后来'),
      isFalse,
    );
  });

  test(
    'strict matching compares version and normalizes traditional metadata',
    () {
      expect(
        scorer.isStrictArtistCandidate(_candidate('后来', '刘若英'), '劉若英 後來'),
        isTrue,
      );
      expect(
        scorer.isStrictArtistCandidate(
          _candidate('后来 (Live)', '刘若英'),
          '刘若英 后来',
        ),
        isFalse,
      );
    },
  );

  test('unknown subtitles stay part of the title', () {
    expect(
      SongMatchIdentity(
        '后来 (另一首歌)',
        '刘若英',
      ).sameRecording(SongMatchIdentity('后来', '刘若英')),
      isFalse,
    );
  });
}

MusicSearchCandidate _candidate(String title, String artist) =>
    MusicSearchCandidate(
      query: title,
      source: MusicDataSource.flac,
      platform: 'kuwo',
      keyword: title,
      page: 1,
      id: title,
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
