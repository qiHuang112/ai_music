import 'dart:convert';

import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'lyrics_normalizer.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';
import 'song_match_identity.dart';

/// Uses the same public search and server-rendered song data as 24bit's player.
class TwentyFourBitResolver {
  TwentyFourBitResolver({required MusicResolverHttp httpClient})
    : _http = httpClient;

  static const base = 'https://www.24bit.net';
  final MusicResolverHttp _http;
  static const _scorer = CandidateScorer();
  static const _headers = {
    'user-agent': ChallengeClient.userAgent,
    'origin': base,
    'referer': '$base/',
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'zh-CN,zh;q=0.9',
  };

  Future<List<MusicSearchCandidate>> search(
    String query, {
    void Function(List<MusicSearchCandidate>)? onBatch,
    bool Function()? isCancelled,
    bool Function(MusicSearchCandidate)? matchesTarget,
  }) async {
    final found = <String, MusicSearchCandidate>{};
    List<MusicSearchCandidate> ranked() =>
        (found.values.toList()..sort((a, b) => b.score.compareTo(a.score)))
            .take(60)
            .toList(growable: false);
    bool stopped() => isCancelled?.call() == true;
    bool enough() => ranked().any(
      (c) => matchesTarget?.call(c) ?? !_scorer.needsDeepSearch(c, query),
    );
    final errors = <Object>[];
    var succeeded = false;
    for (final keyword in _scorer.buildKeywords(query).take(3)) {
      if (stopped()) break;
      final fullGroups = <String>[];
      Future<void> page(String group, int number) async {
        if (stopped()) return;
        try {
          final response = await _http.postJson(
            Uri.parse(
              '$base/api/player/searchOnlineMusic${group == 'b' ? 'Two' : 'One'}',
            ),
            {'keyword': Uri.encodeComponent(keyword), 'page': number},
            headers: _headers,
          );
          if (stopped()) return;
          _checkResponse(response);
          final payload = asStringMap(jsonDecode(response.body));
          final rows = payload['result'];
          if (rows is! List ||
              !(payload['status'] == true ||
                  payload['status'] == 200 ||
                  payload['status'] == 1)) {
            throw const FormatException(
              '24bit non-JSON response or invalid search result',
            );
          }
          succeeded = true;
          if (rows.length >= 30 && number == 1) fullGroups.add(group);
          for (final row in rows) {
            final candidate = _candidate(
              query,
              keyword,
              group,
              number,
              asStringMap(row),
            );
            if (candidate != null) found[candidate.id] = candidate;
          }
          onBatch?.call(ranked());
        } catch (error) {
          if (!stopped()) errors.add(error);
        }
      }

      await Future.wait([page('b', 1), page('a', 1)]);
      if (!succeeded && errors.isNotEmpty && !stopped()) {
        throw errors.first;
      }
      if (stopped() || enough()) break;
      // Search exact artist/title keywords before paging unrelated results.
      if (keyword == _scorer.buildKeywords(query).take(3).last) {
        for (final group in fullGroups) {
          if (stopped() || enough()) break;
          await page(group, 2);
        }
      }
    }
    if (stopped()) throw StateError('Source request cancelled');
    if (!succeeded && errors.isNotEmpty) throw errors.first;
    return ranked();
  }

  MusicSearchCandidate? _candidate(
    String query,
    String keyword,
    String group,
    int page,
    Map<String, dynamic> item,
  ) {
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString().trim() ?? '';
    final artist = item['player']?.toString().trim() ?? '';
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id) ||
        name.isEmpty ||
        artist.isEmpty) {
      return null;
    }
    final qualities = group == 'b'
        ? const [MusicQuality(format: 'flac', bitrate: '16bit 44kHz')]
        : const [
            MusicQuality(format: 'flac', bitrate: '24bit 192kHz'),
            MusicQuality(format: 'flac', bitrate: '24bit 96kHz'),
          ];
    final normalized = {
      'name': name,
      'artist': artist,
      'album_name': item['album'],
      'minfo': qualities.map((q) => q.toJson()).toList(),
    };
    return MusicSearchCandidate(
      query: query,
      source: MusicDataSource.twentyFourBit,
      platform: '24bit',
      keyword: keyword,
      page: page,
      id: '$group:$id',
      name: name,
      artist: artist,
      album: item['album']?.toString() ?? '',
      duration: 0,
      link: '$base/music/$group/$id',
      coverUrl: item['cover']?.toString() ?? '',
      qualities: qualities,
      score: _scorer.scoreCandidate(normalized, query, '24bit', keyword, page),
      raw: {...item, 'kind': group, 'siteId': id},
    );
  }

  Future<ResolvedMusic> resolve(
    MusicSearchCandidate candidate, {
    String? qualityPreference,
  }) async {
    final parts = candidate.id.split(':');
    if (parts.length != 2 ||
        !{'a', 'b'}.contains(parts.first) ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(parts.last)) {
      throw const FormatException('24bit song identity is invalid');
    }
    final kind =
        parts.first == 'a' && qualityPreference?.startsWith('mp3') == true
        ? 'c'
        : parts.first;
    final response = await _http.get(
      Uri.parse('$base/music/$kind/${parts.last}'),
      headers: {..._headers, 'accept': 'text/html'},
    );
    _checkResponse(response);
    final data = parseTwentyFourBitPage(response.body);
    if (data['id']?.toString() != parts.last ||
        !SongMatchIdentity(candidate.name, candidate.artist).sameRecording(
          SongMatchIdentity(
            data['name']?.toString() ?? '',
            data['player']?.toString() ?? '',
          ),
        )) {
      throw StateError('24bit returned a different recording');
    }
    final url = data['url']?.toString() ?? '';
    if (Uri.tryParse(url) case final uri?
        when uri.scheme == 'https' && uri.host.isNotEmpty) {
      return ResolvedMusic(
        query: candidate.query,
        source: MusicDataSource.twentyFourBit,
        platform: '24bit',
        id: candidate.id,
        name: data['name'].toString(),
        artist: data['player'].toString(),
        album: data['album']?.toString() ?? '',
        url: url,
        coverUrl: data['cover']?.toString() ?? '',
        quality: MusicQuality(
          format: data['format']?.toString() ?? '',
          bitrate: kind == 'b'
              ? '16bit 44kHz'
              : kind == 'c'
              ? '24bit 96kHz'
              : '24bit 192kHz',
          size: data['size']?.toString() ?? '',
        ),
        lyrics: makeResolvedLyrics(data['lrc'], '24bit:page'),
      );
    }
    throw StateError('24bit did not return a playable HTTPS audio URL');
  }

  static void _checkResponse(ResolverHttpResponse response) {
    if (!response.ok) throw StateError('24bit HTTP ${response.statusCode}');
    if (response.body.contains('cf-chl-') ||
        response.body.contains('Just a moment...')) {
      throw StateError('24bit HTTP 403: 网站需要验证');
    }
  }
}

/// Decode Next's JSON string frames as data; never execute downloaded scripts.
Map<String, dynamic> parseTwentyFourBitPage(String html) {
  final frames =
      RegExp(r'self\.__next_f\.push\((\[1,"(?:\\.|[^"\\])*"\])\)', dotAll: true)
          .allMatches(html)
          .map((m) => (jsonDecode(m[1]!) as List)[1] as String)
          .join();
  if (frames.contains('今日访问已达限额') || html.contains('今日访问已达限额')) {
    throw const SourceAccessException(
      MusicDataSource.twentyFourBit,
      '今日访问已达限额，请明日再试或登录网站账号',
    );
  }
  final marker = frames.indexOf('"itemMusic":');
  if (marker < 0) {
    throw const FormatException('24bit non-JSON response: missing song data');
  }
  final start = frames.indexOf('{', marker);
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = start; i >= 0 && i < frames.length; i++) {
    final c = frames[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quoted && c == r'\') {
      escaped = true;
      continue;
    }
    if (c == '"') {
      quoted = !quoted;
      continue;
    }
    if (quoted) continue;
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) {
      final data = asStringMap(jsonDecode(frames.substring(start, i + 1)));
      final lyrics = data['lrc']?.toString() ?? '';
      if (RegExp(r'^\$[a-f0-9]+$').hasMatch(lyrics)) {
        final ref = RegExp(
          '${RegExp.escape(lyrics.substring(1))}:T([a-f0-9]+),',
        ).firstMatch(frames);
        data['lrc'] = null;
        if (ref != null) {
          final size = int.parse(ref[1]!, radix: 16);
          final bytes = utf8.encode(frames.substring(ref.end));
          if (size <= bytes.length) {
            data['lrc'] = utf8.decode(bytes.take(size).toList());
          }
        }
      }
      return data;
    }
  }
  throw const FormatException('24bit non-JSON response: incomplete song data');
}
