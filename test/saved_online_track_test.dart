import 'dart:convert';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artistless screenshot selection survives playlist reload', () {
    final saved = SavedOnlineTrack(
      candidate: MusicSearchCandidate(
        query: '剩下的果实',
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        keyword: '剩下的果实',
        page: 1,
        id: 'song-2',
        name: '剩下的果实',
        artist: '',
        album: '',
        duration: 220,
        link: '',
        coverUrl: '',
        qualities: const [],
        score: 0,
        raw: const {},
      ),
    );

    final restored = SavedOnlineTrack.fromJson(saved.toJson());
    expect(restored?.candidate.artist, '');
    expect(restored?.trackId, saved.trackId);
  });

  test('saved candidate keeps re-resolution tokens but no media URL', () {
    final saved = SavedOnlineTrack(
      candidate: MusicSearchCandidate(
        query: '稻香',
        source: MusicDataSource.flac,
        platform: 'kuwo',
        keyword: '稻香',
        page: 1,
        id: 'song-1',
        name: '稻香',
        artist: '周杰伦',
        album: '',
        duration: 220,
        link: 'https://cdn.example.test/expired.mp3',
        coverUrl: '',
        qualities: const [MusicQuality(format: 'mp3')],
        score: 250,
        raw: const {
          'time': '123',
          'sign': 'signature',
          'lrc': '[00:01.00]歌词',
          'url': 'https://cdn.example.test/expired.mp3',
          'downloadUrls': {'mp3': 'https://cdn.example.test/expired.mp3'},
        },
      ),
    );

    final json = jsonEncode(saved.toJson());
    final restored = SavedOnlineTrack.fromJson(jsonDecode(json));

    expect(json, isNot(contains('expired.mp3')));
    expect(restored?.candidate.raw['time'], '123');
    expect(restored?.candidate.raw['sign'], 'signature');
    expect(restored?.candidate.raw['lrc'], '[00:01.00]歌词');
  });
}
