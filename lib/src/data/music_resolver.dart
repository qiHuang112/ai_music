export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'itunes_preview_resolver.dart';
export 'kuwo_full_audio_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';
export 'source_22a5_resolver.dart';

import 'dart:async';
import 'dart:developer' as developer;

import 'buguyy_resolver.dart';
import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'flac_resolver.dart';
import 'itunes_preview_resolver.dart';
import 'kuwo_full_audio_resolver.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';
import 'source_22a5_resolver.dart';

const bool _enableSource22a5Auto = bool.fromEnvironment(
  'AI_MUSIC_ENABLE_22A5_AUTO',
);

class RemoteMusicResolver
    implements MusicResolver, PreferredMusicResolver, ProgressiveMusicResolver {
  RemoteMusicResolver({
    MusicResolverHttp? httpClient,
    String? initialFlacCookie,
    int pages = 8,
    List<String> platforms = const ['kuwo', 'wyy'],
    String prefer = 'flac',
    bool? useAppleBuguyyEndpoint,
  }) : _prefer = prefer {
    final http = httpClient ?? HttpMusicResolverClient();
    const scorer = CandidateScorer();
    _buguyy = BuguyyResolver(
      httpClient: http,
      scorer: scorer,
      prefer: prefer,
      useAppleEndpoint: useAppleBuguyyEndpoint,
    );
    _flac = FlacResolver(
      challengeClient: ChallengeClient(
        httpClient: http,
        initialCookie: initialFlacCookie ?? '',
      ),
      scorer: scorer,
      pages: pages,
      platforms: platforms,
      prefer: prefer,
    );
    _source22a5 = Source22a5Resolver(httpClient: http, scorer: scorer);
    _kuwoFullAudio = KuwoFullAudioResolver(httpClient: http, scorer: scorer);
    _itunesPreview = ItunesPreviewResolver(httpClient: http, scorer: scorer);
  }

  final String _prefer;
  late final BuguyyResolver _buguyy;
  late final FlacResolver _flac;
  late final Source22a5Resolver _source22a5;
  late final KuwoFullAudioResolver _kuwoFullAudio;
  late final ItunesPreviewResolver _itunesPreview;

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    _logResolver(
      '[AI Music][resolver] search query="$trimmed" source=${source.storageValue}',
    );
    final result = switch (source) {
      MusicDataSource.buguyy => await _buguyy.search(trimmed),
      MusicDataSource.flac => await _flac.search(trimmed),
      MusicDataSource.source22a5 => await _source22a5.search(trimmed),
      MusicDataSource.kuwoFullAudio => await _kuwoFullAudio.search(trimmed),
      MusicDataSource.itunesPreview => await _itunesPreview.search(trimmed),
      MusicDataSource.auto => await _searchAuto(trimmed),
    };
    _logResolver(
      '[AI Music][resolver] search done query="$trimmed" '
      'source=${source.storageValue} count=${result.length} '
      'candidateSources=${result.map((c) => c.source.storageValue).toSet().join(",")}',
    );
    return result;
  }

  @override
  Stream<MusicSearchProgress> searchProgressively(
    String query,
    MusicDataSource source,
  ) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      yield const MusicSearchProgress(candidates: [], isComplete: true);
      return;
    }
    if (source != MusicDataSource.auto) {
      try {
        final result = await search(trimmed, source);
        yield MusicSearchProgress(candidates: result, isComplete: true);
      } catch (error) {
        yield MusicSearchProgress(
          candidates: const [],
          isComplete: true,
          error: error,
        );
      }
      return;
    }

    _logResolver(
      '[AI Music][resolver] search query="$trimmed" source=${source.storageValue}',
    );
    final stream = StreamController<MusicSearchProgress>();
    final merged = <MusicSearchCandidate>[];
    final errors = <Object>[];
    var remaining = _enableSource22a5Auto ? 5 : 4;

    void handleResult(_AutoSourceResult result) {
      remaining -= 1;
      if (result.error != null) {
        errors.add(result.error!);
      }
      if (result.candidates.isNotEmpty) {
        _appendStableCandidates(merged, result.candidates);
      }
      final isComplete = remaining == 0;
      if (isComplete) {
        _logResolver(
          '[AI Music][resolver] search done query="$trimmed" '
          'source=${source.storageValue} count=${merged.length} '
          'candidateSources=${merged.map((c) => c.source.storageValue).toSet().join(",")}',
        );
      }
      stream.add(
        MusicSearchProgress(
          candidates: List<MusicSearchCandidate>.unmodifiable(merged),
          isComplete: isComplete,
          error: isComplete && merged.isEmpty && errors.isNotEmpty
              ? _combinedAutoError(errors)
              : null,
        ),
      );
      if (isComplete) {
        unawaited(stream.close());
      }
    }

    unawaited(
      _searchAutoSource(
        trimmed,
        MusicDataSource.buguyy,
        _buguyy.search,
      ).then(handleResult),
    );
    unawaited(
      _searchAutoSource(
        trimmed,
        MusicDataSource.flac,
        _flac.search,
      ).then(handleResult),
    );
    if (_enableSource22a5Auto) {
      unawaited(
        _searchAutoSource(
          trimmed,
          MusicDataSource.source22a5,
          _source22a5.search,
        ).then(handleResult),
      );
    }
    unawaited(
      _searchAutoSource(
        trimmed,
        MusicDataSource.kuwoFullAudio,
        _kuwoFullAudio.search,
      ).then(handleResult),
    );
    unawaited(
      _searchAutoSource(
        trimmed,
        MusicDataSource.itunesPreview,
        _itunesPreview.search,
      ).then(handleResult),
    );
    yield* stream.stream;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return resolveWithPrefer(candidate, prefer: _prefer);
  }

  @override
  Future<ResolvedMusic> resolveWithPrefer(
    MusicSearchCandidate candidate, {
    required String prefer,
  }) async {
    final resolved = await switch (candidate.source) {
      MusicDataSource.buguyy => _resolveBuguyyWithFallback(
        candidate,
        prefer: prefer,
      ),
      MusicDataSource.flac => _flac.resolveWithPrefer(
        candidate,
        prefer: prefer,
      ),
      MusicDataSource.source22a5 => _source22a5.resolve(candidate),
      MusicDataSource.kuwoFullAudio => _kuwoFullAudio.resolve(candidate),
      MusicDataSource.itunesPreview => _itunesPreview.resolve(candidate),
      MusicDataSource.auto => throw StateError(
        'Auto candidates must be tagged with their concrete source.',
      ),
    };
    _logResolver(
      '[AI Music][resolver] resolve done '
      'source=${resolved.source.storageValue} platform=${resolved.platform} '
      'name="${resolved.name}" artist="${resolved.artist}" '
      'hasCover=${resolved.coverUrl.trim().isNotEmpty} '
      'hasLyrics=${resolved.lyrics?.text.trim().isNotEmpty ?? false}',
    );
    return resolved;
  }

  Future<ResolvedMusic> _resolveBuguyyWithFallback(
    MusicSearchCandidate candidate, {
    required String prefer,
  }) async {
    final buguyy = await _buguyy.resolveWithPrefer(candidate, prefer: prefer);
    if (buguyy.urlType == MediaUrlType.directAudio) {
      return buguyy;
    }

    Object? flacError;
    final flacAttempts = <SourceAttempt>[];
    try {
      final flacCandidates = await _flac.search(candidate.query);
      for (final flacCandidate in flacCandidates.take(3)) {
        if (!_isTrustedFallbackCandidate(flacCandidate, candidate)) {
          flacAttempts.add(
            _fallbackAttempt(
              flacCandidate,
              candidate,
              status: SourceAttemptStatus.skipped,
              failureCode: 'no_trusted_artist_title_match',
            ),
          );
          continue;
        }
        final resolved = await _flac.resolveWithPrefer(
          flacCandidate,
          prefer: prefer,
        );
        if (resolved.urlType == MediaUrlType.directAudio) {
          return resolved.copyWith(
            sourceAttempts: [
              ...buguyy.sourceAttempts,
              ...flacAttempts,
              ...resolved.sourceAttempts,
            ],
          );
        }
      }
      if (flacAttempts.isNotEmpty) {
        flacError = SourceDownloadException(
          '未找到可信的同名同歌手 FLAC fallback 候选。',
          failureCode: 'no_trusted_artist_title_match',
          sourceAttempts: flacAttempts,
        );
      }
    } catch (error) {
      flacError = error;
    }

    final buguyyCode = buguyy.sourceAttempts
        .map((attempt) => attempt.failureCode)
        .firstWhere((code) => code.isNotEmpty, orElse: () => '');
    final flacCode = _failureCodeForResolverError(flacError);
    throw SourceDownloadException(
      _messageForFailureCode(buguyyCode.isNotEmpty ? buguyyCode : flacCode),
      failureCode: buguyyCode.isNotEmpty ? buguyyCode : flacCode,
      sourceAttempts: [
        ...buguyy.sourceAttempts,
        if (flacError is SourceDownloadException &&
            flacError.sourceAttempts.isNotEmpty)
          ...flacError.sourceAttempts
        else if (flacError != null)
          SourceAttempt(
            query: candidate.query,
            source: MusicDataSource.flac,
            stage: 'search',
            status: SourceAttemptStatus.failed,
            failureCode: flacCode,
            candidateId: candidate.id,
            candidateTitle: candidate.name,
            candidateArtist: candidate.artist,
            matchConfidence: candidate.score,
          ),
      ],
    );
  }

  Future<List<MusicSearchCandidate>> _searchAuto(String query) async {
    final buguyyFuture = _searchAutoSource(
      query,
      MusicDataSource.buguyy,
      _buguyy.search,
    );
    final flacFuture = _searchAutoSource(
      query,
      MusicDataSource.flac,
      _flac.search,
    );
    final kuwoFuture = _searchAutoSource(
      query,
      MusicDataSource.kuwoFullAudio,
      _kuwoFullAudio.search,
    );
    final Future<_AutoSourceResult> source22a5Future = _enableSource22a5Auto
        ? _searchAutoSource(
            query,
            MusicDataSource.source22a5,
            _source22a5.search,
          )
        : Future.value(const _AutoSourceResult());
    final itunesFuture = _searchAutoSource(
      query,
      MusicDataSource.itunesPreview,
      _itunesPreview.search,
    );
    final results = await Future.wait([
      buguyyFuture,
      flacFuture,
      kuwoFuture,
      source22a5Future,
      itunesFuture,
    ]);
    final buguyy = results[0];
    final flac = results[1];
    final kuwo = results[2];
    final source22a5 = results[3];
    final itunes = results[4];
    final merged = [
      ...buguyy.candidates,
      ...flac.candidates,
      ...kuwo.candidates,
      ...source22a5.candidates,
      ...itunes.candidates,
    ]..sort((a, b) => b.score.compareTo(a.score));
    _logResolver(
      '[AI Music][resolver] auto merged query="$query" '
      'buguyy=${buguyy.candidates.length} flac=${flac.candidates.length} '
      'kuwoFullAudio=${kuwo.candidates.length} '
      'source22a5=${source22a5.candidates.length} '
      'itunesPreview=${itunes.candidates.length} count=${merged.length}',
    );
    if (merged.isNotEmpty) {
      return merged.take(80).toList(growable: false);
    }
    if (buguyy.error != null &&
        flac.error != null &&
        kuwo.error != null &&
        source22a5.error != null &&
        itunes.error != null) {
      throw _combinedAutoError([
        buguyy.error!,
        flac.error!,
        kuwo.error!,
        source22a5.error!,
        itunes.error!,
      ]);
    }
    final error =
        buguyy.error ??
        flac.error ??
        kuwo.error ??
        source22a5.error ??
        itunes.error;
    if (error != null) {
      throw StateError(formatResolverError(error));
    }
    return const [];
  }
}

void _appendStableCandidates(
  List<MusicSearchCandidate> target,
  List<MusicSearchCandidate> incoming,
) {
  final seen = {
    for (final candidate in target)
      '${candidate.source.storageValue}\t${candidate.platform}\t${candidate.id}',
  };
  for (final candidate in incoming) {
    final key =
        '${candidate.source.storageValue}\t${candidate.platform}\t${candidate.id}';
    if (seen.add(key)) {
      target.add(candidate);
    }
  }
}

StateError _combinedAutoError(List<Object> errors) {
  if (errors.length <= 1) {
    return StateError(formatResolverError(errors.single));
  }
  return StateError(
    [
      'buguyy failed: ${formatResolverError(errors[0])}',
      'flac failed: ${formatResolverError(errors[1])}',
      if (errors.length > 2)
        'source 22a5 failed: ${formatResolverError(errors[2])}',
      if (errors.length > 3)
        'itunes preview failed: ${formatResolverError(errors[3])}',
    ].join('; '),
  );
}

void _logResolver(String message) {
  developer.log(message, name: 'ai_music.resolver');
  // ignore: avoid_print
  print(message);
}

Future<_AutoSourceResult> _searchAutoSource(
  String query,
  MusicDataSource source,
  Future<List<MusicSearchCandidate>> Function(String query) search,
) async {
  try {
    final candidates = await search(query);
    _logResolver(
      '[AI Music][resolver] auto ${source.storageValue} query="$query" '
      'count=${candidates.length}',
    );
    return _AutoSourceResult(candidates: candidates);
  } catch (error) {
    _logResolver(
      '[AI Music][resolver] auto ${source.storageValue} failed query="$query" '
      'error=${formatResolverError(error)}',
    );
    return _AutoSourceResult(error: error);
  }
}

class _AutoSourceResult {
  const _AutoSourceResult({this.candidates = const [], this.error});

  final List<MusicSearchCandidate> candidates;
  final Object? error;
}

bool _isTrustedFallbackCandidate(
  MusicSearchCandidate flacCandidate,
  MusicSearchCandidate buguyyCandidate,
) {
  if (flacCandidate.score < 120) {
    return false;
  }
  final query = _fallbackMatchQuery(buguyyCandidate);
  return isLooseArtistTitleCandidate(flacCandidate, query);
}

String _fallbackMatchQuery(MusicSearchCandidate candidate) {
  final artist = candidate.artist.trim();
  final name = candidate.name.trim();
  if (artist.isNotEmpty && name.isNotEmpty) {
    return '$artist $name';
  }
  return candidate.query;
}

SourceAttempt _fallbackAttempt(
  MusicSearchCandidate flacCandidate,
  MusicSearchCandidate buguyyCandidate, {
  required SourceAttemptStatus status,
  required String failureCode,
}) {
  return SourceAttempt(
    query: buguyyCandidate.query,
    source: MusicDataSource.flac,
    stage: 'match',
    status: status,
    failureCode: failureCode,
    candidateId: flacCandidate.id,
    candidateTitle: flacCandidate.name,
    candidateArtist: flacCandidate.artist,
    matchConfidence: flacCandidate.score,
    mediaUrlType: MediaUrlType.unknown,
    coverUrl: flacCandidate.coverUrl,
  );
}

String _failureCodeForResolverError(Object? error) {
  if (error == null) {
    return 'play_url_unavailable';
  }
  if (error is TimeoutException) {
    return 'network_timeout';
  }
  if (error is SourceDownloadException && error.failureCode.isNotEmpty) {
    return error.failureCode;
  }
  final text = formatResolverError(error).toLowerCase();
  if (text.contains('safeline') || text.contains('challenge')) {
    return 'defender_challenge';
  }
  if (text.contains('html') ||
      text.contains('format') ||
      text.contains('non-json') ||
      (text.contains('non') && text.contains('json'))) {
    return 'anticc_non_json';
  }
  if (text.contains('timed out') || text.contains('timeout')) {
    return 'network_timeout';
  }
  return 'play_url_unavailable';
}

String _messageForFailureCode(String failureCode) {
  return switch (failureCode) {
    'search_no_result' => '未找到可下载的歌曲结果。',
    'external_pan_link' => '源站只提供网盘链接，已跳过音频下载。',
    'defender_challenge' => '源站防护拦截，暂时无法解析直链。',
    'anticc_non_json' => '源站返回防护页面，不是可解析的歌曲数据。',
    'no_trusted_artist_title_match' => '未找到可信的同名同歌手下载候选。',
    'non_audio_content' => '下载链接返回的不是音频内容。',
    'preview_audio_available' => '当前仅支持试听，无法缓存为完整歌曲。',
    'network_timeout' => '源站响应超时，请稍后再试。',
    'direct_url_expired' => '音频直链已失效，请重新搜索。',
    _ => '暂时没有可下载的音频直链。',
  };
}
