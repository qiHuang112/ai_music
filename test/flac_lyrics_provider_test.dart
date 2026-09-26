import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'LRC action uses refreshed credentials of the exact cached song',
    () async {
      final api = _Api();
      final provider = FlacLyricsProvider(challengeClient: api);
      final results = await Future.wait([
        provider.find(_track()),
        provider.find(_track()),
      ]);
      expect(results.first.lyrics.single.text, '测试歌词');
      expect(results.first.source, 'flac:getLyric');
      expect(api.actions, ['search', 'getLyric']);
      expect(api.lyricForm, {
        'platform': 'kuwo',
        'songid': '42',
        'time': 'fresh-time',
        'sign': 'fresh-sign',
      });
    },
  );

  test(
    'artist and title search finds an exact song missing from title page',
    () async {
      final api = _Api(matchOnlyWithArtistQuery: true);
      final result = await FlacLyricsProvider(
        challengeClient: api,
      ).find(_track());
      expect(result.lyrics.single.text, '测试歌词');
      expect(api.searchKeywords, ['测试曲', '测试歌手 测试曲']);
      expect(api.actions, ['search', 'search', 'getLyric']);
    },
  );

  for (final field in ['id', 'name', 'artist']) {
    test('rejects mismatched $field without requesting lyrics', () async {
      final api = _Api(mismatch: field);
      final result = await FlacLyricsProvider(
        challengeClient: api,
      ).find(_track());
      expect(result.hasLyrics, isFalse);
      expect(api.actions, ['search', 'search']);
    });
  }

  for (final content in [
    'https://cdn.example.test/audio.flac',
    '<html>error</html>',
    '<div>Service unavailable</div>',
    '&lt;div&gt;Service unavailable&lt;/div&gt;',
    '暂无歌词',
  ]) {
    test('rejects non-lyric response $content', () async {
      final result = await FlacLyricsProvider(
        challengeClient: _Api(content: content),
      ).find(_track());
      expect(result.hasLyrics, isFalse);
    });
  }

  test('failed source does not break playback and does not loop', () async {
    final api = _Api(code: 1);
    final result = await FlacLyricsProvider(
      challengeClient: api,
    ).find(_track());
    expect(result.hasLyrics, isFalse);
    expect(api.actions, ['search', 'getLyric']);
  });
}

CachedTrack _track() => CachedTrack(
  cacheId: 'flac-kuwo-42',
  filePath: '/tmp/flac-test.mp3',
  sizeBytes: 4,
  fromCache: true,
  music: const ResolvedMusic(
    query: '测试曲',
    source: MusicDataSource.flac,
    platform: 'kuwo',
    id: '42',
    name: '测试曲',
    artist: '测试歌手',
    album: '',
    url: 'https://example.test/audio.mp3',
    quality: MusicQuality(format: 'mp3'),
  ),
);

class _Api extends ChallengeClient {
  _Api({
    this.mismatch,
    this.content = '[00:01.00]测试歌词',
    this.code = 0,
    this.matchOnlyWithArtistQuery = false,
  }) : super(httpClient: HttpMusicResolverClient());
  final String? mismatch;
  final String content;
  final int code;
  final bool matchOnlyWithArtistQuery;
  final actions = <String>[];
  final searchKeywords = <String>[];
  Map<String, String>? lyricForm;
  @override
  Future<Map<String, dynamic>> postFlacApi(
    String act,
    Map<String, String> form,
  ) async {
    actions.add(act);
    if (act == 'search') {
      expect(form['platform'], 'kuwo');
      expect(form['page'], '1');
      searchKeywords.add(form['keyword'] ?? '');
      if (matchOnlyWithArtistQuery && form['keyword'] == '测试曲') {
        return {
          'code': 0,
          'data': {'list': []},
        };
      }
      return {
        'code': 0,
        'data': {
          'list': [
            {
              'id': '42',
              'name': '测试曲',
              'artist': '测试歌手',
              'time': 'fresh-time',
              'sign': 'fresh-sign',
              ?mismatch: 'another-version',
            },
          ],
        },
      };
    }
    expect(act, 'getLyric');
    lyricForm = form;
    return {'code': code, 'data': content};
  }
}
