// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'lyrics_normalizer.dart';
import 'resolver_candidate_mapper.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class FlacResolver {
  FlacResolver({
    required ChallengeClient challengeClient,
    CandidateScorer scorer = const CandidateScorer(),
    this.pages = 8,
    this.platforms = const ['kuwo', 'wyy'],
    this.prefer = 'flac',
    this.apiTimeout = const Duration(seconds: 6),
  }) : _challenge = challengeClient,
       _scorer = scorer;

  final ChallengeClient _challenge;
  final CandidateScorer _scorer;
  final int pages;
  final List<String> platforms;
  final String prefer;
  final Duration apiTimeout;

  Future<List<MusicSearchCandidate>> search(String query) async {
    final rawKeyword = query.trim();
    final rawJobs = platforms.map(
      (platform) => _searchPage(query, platform, rawKeyword, 1),
    );
    var candidates = (await Future.wait(
      rawJobs,
    )).expand((batch) => batch).toList();
    candidates.sort((a, b) => b.score.compareTo(a.score));

    if (candidates.isNotEmpty &&
        !_scorer.needsDeepSearch(candidates.first, query)) {
      return candidates.take(40).toList(growable: false);
    }

    final keywords = _scorer
        .buildKeywords(query)
        .where((keyword) => keyword != rawKeyword)
        .toList(growable: false);
    final pageOneJobs = <Future<List<MusicSearchCandidate>>>[];
    for (final platform in platforms) {
      for (final keyword in keywords) {
        pageOneJobs.add(_searchPage(query, platform, keyword, 1));
      }
    }
    if (pageOneJobs.isNotEmpty) {
      candidates = [
        ...candidates,
        ...(await Future.wait(pageOneJobs)).expand((batch) => batch),
      ]..sort((a, b) => b.score.compareTo(a.score));
    }

    final bestPageOne = candidates.isEmpty ? null : candidates.first;
    if (pages > 1 && _scorer.needsDeepSearch(bestPageOne, query)) {
      final promising = candidates
          .take(5)
          .map((candidate) => '${candidate.platform}\t${candidate.keyword}')
          .toSet();
      final deepJobs = <Future<List<MusicSearchCandidate>>>[];
      for (final key in promising) {
        final parts = key.split('\t');
        if (parts.length != 2) {
          continue;
        }
        for (var page = 2; page <= pages; page += 1) {
          deepJobs.add(_searchPage(query, parts[0], parts[1], page));
        }
      }
      if (deepJobs.isNotEmpty) {
        candidates = [
          ...candidates,
          ...(await Future.wait(deepJobs)).expand((batch) => batch),
        ]..sort((a, b) => b.score.compareTo(a.score));
      }
    }

    final seen = <String>{};
    return candidates
        .where((candidate) {
          final key = '${candidate.platform}\t${candidate.id}';
          return seen.add(key);
        })
        .take(40)
        .toList(growable: false);
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return resolveWithPrefer(candidate, prefer: prefer);
  }

  Future<ResolvedMusic> resolveWithPrefer(
    MusicSearchCandidate candidate, {
    required String prefer,
  }) async {
    final qualities = qualityOrder(candidate.qualities, prefer);
    if (qualities.isEmpty) {
      throw StateError('No downloadable quality found');
    }

    final errors = <String>[];
    for (final quality in qualities) {
      final json = await _postFlacApiWithTimeout('getUrl', {
        'platform': candidate.platform,
        'songid': candidate.id,
        'format': quality.format,
        'bitrate': quality.bitrate,
        'time': candidate.raw['time']?.toString() ?? '',
        'sign': candidate.raw['sign']?.toString() ?? '',
      });
      final data = asStringMap(json['data']);
      final url = data['url']?.toString() ?? '';
      if (url.isNotEmpty) {
        final urlType = classifyMediaUrl(url);
        final lyrics = firstResolvedLyrics([
          ..._lyricsFromPayload(data, 'flac:getUrl'),
          ..._lyricsFromPayload(candidate.raw, 'flac:search'),
        ]);
        final coverUrl = _firstText([
          data['picurl'],
          data['pic_url'],
          data['pic'],
          data['cover'],
          data['coverUrl'],
          data['cover_url'],
          data['album_pic'],
          data['albumPic'],
          candidate.coverUrl,
        ]);
        return ResolvedMusic(
          query: candidate.query,
          source: MusicDataSource.flac,
          platform: candidate.platform,
          id: candidate.id,
          name: candidate.name,
          artist: candidate.artist,
          album: candidate.album,
          url: url,
          quality: quality,
          coverUrl: coverUrl,
          lyrics: lyrics,
          duration: candidate.duration,
          urlType: urlType,
          sourceAttempts: [
            _attempt(
              candidate,
              stage: 'resolve',
              status: urlType == MediaUrlType.directAudio
                  ? SourceAttemptStatus.ok
                  : SourceAttemptStatus.failed,
              failureCode: failureCodeForUrlType(urlType),
              mediaUrl: url,
              mediaUrlType: urlType,
              lyricsStatus: lyrics == null ? 'missing' : 'ok',
            ),
          ],
        );
      }
      final msg = json['msg']?.toString();
      if (msg != null && msg.isNotEmpty) {
        errors.add(msg);
      }
    }

    throw SourceDownloadException(
      errors.firstOrNull ?? 'No URL returned',
      failureCode: 'play_url_unavailable',
      sourceAttempts: [
        _attempt(
          candidate,
          stage: 'resolve',
          status: SourceAttemptStatus.failed,
          failureCode: 'play_url_unavailable',
        ),
      ],
    );
  }

  List<ResolvedLyrics?> _lyricsFromPayload(
    Map<String, dynamic> payload,
    String source,
  ) {
    const keys = [
      'lrc',
      'lrcText',
      'lrc_text',
      'lrcContent',
      'lrc_content',
      'lrc_lyric',
      'lyric',
      'lyricText',
      'lyric_text',
      'lyricContent',
      'lyric_content',
      'lyrics',
      'lyricsText',
      'lyrics_text',
      'lyricsContent',
      'lyrics_content',
      'songLyric',
      'song_lyric',
      'content',
      'text',
      'data',
      'about',
    ];
    return [
      for (final key in keys) makeResolvedLyrics(payload[key], '$source:$key'),
      makeResolvedLyrics(payload, '$source:payload'),
    ];
  }

  Future<List<MusicSearchCandidate>> _searchPage(
    String query,
    String platform,
    String keyword,
    int page,
  ) async {
    final json = await _postFlacApiWithTimeout('search', {
      'platform': platform,
      'keyword': keyword,
      'page': '$page',
      'size': '20',
    });
    final data = asStringMap(json['data']);
    final rows = data['list'] is List ? data['list'] as List<dynamic> : [];
    return rows
        .map((row) {
          final item = asStringMap(row);
          final score = _scorer.scoreCandidate(
            item,
            query,
            platform,
            keyword,
            page,
          );
          return candidateFromItem(
            query: query,
            source: MusicDataSource.flac,
            platform: platform,
            keyword: keyword,
            page: page,
            item: item,
            score: score,
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _postFlacApiWithTimeout(
    String act,
    Map<String, String> form,
  ) {
    return _challenge.postFlacApi(act, form).timeout(apiTimeout);
  }
}

SourceAttempt _attempt(
  MusicSearchCandidate candidate, {
  required String stage,
  required SourceAttemptStatus status,
  String failureCode = '',
  String mediaUrl = '',
  MediaUrlType mediaUrlType = MediaUrlType.unknown,
  String lyricsStatus = '',
}) {
  return SourceAttempt(
    query: candidate.query,
    source: MusicDataSource.flac,
    stage: stage,
    status: status,
    failureCode: failureCode,
    candidateId: candidate.id,
    candidateTitle: candidate.name,
    candidateArtist: candidate.artist,
    matchConfidence: candidate.score,
    mediaUrl: mediaUrl,
    mediaUrlType: mediaUrlType,
    lyricsStatus: lyricsStatus,
    coverUrl: candidate.coverUrl,
  );
}

String _firstText(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}
