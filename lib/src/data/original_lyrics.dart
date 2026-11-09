import 'dart:async';
import 'dart:convert';

import '../domain/music_models.dart';
import 'lyrics_normalizer.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'song_comments.dart';

/// Synchronized lyrics from the song's original platform, for audio whose
/// own provider only carries plain text (BuguYY's "about" lyrics have no
/// timestamps, so the player cannot follow them).
///
/// The recording is found with the same strict title/artist/duration check
/// as song comments, and the caller still compares the words with the plain
/// lyrics it has before adopting them.
class OriginalSongLyrics {
  OriginalSongLyrics({
    SongCommentsRepository? songs,
    MusicResolverHttp? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _songs = songs ?? SongCommentsRepository.shared,
       _http = httpClient ?? HttpMusicResolverClient();

  final SongCommentsRepository _songs;
  final MusicResolverHttp _http;
  final Duration timeout;

  /// Timed lines of the NetEase copy, or empty when there is none.
  Future<List<LyricLine>> find(SongCommentQuery query) async {
    final song = await _songs.findSong(query, SongCommentPlatform.netease);
    if (song == null) return const [];
    final response = await _http
        .get(
          Uri.https('music.163.com', '/api/song/lyric', {
            'id': song.id,
            'lv': '1',
          }),
          headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://music.163.com/',
          },
        )
        .timeout(timeout);
    if (!response.ok) return const [];
    final root = jsonDecode(response.body);
    if (root is! Map) return const [];
    final lrc = root['lrc'];
    final text = lrc is Map ? lrc['lyric']?.toString() ?? '' : '';
    final lines = parseLrcLines(text);
    return lines.any((line) => line.time > Duration.zero) ? lines : const [];
  }
}

/// Whether [timed] carries the same words as the [plain] lyrics already
/// shown: most of its sung lines must appear there, so lyrics of another
/// song or version are never adopted.
bool timedLyricsMatchPlain(List<LyricLine> timed, List<LyricLine> plain) {
  String key(String text) => text.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );
  final known = {for (final line in plain) key(line.text)}..remove('');
  final sung = [
    for (final line in timed)
      if (key(line.text).isNotEmpty) key(line.text),
  ];
  if (known.length < 4 || sung.length < 4) return false;
  final shared = sung.where(known.contains).length;
  return shared / sung.length >= .6;
}
