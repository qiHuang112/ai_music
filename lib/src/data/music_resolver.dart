export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'gequhai_player_audio_resolver.dart';
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
import 'gequhai_player_audio_resolver.dart';
import 'itunes_preview_resolver.dart';
import 'kuwo_full_audio_resolver.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';
import 'source_22a5_resolver.dart';

class RemoteMusicResolver
    implements
        MusicResolver,
        PreferredMusicResolver,
        ProgressiveMusicResolver,
        PaginatedProgressiveMusicResolver {
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
    _gequhai = GequhaiPlayerAudioResolver(httpClient: http);
    _kuwoFullAudio = KuwoFullAudioResolver(httpClient: http, scorer: scorer);
    _itunesPreview = ItunesPreviewResolver(httpClient: http, scorer: scorer);
  }

  final String _prefer;
  late final BuguyyResolver _buguyy;
  late final FlacResolver _flac;
  late final Source22a5Resolver _source22a5;
  late final GequhaiPlayerAudioResolver _gequhai;
  late final KuwoFullAudioResolver _kuwoFullAudio;
  late final ItunesPreviewResolver _itunesPreview;
  DateTime? _gequhaiRetryAfter;
  String _activeAutoQuery = '';
  MusicDataSource? _activeAutoSource;

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
      MusicDataSource.source2t58 => await _unsupportedFullAudioSource(
        trimmed,
        MusicDataSource.source2t58,
        failureCode: 'security_verification',
      ),
      MusicDataSource.source22a5 => await _source22a5.search(trimmed),
      MusicDataSource.gequhai => await _gequhai.search(trimmed),
      MusicDataSource.gequbao => await _unsupportedFullAudioSource(
        trimmed,
        MusicDataSource.gequbao,
        failureCode: 'security_verification',
      ),
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
    yield* searchPageProgressively(query, source, page: 1);
  }

  @override
  Stream<MusicSearchProgress> searchPageProgressively(
    String query,
    MusicDataSource source, {
    required int page,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
      );
      return;
    }
    if (source == MusicDataSource.auto) {
      yield* _searchAutoPageProgressively(trimmed, page: page);
      return;
    }
    if (source == MusicDataSource.gequhai) {
      _logResolver(
        '[AI Music][resolver] search query="$trimmed" '
        'source=${source.storageValue} page=$page',
      );
      await for (final progress in _gequhai.searchPageProgressively(
        trimmed,
        page: page,
      )) {
        if (progress.isComplete) {
          _logResolver(
            '[AI Music][resolver] search done query="$trimmed" '
            'source=${source.storageValue} page=$page '
            'count=${progress.candidates.length} '
            'hasNextPage=${progress.hasNextPage}',
          );
        }
        yield progress;
      }
      return;
    }
    if (page > 1) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
      );
      return;
    }
    try {
      final result = await search(trimmed, source);
      yield MusicSearchProgress(
        candidates: result,
        isComplete: true,
        page: page,
      );
    } catch (error) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        error: error,
      );
    }
  }

  Stream<MusicSearchProgress> _searchAutoPageProgressively(
    String query, {
    required int page,
  }) async* {
    if (page == 1 || _activeAutoQuery != query) {
      _activeAutoQuery = query;
      _activeAutoSource = null;
    }
    _logResolver(
      '[AI Music][resolver] search query="$query" source=auto page=$page',
    );

    Object? gequhaiError;
    final retryAfter = _gequhaiRetryAfter;
    final gequhaiCircuitOpen =
        retryAfter != null && DateTime.now().isBefore(retryAfter);
    final shouldTryGequhai =
        _activeAutoSource != MusicDataSource.kuwoFullAudio &&
        !gequhaiCircuitOpen;
    if (shouldTryGequhai) {
      try {
        await for (final progress in _gequhai.searchPageProgressively(
          query,
          page: page,
        )) {
          yield progress;
          if (progress.isComplete && progress.candidates.isNotEmpty) {
            _activeAutoSource = MusicDataSource.gequhai;
            _gequhaiRetryAfter = null;
            return;
          }
        }
      } catch (error) {
        gequhaiError = error;
        _gequhaiRetryAfter = DateTime.now().add(const Duration(minutes: 2));
        _logResolver(
          '[AI Music][resolver] auto gequhai failed query="$query" '
          'page=$page error=${formatResolverError(error)}',
        );
      }
    }

    _activeAutoSource = MusicDataSource.kuwoFullAudio;
    var fallbackReady = false;
    Object? fallbackError;
    try {
      await for (final progress in _kuwoFullAudio.searchPageProgressively(
        query,
        page: page,
      )) {
        if (progress.isComplete) {
          fallbackReady = progress.candidates.isNotEmpty;
          fallbackError = progress.error;
        }
        yield progress;
      }
    } catch (error) {
      fallbackError = error;
    }
    if (!fallbackReady && (fallbackError != null || gequhaiError != null)) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        error: _autoFallbackError(
          gequhaiError: gequhaiError,
          kuwoError: fallbackError,
        ),
      );
    }
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
      MusicDataSource.source2t58 => _unsupportedResolve(candidate),
      MusicDataSource.source22a5 => _source22a5.resolve(candidate),
      MusicDataSource.gequhai => _gequhai.resolve(candidate),
      MusicDataSource.gequbao => _unsupportedResolve(candidate),
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
    var candidates = const <MusicSearchCandidate>[];
    Object? error;
    await for (final progress in _searchAutoPageProgressively(query, page: 1)) {
      if (progress.isComplete) {
        candidates = progress.candidates;
        error = progress.error;
      }
    }
    if (candidates.isNotEmpty) {
      return candidates;
    }
    if (error != null) {
      throw error;
    }
    return const [];
  }
}

Future<List<MusicSearchCandidate>> _unsupportedFullAudioSource(
  String query,
  MusicDataSource source, {
  required String failureCode,
}) {
  return Future.error(
    SourceDownloadException(
      _messageForFailureCode(failureCode),
      failureCode: failureCode,
      sourceAttempts: [
        SourceAttempt(
          query: query,
          source: source,
          stage: 'search',
          status: SourceAttemptStatus.failed,
          failureCode: failureCode,
          reasonCode: 'full_audio_unavailable',
          mediaUrlType: MediaUrlType.htmlPage,
          clientReady: false,
          mediaValidation: 'no client-ready direct audio for full download',
        ),
      ],
    ),
  );
}

Future<ResolvedMusic> _unsupportedResolve(MusicSearchCandidate candidate) {
  return Future.error(
    SourceDownloadException(
      _messageForFailureCode('full_audio_unavailable'),
      failureCode: 'full_audio_unavailable',
      sourceAttempts: [
        SourceAttempt(
          query: candidate.query,
          source: candidate.source,
          stage: 'resolve',
          status: SourceAttemptStatus.failed,
          failureCode: 'full_audio_unavailable',
          reasonCode: 'full_audio_unavailable',
          candidateId: candidate.id,
          candidateTitle: candidate.name,
          candidateArtist: candidate.artist,
          matchConfidence: candidate.score,
          clientReady: false,
          mediaValidation: 'no client-ready direct audio for full download',
        ),
      ],
    ),
  );
}

StateError _autoFallbackError({Object? gequhaiError, Object? kuwoError}) {
  final messages = <String>[
    if (gequhaiError != null)
      'gequhai failed: ${formatResolverError(gequhaiError)}',
    if (kuwoError != null)
      'kuwo full audio failed: ${formatResolverError(kuwoError)}',
  ];
  return StateError(messages.join('; '));
}

void _logResolver(String message) {
  developer.log(message, name: 'ai_music.resolver');
  // ignore: avoid_print
  print(message);
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
    'security_verification' => '源站进入安全验证页，暂时不能自动下载完整音频。',
    'security_or_forbidden' => '源站返回 403 或安全防护页，未暴露完整音频直链。',
    'defender_challenge' => '源站防护拦截，暂时无法解析直链。',
    'anticc_non_json' => '源站返回防护页面，不是可解析的歌曲数据。',
    'no_trusted_artist_title_match' => '未找到可信的同名同歌手下载候选。',
    'non_audio_content' => '下载链接返回的不是音频内容。',
    'preview_audio_available' => '当前仅支持试听，无法缓存为完整歌曲。',
    'full_audio_unavailable' => '当前源没有可下载的完整音频直链。',
    'network_timeout' => '源站响应超时，请稍后再试。',
    'direct_url_expired' => '音频直链已失效，请重新搜索。',
    _ => '暂时没有可下载的音频直链。',
  };
}
