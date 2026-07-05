// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'lyrics_normalizer.dart';
import 'resolver_candidate_mapper.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

const buguyyHttpsBaseUrl = 'https://buguyy.top';
const buguyyAppleBaseUrl = 'http://buguyy.top';
const buguyyConnectionMessage = 'BuguYY 连接被中断，请稍后重试或检查当前网络/代理。';

String defaultBuguyyBaseUrl({bool? isApplePlatform}) {
  final applePlatform = isApplePlatform ?? (Platform.isIOS || Platform.isMacOS);
  return applePlatform ? buguyyAppleBaseUrl : buguyyHttpsBaseUrl;
}

class BuguyyConnectionException implements Exception {
  const BuguyyConnectionException([this.cause]);

  final Object? cause;

  @override
  String toString() => buguyyConnectionMessage;
}

class BuguyyResolver {
  BuguyyResolver({
    required MusicResolverHttp httpClient,
    CandidateScorer scorer = const CandidateScorer(),
    String? baseUrl,
    bool? useAppleEndpoint,
    this.prefer = 'flac',
    int maxNetworkAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 250),
  }) : baseUrl =
           baseUrl ?? defaultBuguyyBaseUrl(isApplePlatform: useAppleEndpoint),
       _maxNetworkAttempts = max(1, maxNetworkAttempts),
       _retryDelay = retryDelay,
       _http = httpClient,
       _scorer = scorer;

  final MusicResolverHttp _http;
  final CandidateScorer _scorer;
  final String baseUrl;
  final String prefer;
  final int _maxNetworkAttempts;
  final Duration _retryDelay;

  Future<List<MusicSearchCandidate>> search(String query) async {
    final keywords = _scorer.buildKeywords(query);
    final batches = await Future.wait(
      keywords.map((keyword) => _searchKeyword(query, keyword)),
    );
    final seen = <String>{};
    final candidates = <MusicSearchCandidate>[];

    for (final candidate in batches.expand((batch) => batch)) {
      final key = candidate.id.isNotEmpty
          ? candidate.id
          : '${candidate.name}\t${candidate.artist}';
      if (seen.add(key)) {
        candidates.add(candidate);
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(30).toList(growable: false);
  }

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final playJson = await _json('/api/geturl', {'id': candidate.id});
    final directUrl = playJson['success'] == true
        ? playJson['url']?.toString() ?? ''
        : '';
    final lyrics = _chooseLyrics(playJson, candidate.raw);

    if (directUrl.isNotEmpty) {
      final extension = urlExtension(directUrl).replaceFirst('.', '');
      final urlType = classifyMediaUrl(directUrl);
      return ResolvedMusic(
        query: candidate.query,
        source: MusicDataSource.buguyy,
        platform: 'buguyy',
        id: candidate.id,
        name: playJson['name']?.toString().trim().isNotEmpty == true
            ? playJson['name'].toString()
            : candidate.name,
        artist: candidate.artist,
        album: '',
        url: directUrl,
        quality: MusicQuality(format: extension.isEmpty ? 'mp3' : extension),
        coverUrl: candidate.coverUrl,
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
            mediaUrl: directUrl,
            mediaUrlType: urlType,
            lyricsStatus: lyrics == null ? 'missing' : 'ok',
          ),
        ],
      );
    }

    final downJson = await _json('/api/getdown', {'id': candidate.id});
    if (downJson['success'] != true) {
      throw StateError(
        downJson['message']?.toString() ?? 'buguyy no URL returned',
      );
    }

    final downloadUrls = _parseDownloadUrls(
      downJson['kuakedownurl'] ??
          downJson['data'] ??
          downJson['downloadUrls'] ??
          downJson['url'] ??
          '',
    );
    final chosen = _chooseDownload(downloadUrls, prefer);
    if (chosen == null) {
      throw StateError('buguyy no downloadable URL returned');
    }
    final chosenUrlType = classifyMediaUrl(chosen.value);
    final resolvedLyrics =
        lyrics ??
        firstResolvedLyrics([
          makeResolvedLyrics(downJson['lrc'], 'buguyy:getdown:lrc'),
          makeResolvedLyrics(downJson['lyric'], 'buguyy:getdown:lyric'),
          makeResolvedLyrics(downJson['about'], 'buguyy:getdown:about'),
        ]);

    return ResolvedMusic(
      query: candidate.query,
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: candidate.id,
      name: downJson['title']?.toString().trim().isNotEmpty == true
          ? downJson['title'].toString()
          : candidate.name,
      artist: downJson['singer']?.toString().trim().isNotEmpty == true
          ? downJson['singer'].toString()
          : candidate.artist,
      album: '',
      url: chosen.value,
      quality: MusicQuality(format: chosen.key),
      coverUrl: candidate.coverUrl,
      lyrics: resolvedLyrics,
      panLink: chosenUrlType == MediaUrlType.externalPan,
      duration: candidate.duration,
      urlType: chosenUrlType,
      sourceAttempts: [
        _attempt(
          candidate,
          stage: 'resolve',
          status: chosenUrlType == MediaUrlType.directAudio
              ? SourceAttemptStatus.ok
              : SourceAttemptStatus.skipped,
          failureCode: failureCodeForUrlType(chosenUrlType),
          mediaUrl: chosen.value,
          mediaUrlType: chosenUrlType,
          lyricsStatus: resolvedLyrics == null ? 'missing' : 'ok',
        ),
      ],
    );
  }

  Future<List<MusicSearchCandidate>> _searchKeyword(
    String query,
    String keyword,
  ) async {
    final json = await _json('/api/search', {'keyword': keyword});
    final rows = json['data'] is List ? json['data'] as List<dynamic> : [];
    return rows
        .map((row) {
          final item = normalizeBuguyySong(asStringMap(row));
          final score = _scorer.scoreCandidate(
            item,
            query,
            'buguyy',
            keyword,
            1,
          );
          return candidateFromItem(
            query: query,
            source: MusicDataSource.buguyy,
            platform: 'buguyy',
            keyword: keyword,
            page: 1,
            item: item,
            score: score,
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _json(
    String pathname,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$baseUrl$pathname').replace(
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      },
    );
    final response = await getBuguyyWithRetry(
      _http,
      uri,
      headers: {
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9',
        'referer': '$baseUrl/',
        'user-agent': ChallengeClient.userAgent,
      },
      maxAttempts: _maxNetworkAttempts,
      retryDelay: _retryDelay,
    );
    final decoded = _decodeJson(response, label: 'buguyy');
    if (!response.ok) {
      throw HttpException(
        'buguyy HTTP ${response.statusCode}: '
        '${decoded['message'] ?? response.body.substring(0, min(160, response.body.length))}',
        uri: uri,
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decodeJson(
    ResolverHttpResponse response, {
    required String label,
  }) {
    try {
      return asStringMap(jsonDecode(response.body));
    } catch (_) {
      throw FormatException(
        '$label non-JSON response ${response.statusCode}: '
        '${prefix(response.body)}',
      );
    }
  }
}

SourceAttempt _attempt(
  MusicSearchCandidate candidate, {
  required String stage,
  required SourceAttemptStatus status,
  String failureCode = '',
  String mediaUrl = '',
  MediaUrlType mediaUrlType = MediaUrlType.unknown,
  String mediaContentType = '',
  int? mediaContentLength,
  String lyricsStatus = '',
}) {
  return SourceAttempt(
    query: candidate.query,
    source: MusicDataSource.buguyy,
    stage: stage,
    status: status,
    failureCode: failureCode,
    candidateId: candidate.id,
    candidateTitle: candidate.name,
    candidateArtist: candidate.artist,
    matchConfidence: candidate.score,
    mediaUrl: mediaUrl,
    mediaUrlType: mediaUrlType,
    mediaContentType: mediaContentType,
    mediaContentLength: mediaContentLength,
    lyricsStatus: lyricsStatus,
    coverUrl: candidate.coverUrl,
  );
}

Future<ResolverHttpResponse> getBuguyyWithRetry(
  MusicResolverHttp httpClient,
  Uri uri, {
  required Map<String, String> headers,
  int maxAttempts = 3,
  Duration retryDelay = const Duration(milliseconds: 250),
}) async {
  final attempts = max(1, maxAttempts);
  Object? lastError;
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await httpClient.get(
        uri,
        headers: {...headers, if (attempt > 0) 'connection': 'close'},
      );
    } catch (error) {
      if (!isTransientBuguyyNetworkError(error)) {
        rethrow;
      }
      lastError = error;
      if (attempt == attempts - 1) {
        throw BuguyyConnectionException(lastError);
      }
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(
          Duration(milliseconds: retryDelay.inMilliseconds * (attempt + 1)),
        );
      }
    }
  }
  throw BuguyyConnectionException(lastError);
}

bool isTransientBuguyyNetworkError(Object error) {
  if (error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException) {
    return true;
  }
  final text = formatResolverError(error).toLowerCase();
  return text.contains('handshakeconnection terminated') ||
      text.contains('terminated during handshake') ||
      text.contains('closed before full header') ||
      text.contains('connection closed before') ||
      text.contains('empty reply') ||
      text.contains('connection reset') ||
      text.contains('connection abort');
}

ResolvedLyrics? _chooseLyrics(
  Map<String, dynamic> playJson,
  Map<String, dynamic> item,
) {
  return firstResolvedLyrics([
    makeResolvedLyrics(playJson['lrc'], 'buguyy:geturl:lrc'),
    makeResolvedLyrics(playJson['lyric'], 'buguyy:geturl:lyric'),
    makeResolvedLyrics(
      asStringMap(item['raw'])['about'],
      'buguyy:search:about',
    ),
    makeResolvedLyrics(item['about'], 'buguyy:search:about'),
  ]);
}

Map<String, String> _parseDownloadUrls(Object? value) {
  final urls = <String, String>{};
  if (value is String) {
    for (final part in value.split('###')) {
      if (!part.contains('#')) {
        continue;
      }
      final index = part.indexOf('#');
      final label = part.substring(0, index).trim();
      final url = part.substring(index + 1).trim();
      if (label.isNotEmpty && url.isNotEmpty) {
        urls[label.toLowerCase()] = url;
      }
    }
  } else if (value is Map) {
    for (final entry in value.entries) {
      final url = entry.value?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        urls[entry.key.toString().toLowerCase()] = url;
      }
    }
  }
  return urls;
}

MapEntry<String, String>? _chooseDownload(
  Map<String, String> urls,
  String prefer,
) {
  if (urls.isEmpty) {
    return null;
  }
  final order = [
    prefer,
    'flac',
    '【hi-res】wav',
    'hi-res',
    'wav',
    'ape',
    'mp3',
  ].map((value) => value.toLowerCase());
  for (final wanted in order) {
    for (final entry in urls.entries) {
      if (entry.key.contains(wanted)) {
        return entry;
      }
    }
  }
  return urls.entries.first;
}
