import 'dart:math';

import 'package:ai_music/src/application/search_playback_session.dart';
import 'package:ai_music/src/data/resolver_models.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appends later pages without changing the selected song', () {
    final session = SearchPlaybackSession(
      request: 7,
      query: '周杰伦',
      candidates: [_candidate('1'), _candidate('2')],
    );

    session.select(_candidate('2'));
    session.append([_candidate('2'), _candidate('3')]);

    expect(session.candidates.map((item) => item.id), ['1', '2', '3']);
    expect(session.current?.id, '2');
    expect(session.currentIndex, 1);
  });

  test('sequential stops at the end while loop all wraps', () {
    final session = SearchPlaybackSession(
      request: 1,
      query: '歌手',
      candidates: [_candidate('1'), _candidate('2')],
    );
    session.select(_candidate('2'));

    expect(session.next(PlaybackMode.sequential, automatic: true), isNull);
    expect(session.next(PlaybackMode.loopAll, automatic: true)?.id, '1');
  });

  test('repeat one repeats automatically but manual next advances', () {
    final session = SearchPlaybackSession(
      request: 1,
      query: '歌手',
      candidates: [_candidate('1'), _candidate('2')],
    );
    session.select(_candidate('1'));

    expect(session.next(PlaybackMode.repeatOne, automatic: true)?.id, '1');
    expect(session.next(PlaybackMode.repeatOne, automatic: false)?.id, '2');
  });

  test('shuffle keeps a stable order when a later page is appended', () {
    final session = SearchPlaybackSession(
      request: 1,
      query: '歌手',
      candidates: [_candidate('1'), _candidate('2'), _candidate('3')],
      random: Random(9),
    );
    session.select(_candidate('2'));

    final first = session.next(PlaybackMode.shuffle, automatic: false);
    session.append([_candidate('4'), _candidate('5')]);
    final second = session.next(PlaybackMode.shuffle, automatic: false);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.id, isNot('2'));
    expect(second!.id, isNot(first.id));
    expect(session.candidates.map((item) => item.id).toSet(), {
      '1',
      '2',
      '3',
      '4',
      '5',
    });
  });
}

MusicSearchCandidate _candidate(String id) {
  return MusicSearchCandidate(
    query: 'query',
    source: MusicDataSource.gequhai,
    platform: 'gequhai',
    keyword: 'query',
    page: 1,
    id: id,
    name: 'Song $id',
    artist: 'Artist',
    album: '',
    duration: 180,
    link: '',
    coverUrl: '',
    qualities: const [MusicQuality(format: 'mp3')],
    score: 100,
    raw: const {'clientReady': true, 'urlType': 'direct_audio'},
  );
}
