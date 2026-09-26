import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses lyrics only after matching the identical Kuwo audio resource',
    () async {
      final api = _Api();
      final result = await BuguyyKuwoLyricsProvider(
        challengeClient: api,
      ).find(_track());
      expect(result.lyrics.single.text, '同一现场版歌词');
      expect(result.source, 'flac:getLyric:matched-kuwo-audio');
      expect(api.actions, [
        'search',
        'getUrl:studio',
        'getUrl:live',
        'getLyric:live',
      ]);
    },
  );

  test(
    'similar title and artist cannot borrow lyrics from another recording',
    () async {
      final api = _Api(matchingResource: false);
      final result = await BuguyyKuwoLyricsProvider(
        challengeClient: api,
      ).find(_track());
      expect(result.hasLyrics, isFalse);
      expect(api.actions, ['search', 'getUrl:studio', 'getUrl:live', 'search']);
    },
  );

  test('artist and title query finds the exact matching audio', () async {
    final api = _Api(onlyArtistQuery: true);
    final result = await BuguyyKuwoLyricsProvider(
      challengeClient: api,
    ).find(_track());
    expect(result.lyrics.single.time, const Duration(seconds: 1));
    expect(api.actions, [
      'search',
      'search',
      'getUrl:studio',
      'getUrl:live',
      'getLyric:live',
    ]);
  });

  test('matches the exact Kuwo trackmedia MP3 resource', () async {
    const resource = 'resource/30106/trackmedia/M800002S3TYo3YJY0x.mp3';
    final api = _Api(onlyArtistQuery: true, resourcePath: resource);
    final result = await BuguyyKuwoLyricsProvider(
      challengeClient: api,
    ).find(_track(url: 'https://car-lv.kuwo.cn/token/$resource'));

    expect(result.lyrics.single.time, const Duration(seconds: 1));
    expect(api.actions.last, 'getLyric:live');
  });

  test('non-Kuwo audio cannot trigger the cross-source lookup', () async {
    final api = _Api();
    final result = await BuguyyKuwoLyricsProvider(challengeClient: api).find(
      _track(url: 'https://cdn.example.test/resource/n2/80/0/906563066.mp3'),
    );
    expect(result.hasLyrics, isFalse);
    expect(api.actions, isEmpty);
  });

  test('cross-source lookup rejects an HTML response', () async {
    final api = _Api(lyric: '<div>Service unavailable</div>');
    final result = await BuguyyKuwoLyricsProvider(
      challengeClient: api,
    ).find(_track());
    expect(result.hasLyrics, isFalse);
  });
}

CachedTrack _track({
  String url =
      'http://car-bj.kuwo.cn/token/time/lx/resource/n2/80/0/906563066.mp3',
}) => CachedTrack(
  cacheId: 'buguyy-live-test',
  filePath: '/tmp/winter.mp3',
  sizeBytes: 4,
  fromCache: true,
  music: ResolvedMusic(
    query: '冬天的秘密',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'MTEyNDA5NDc=',
    name: '冬天的秘密',
    artist: '周传雄',
    album: '',
    url: url,
    quality: const MusicQuality(format: 'mp3'),
  ),
);

class _Api extends ChallengeClient {
  _Api({
    this.matchingResource = true,
    this.lyric = '[00:01.00]同一现场版歌词',
    this.onlyArtistQuery = false,
    this.resourcePath = 'resource/n2/80/0/906563066.mp3',
  }) : super(httpClient: HttpMusicResolverClient());

  final bool matchingResource;
  final String lyric;
  final bool onlyArtistQuery;
  final String resourcePath;
  final actions = <String>[];

  @override
  Future<Map<String, dynamic>> postFlacApi(
    String act,
    Map<String, String> form,
  ) async {
    if (act == 'search') {
      actions.add(act);
      expect(form['platform'], 'kuwo');
      expect(form['keyword'], anyOf('冬天的秘密', '周传雄 冬天的秘密'));
      return {
        'code': 0,
        'data': {
          'list': [
            for (final id
                in onlyArtistQuery && form['keyword'] == '冬天的秘密'
                    ? <String>[]
                    : ['studio', 'live'])
              {
                'id': id,
                'name': '冬天的秘密',
                'artist': '周传雄',
                'time': 'fresh-time',
                'sign': 'fresh-sign',
                'minfo': [
                  {'format': 'mp3', 'bitrate': '320', 'size': '7M'},
                ],
              },
          ],
        },
      };
    }
    final id = form['songid']!;
    actions.add('$act:$id');
    expect(form['time'], 'fresh-time');
    expect(form['sign'], 'fresh-sign');
    if (act == 'getUrl') {
      return {
        'code': 0,
        'data': {
          'url':
              'https://other-lv.kuwo.cn/token/time/lx/'
              '${id == 'live' && matchingResource ? resourcePath : 'resource/n2/80/0/different.mp3'}',
        },
      };
    }
    expect(act, 'getLyric');
    expect(id, 'live');
    return {'code': 0, 'data': lyric};
  }
}
