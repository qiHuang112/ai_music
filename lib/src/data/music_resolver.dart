export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';

import 'dart:async';
import 'dart:developer' as developer;

import 'auto_source_health.dart';
import 'buguyy_resolver.dart';
import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'flac_resolver.dart';
import 'lyrics_normalizer.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class RemoteMusicResolver
    implements
        MusicResolver,
        QualitySelectableMusicResolver,
        AutoSourceHealthResolver,
        ProgressiveMusicResolver,
        ScreenshotSearchResolver,
        StagedScreenshotSearchResolver {
  RemoteMusicResolver({
    MusicResolverHttp? httpClient,
    String? initialFlacCookie,
    int pages = 8,
    List<String> platforms = const ['kuwo', 'wyy'],
    String prefer = 'flac',
    bool? useAppleBuguyyEndpoint,
  }) {
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
  }

  late final BuguyyResolver _buguyy;
  late final FlacResolver _flac;
  final _sourceHealth = AutoSourceHealth();

  @override
  List<MusicDataSource> get availableAutoSources =>
      _sourceHealth.availableSources;

  @override
  bool isSourceAvailableForAuto(MusicDataSource source) =>
      _sourceHealth.isAvailable(source);

  @override
  String? sourceDegradationReason(MusicDataSource source) =>
      _sourceHealth.degradationReason(source);

  @override
  void reportSourceFailure(MusicDataSource source, Object error) =>
      _sourceHealth.recordFailure(
        source,
        error,
        operation: AutoSourceOperation.media,
      );

  @override
  void reportSourceSuccess(MusicDataSource source) =>
      _sourceHealth.recordSuccess(source, operation: AutoSourceOperation.media);

  @override
  Future<List<MusicSearchCandidate>> searchScreenshot(
    String title,
    String artist,
  ) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    Object? firstFailure;
    var candidates = <MusicSearchCandidate>[];
    try {
      candidates = await searchScreenshotPrimary(query);
    } catch (error) {
      firstFailure = error;
    }
    if (candidates.isNotEmpty) return candidates;
    try {
      return [...candidates, ...await searchScreenshotFallback(query, artist)];
    } catch (_) {
      if (candidates.isNotEmpty) return candidates;
      if (firstFailure != null) throw firstFailure;
      rethrow;
    }
  }

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotPrimary(String title) =>
      _searchScreenshotSource(
        title,
        MusicDataSource.buguyy,
        _buguyy.searchSingleKeyword,
      );

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotFallback(
    String title,
    String artist,
  ) => _searchScreenshotSource(
    title,
    MusicDataSource.flac,
    (query) => _flac.searchFirstPages(query, stopAfterPage: (_) => true),
  );

  Future<List<MusicSearchCandidate>> _searchScreenshotSource(
    String title,
    MusicDataSource source,
    Future<List<MusicSearchCandidate>> Function(String) action,
  ) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    if (!isSourceAvailableForAuto(source)) return const [];
    try {
      return await _sourceHealth.run(
        source,
        () => action(query),
        automatic: true,
      );
    } on AutoSourceUnavailableException {
      // The circuit can open while this song waits behind another search.
      return const [];
    }
  }

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
      MusicDataSource.buguyy => await _sourceHealth.run(
        source,
        () => _buguyy.search(trimmed),
        automatic: false,
      ),
      MusicDataSource.flac => await _sourceHealth.run(
        source,
        () => _flac.search(trimmed),
        automatic: false,
      ),
      MusicDataSource.auto => await _searchAuto(trimmed),
      MusicDataSource.lan => throw UnsupportedError(
        'LAN is a cache provenance and cannot be searched online.',
      ),
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
    final merged = <MusicSearchCandidate>[];
    final errors = <Object>[];
    final sources = availableAutoSources;
    if (sources.isEmpty) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        error: _noAvailableAutoSourceError(),
      );
      return;
    }
    var cancelled = false;
    final stream = StreamController<MusicSearchProgress>(
      onCancel: () => cancelled = true,
    );
    var remaining = sources.length;

    void handleResult(_AutoSourceResult result) {
      remaining -= 1;
      if (cancelled) {
        if (remaining == 0) unawaited(stream.close());
        return;
      }
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

    for (final source in sources) {
      unawaited(
        _searchAutoSource(
          trimmed,
          source,
          isCancelled: () => cancelled,
        ).then(handleResult),
      );
    }
    yield* stream.stream;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      _resolveWithPreference(candidate, null);

  @override
  Future<ResolvedMusic> resolveAtQuality(
    MusicSearchCandidate candidate,
    MusicQualityLevel level,
  ) => _resolveWithPreference(candidate, level.resolverPreference);

  @override
  Future<ResolvedMusic> resolveForSourceMode(
    MusicSearchCandidate candidate,
    MusicDataSource mode, {
    MusicQualityLevel? quality,
  }) => _resolveWithPreference(
    candidate,
    quality?.resolverPreference,
    automatic: mode == MusicDataSource.auto,
  );

  Future<ResolvedMusic> _resolveWithPreference(
    MusicSearchCandidate candidate,
    String? qualityPreference, {
    bool automatic = false,
  }) async {
    final resolved = await switch (candidate.source) {
      MusicDataSource.buguyy => _resolveBuguyy(
        candidate,
        qualityPreference,
        automatic: automatic,
      ),
      MusicDataSource.flac => _sourceHealth.run(
        MusicDataSource.flac,
        () => _flac.resolve(candidate, qualityPreference: qualityPreference),
        automatic: automatic,
        operation: AutoSourceOperation.resolve,
      ),
      MusicDataSource.auto => throw StateError(
        'Auto candidates must be tagged with their concrete source.',
      ),
      MusicDataSource.lan => throw UnsupportedError(
        'LAN manifest tracks are already resolved.',
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

  Future<ResolvedMusic> _resolveBuguyy(
    MusicSearchCandidate candidate,
    String? qualityPreference, {
    required bool automatic,
  }) async {
    try {
      return await _sourceHealth.run(
        MusicDataSource.buguyy,
        () => _buguyy.resolve(candidate, qualityPreference: qualityPreference),
        automatic: automatic,
        operation: AutoSourceOperation.resolve,
      );
    } on UnsupportedEncryptedAudioException {
      return _sourceHealth.run(
        MusicDataSource.flac,
        () => _resolveEncryptedAlternate(candidate, qualityPreference),
        automatic: automatic,
        operation: AutoSourceOperation.resolve,
      );
    }
  }

  Future<ResolvedMusic> _resolveEncryptedAlternate(
    MusicSearchCandidate candidate,
    String? qualityPreference,
  ) async {
    // An encrypted URL cannot be downloaded as ordinary audio. Check both
    // platform first pages before deciding whether the identity is unique.
    final found = await _flac.searchFirstPages(candidate.name, maxResults: 40);
    final matches = found
        .where(
          (item) =>
              item.name.trim().toLowerCase() ==
                  candidate.name.trim().toLowerCase() &&
              item.artist.trim().toLowerCase() ==
                  candidate.artist.trim().toLowerCase(),
        )
        .toList(growable: false);
    if (matches.length != 1) {
      throw const UnsupportedEncryptedAudioException();
    }
    // The verified alternate for 梧桐灯 is MP3. A FLAC choice can itself
    // resolve to encrypted .mflac, so restrict this fallback to MP3 URLs.
    final match = matches.single;
    final mp3Qualities = match.qualities
        .where((quality) => quality.format.toLowerCase() == 'mp3')
        .toList(growable: false);
    if (mp3Qualities.isEmpty) {
      throw const UnsupportedEncryptedAudioException();
    }
    final playable = await _flac.resolve(
      MusicSearchCandidate(
        query: match.query,
        source: match.source,
        platform: match.platform,
        keyword: match.keyword,
        page: match.page,
        id: match.id,
        name: match.name,
        artist: match.artist,
        album: match.album,
        duration: match.duration,
        link: match.link,
        coverUrl: match.coverUrl,
        qualities: mp3Qualities,
        score: match.score,
        raw: match.raw,
      ),
      qualityPreference: qualityPreference ?? 'mp3:320',
    );
    if (urlExtension(playable.url) == '.mflac') {
      throw const UnsupportedEncryptedAudioException();
    }
    // Keep the user's saved playlist identity so a later cache lookup finds
    // the downloaded audio. The alternate source supplies only its media.
    return ResolvedMusic(
      query: candidate.query,
      source: candidate.source,
      platform: candidate.platform,
      id: candidate.id,
      name: candidate.name,
      artist: candidate.artist,
      album: playable.album,
      url: playable.url,
      quality: playable.quality,
      coverUrl: candidate.coverUrl.isNotEmpty
          ? candidate.coverUrl
          : playable.coverUrl,
      lyrics:
          playable.lyrics ??
          makeResolvedLyrics(candidate.raw['about'], 'buguyy:search:about'),
    );
  }

  Future<List<MusicSearchCandidate>> _searchAuto(String query) async {
    final sources = availableAutoSources;
    if (sources.isEmpty) throw _noAvailableAutoSourceError();
    final results = await Future.wait([
      for (final source in sources) _searchAutoSource(query, source),
    ]);
    final merged = [for (final result in results) ...result.candidates]
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        // Same recording score: prefer FLAC without reordering better matches.
        return (a.source == MusicDataSource.flac ? 0 : 1).compareTo(
          b.source == MusicDataSource.flac ? 0 : 1,
        );
      });
    if (merged.isNotEmpty) return merged.take(80).toList(growable: false);
    final errors = [
      for (final result in results)
        if (result.error != null) result.error!,
    ];
    if (errors.isNotEmpty) throw _combinedAutoError(errors);
    return const [];
  }

  Future<_AutoSourceResult> _searchAutoSource(
    String query,
    MusicDataSource source, {
    bool Function()? isCancelled,
  }) async {
    try {
      final candidates = await _sourceHealth.run(
        source,
        () => source == MusicDataSource.flac
            ? _flac.search(query)
            : _buguyy.search(query),
        automatic: true,
        isCancelled: isCancelled,
      );
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
      return _AutoSourceResult(
        error: StateError('${source.label}: ${formatResolverError(error)}'),
      );
    }
  }

  StateError _noAvailableAutoSourceError() =>
      StateError('两个音源均多次请求失败，本次运行已暂停自动请求。可在设置中手动选择音源重试，或重新打开应用。');
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

StateError _combinedAutoError(List<Object> errors) =>
    StateError(errors.map(formatResolverError).join('; '));

void _logResolver(String message) {
  developer.log(message, name: 'ai_music.resolver');
  // ignore: avoid_print
  print(message);
}

class _AutoSourceResult {
  const _AutoSourceResult({this.candidates = const [], this.error});

  final List<MusicSearchCandidate> candidates;
  final Object? error;
}
