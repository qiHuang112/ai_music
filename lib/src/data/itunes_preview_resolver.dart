import 'dart:convert';
import 'dart:io';

import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'lyrics_normalizer.dart';
import 'resolver_candidate_mapper.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class ItunesPreviewResolver {
  const ItunesPreviewResolver({
    required MusicResolverHttp httpClient,
    CandidateScorer scorer = const CandidateScorer(),
    this.country = 'CN',
    this.limit = 25,
  }) : _http = httpClient,
       _scorer = scorer;

  final MusicResolverHttp _http;
  final CandidateScorer _scorer;
  final String country;
  final int limit;

  Future<List<MusicSearchCandidate>> search(String query) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': query,
      'media': 'music',
      'entity': 'song',
      'country': country,
      'limit': '$limit',
    });
    final response = await _http.get(uri, headers: _headers);
    final json = _decodeJson(response, label: 'itunes');
    if (!response.ok) {
      throw HttpException('itunes HTTP ${response.statusCode}', uri: uri);
    }
    final rows = json['results'] is List ? json['results'] as List : const [];
    final candidates = <MusicSearchCandidate>[];
    for (final row in rows) {
      final item = asStringMap(row);
      final previewUrl = item['previewUrl']?.toString().trim() ?? '';
      if (previewUrl.isEmpty) {
        continue;
      }
      final mapped = <String, dynamic>{
        'id': item['trackId']?.toString() ?? previewUrl,
        'name': item['trackName']?.toString() ?? '',
        'artist': item['artistName']?.toString() ?? '',
        'album': item['collectionName']?.toString() ?? '',
        'duration': intFrom(item['trackTimeMillis']) ~/ 1000,
        'pic_url': _largeArtworkUrl(item['artworkUrl100']?.toString() ?? ''),
        'minfo': [
          {'format': 'preview', 'bitrate': 'AAC', 'size': '30s'},
        ],
        ...item,
      };
      final score = _scorer.scoreCandidate(mapped, query, 'itunes', query, 1);
      candidates.add(
        candidateFromItem(
          query: query,
          source: MusicDataSource.itunesPreview,
          platform: 'itunes',
          keyword: query,
          page: 1,
          item: mapped,
          score: score,
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(30).toList(growable: false);
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final previewUrl = candidate.raw['previewUrl']?.toString().trim() ?? '';
    if (previewUrl.isEmpty) {
      throw SourceDownloadException(
        'iTunes preview URL unavailable.',
        failureCode: 'play_url_unavailable',
        sourceAttempts: [_attempt(candidate, SourceAttemptStatus.failed)],
      );
    }
    final lyrics = await _lyrics(candidate);
    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.itunesPreview,
      platform: 'itunes',
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: candidate.album,
      url: previewUrl,
      quality: const MusicQuality(
        format: 'preview',
        bitrate: 'AAC',
        size: '30s',
      ),
      coverUrl: candidate.coverUrl,
      lyrics: lyrics,
      duration: candidate.duration,
      urlType: MediaUrlType.previewAudio,
      canCacheAudio: false,
      sourceAttempts: [
        _attempt(
          candidate,
          SourceAttemptStatus.ok,
          mediaUrl: previewUrl,
          lyricsStatus: lyrics == null ? 'missing' : 'ok',
          reasonCode: 'preview_audio_available',
        ),
      ],
    );
  }

  Future<ResolvedLyrics?> _lyrics(MusicSearchCandidate candidate) async {
    final title = candidate.name.trim();
    if (title.isEmpty) {
      return null;
    }
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (candidate.artist.trim().isNotEmpty) 'artist_name': candidate.artist,
    });
    try {
      final response = await _http.get(uri, headers: _headers);
      if (!response.ok) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return null;
      }
      for (final row in decoded) {
        final item = asStringMap(row);
        final synced = makeResolvedLyrics(
          item['syncedLyrics'],
          'lrclib:syncedLyrics',
        );
        if (synced != null) {
          return synced;
        }
        final plain = makeResolvedLyrics(
          item['plainLyrics'],
          'lrclib:plainLyrics',
        );
        if (plain != null) {
          return plain;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

SourceAttempt _attempt(
  MusicSearchCandidate candidate,
  SourceAttemptStatus status, {
  String failureCode = '',
  String reasonCode = '',
  String mediaUrl = '',
  String lyricsStatus = '',
}) {
  return SourceAttempt(
    query: candidate.query,
    source: MusicDataSource.itunesPreview,
    stage: 'resolve',
    status: status,
    failureCode: failureCode,
    reasonCode: reasonCode,
    candidateId: candidate.id,
    candidateTitle: candidate.name,
    candidateArtist: candidate.artist,
    matchConfidence: candidate.score,
    mediaUrl: mediaUrl,
    mediaUrlType: mediaUrl.isEmpty
        ? MediaUrlType.unknown
        : MediaUrlType.previewAudio,
    lyricsStatus: lyricsStatus,
    coverUrl: candidate.coverUrl,
  );
}

Map<String, dynamic> _decodeJson(
  ResolverHttpResponse response, {
  required String label,
}) {
  try {
    return asStringMap(jsonDecode(response.body));
  } catch (_) {
    throw FormatException('$label non-JSON response ${response.statusCode}');
  }
}

String _largeArtworkUrl(String url) {
  if (url.isEmpty) {
    return '';
  }
  return url.replaceFirst('100x100bb', '600x600bb');
}

const _headers = {
  'accept': 'application/json, text/plain, */*',
  'accept-language': 'zh-CN,zh;q=0.9',
  'user-agent': ChallengeClient.userAgent,
};
