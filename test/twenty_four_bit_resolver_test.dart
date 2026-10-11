import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

const songId = '943e5cfd3555f45f5847010ebb501086';
Map<String, Object?> song({String name = '晴天', String artist = '周杰伦'}) => {
  'id': songId,
  'name': name,
  'player': artist,
  'album': '叶惠美',
};
String page({
  String name = '晴天',
  String artist = '周杰伦',
  String url = 'https://cdn.example/song.flac',
}) {
  const lrc = '[00:01.00]test line } " and 中文\n[00:02.00]second line';
  final data = {
    ...song(name: name, artist: artist),
    'url': url,
    'format': 'flac',
    'cover': 'https://cdn.example/cover.jpg',
    'size': '52.83 MB',
    'lrc': r'$c',
  };
  final frames = [
    'c:T${utf8.encode(lrc).length.toRadixString(16)},',
    lrc,
    'a:${jsonEncode({'itemMusic': data})}\n',
  ];
  return frames
      .map((f) => '<script>self.__next_f.push(${jsonEncode([1, f])})</script>')
      .join();
}

void main() {
  test(
    'HTTP 200 daily quota is an access restriction, not invalid song data',
    () async {
      final http = Fake24Http()
        ..html =
            '<script>self.__next_f.push(${jsonEncode([1, 'a:["\u4eca\u65e5\u8bbf\u95ee\u5df2\u8fbe\u9650\u989d，可明日再来。"]'])})</script>';
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
      );
      final candidate = (await resolver.search(
        '晴天 周杰伦',
        MusicDataSource.twentyFourBit,
      )).first;
      await expectLater(
        resolver.resolveForSourceMode(candidate, MusicDataSource.twentyFourBit),
        throwsA(
          isA<SourceAccessException>().having(
            (e) => e.toString(),
            'message',
            contains('今日访问已达限额'),
          ),
        ),
      );
      expect(http.gets, hasLength(1));
      expect(
        resolver.availableAutoSources,
        isNot(contains(MusicDataSource.twentyFourBit)),
      );
      expect(
        resolver.availableAutoSources,
        containsAll([MusicDataSource.flac, MusicDataSource.buguyy]),
      );
      http.posts.clear();
      await expectLater(
        resolver.search('另一个查询', MusicDataSource.auto),
        throwsA(anything),
      );
      expect(http.posts, isEmpty);
      expect(http.gets, hasLength(1));
    },
  );
  test('decodes split Next frames and byte-sized referenced lyrics as data', () {
    final result = parseTwentyFourBitPage(page());
    expect(result['id'], songId);
    expect(result['lrc'], contains('中文'));
    expect(result['lrc'], endsWith('second line'));
    expect(
      () => parseTwentyFourBitPage('<html>Just a moment...</html>'),
      throwsFormatException,
    );
    expect(
      () => parseTwentyFourBitPage(
        '<script>self.__next_f.push(${jsonEncode([1, 'a:{"itemMusic":{'])})</script>',
      ),
      throwsFormatException,
    );
  });
  test(
    'search reuses both public JSON APIs and ranks original above covers',
    () async {
      final http = Fake24Http();
      final resolver = TwentyFourBitResolver(httpClient: http);
      final batches = <int>[];
      final found = await resolver.search(
        '晴天 周杰伦',
        onBatch: (c) => batches.add(c.length),
      );
      expect(http.posts, hasLength(2));
      expect(
        http.posts.map((e) => e.$1.path),
        containsAll([
          '/api/player/searchOnlineMusicOne',
          '/api/player/searchOnlineMusicTwo',
        ]),
      );
      expect(http.posts.first.$2, {
        'keyword': Uri.encodeComponent('晴天 周杰伦'),
        'page': 1,
      });
      expect(found.first.name, '晴天');
      expect(found.first.artist, '周杰伦');
      expect(found.first.source, MusicDataSource.twentyFourBit);
      expect(found.first.link, 'https://www.24bit.net/music/b/$songId');
      expect(batches, isNotEmpty);
      final resolved = await resolver.resolve(found.first);
      expect(resolved.quality.bitrate, '16bit 44kHz');
      expect(resolved.quality.size, '52.83 MB');
      expect(resolved.lyrics?.timed, isTrue);
    },
  );
  test(
    'each resolution refreshes expiring media and uses actual quality',
    () async {
      final http = Fake24Http();
      final resolver = TwentyFourBitResolver(httpClient: http);
      final item = (await resolver.search('晴天 周杰伦')).first;
      await resolver.resolve(item);
      await resolver.resolve(item, qualityPreference: 'mp3:128');
      expect(http.gets, hasLength(2));
      expect(http.gets.every((u) => u.path == '/music/b/$songId'), isTrue);
      final high = (await resolver.search(
        '晴天 周杰伦',
      )).firstWhere((c) => c.id.startsWith('a:'));
      await resolver.resolve(high, qualityPreference: 'mp3:128');
      expect(http.gets.last.path, '/music/c/$songId');
    },
  );
  test(
    'wrong recording, unsafe URL and verification HTML never resolve',
    () async {
      final http = Fake24Http();
      final resolver = TwentyFourBitResolver(httpClient: http);
      final item = (await resolver.search('晴天 周杰伦')).first;
      for (final content in [
        page(name: '晴天 (Live)'),
        page(artist: '翻唱歌手'),
        page(url: 'http://cdn.example/song.flac'),
        '<html>verification</html>',
      ]) {
        http.html = content;
        await expectLater(resolver.resolve(item), throwsA(anything));
      }
    },
  );
  test(
    'empty result stays empty, service failure stops after first pair',
    () async {
      final http = Fake24Http()..rows = [];
      final resolver = TwentyFourBitResolver(httpClient: http);
      expect(await resolver.search('不存在'), isEmpty);
      http.posts.clear();
      http.status = 403;
      await expectLater(
        resolver.search('晴天 周杰伦'),
        throwsA(predicate((e) => e.toString().contains('HTTP 403'))),
      );
      expect(http.posts, hasLength(2));
    },
  );
  test(
    'cancellation ignores late results and starts no keyword or detail work',
    () async {
      final http = Fake24Http()..gate = Completer<void>();
      final resolver = TwentyFourBitResolver(httpClient: http);
      var cancelled = false;
      var batches = 0;
      final operation = resolver.search(
        '晴天 周杰伦',
        isCancelled: () => cancelled,
        onBatch: (_) => batches++,
      );
      final assertion = expectLater(operation, throwsA(anything));
      cancelled = true;
      http.gate!.complete();
      await assertion;
      expect(batches, 0);
      expect(http.posts, hasLength(2));
      expect(http.gets, isEmpty);
    },
  );
  test(
    'Auto includes 24bit and uses it when both existing services fail',
    () async {
      final http = Fake24Http();
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
      );
      final progress = await resolver
          .searchProgressively('晴天 周杰伦', MusicDataSource.auto)
          .toList();
      expect(progress.last.error, isNull);
      expect(
        progress.last.candidates.every(
          (c) => c.source == MusicDataSource.twentyFourBit,
        ),
        isTrue,
      );
      final item = progress.last.candidates.first;
      final resolved = await resolver.resolveAlternative(
        item,
        excludedSources: {MusicDataSource.buguyy, MusicDataSource.flac},
      );
      expect(resolved.source, MusicDataSource.twentyFourBit);
      expect(resolved.name, '晴天');
    },
  );
  test(
    'playlist matching falls back to 24bit after existing providers fail',
    () async {
      final resolver = RemoteMusicResolver(
        httpClient: Fake24Http(),
        initialFlacCookie: 'ready',
      );
      final found = await resolver.searchScreenshot('晴天', '周杰伦');
      expect(found.first.source, MusicDataSource.twentyFourBit);
      expect(found.first.artist, '周杰伦');
    },
  );
  test(
    '24bit failure is isolated from healthy FLAC and manual source persists',
    () async {
      final http = Fake24Http()..status = 503;
      final resolver = RemoteMusicResolver(
        httpClient: http,
        initialFlacCookie: 'ready',
      );
      for (var i = 0; i < 3; i++) {
        await expectLater(
          resolver.search('晴天', MusicDataSource.twentyFourBit),
          throwsA(anything),
        );
      }
      expect(
        resolver.availableAutoSources,
        isNot(contains(MusicDataSource.twentyFourBit)),
      );
      expect(resolver.availableAutoSources, contains(MusicDataSource.flac));
      http.status = 200;
      expect(
        await resolver.search('晴天 周杰伦', MusicDataSource.twentyFourBit),
        isNotEmpty,
      );
      expect(
        MusicDataSource.fromStorage('24bit'),
        MusicDataSource.twentyFourBit,
      );
    },
  );
}

class Fake24Http implements MusicResolverHttp {
  final posts = <(Uri, Object)>[];
  final gets = <Uri>[];
  int status = 200;
  String? html;
  List<Map<String, Object?>>? rows;
  Completer<void>? gate;
  ResolverHttpResponse response(Uri uri, String body) =>
      ResolverHttpResponse(statusCode: status, body: body, finalUrl: uri);
  @override
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (uri.host != 'www.24bit.net') throw const SocketException('offline');
    gets.add(uri);
    return response(uri, html ?? page());
  }

  @override
  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    expect(uri.host, 'www.24bit.net');
    expect(headers['origin'], 'https://www.24bit.net');
    expect(headers['referer'], 'https://www.24bit.net/');
    posts.add((uri, body));
    await gate?.future;
    return response(
      uri,
      jsonEncode({
        'status': true,
        'result': rows ?? [song(name: '晴天 (Live)'), song()],
      }),
    );
  }

  @override
  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async => throw const SocketException('offline');
}
