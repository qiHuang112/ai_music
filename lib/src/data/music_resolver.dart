export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'twenty_four_bit_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';
export 'music_source_policy.dart';

import 'dart:async';
import 'dart:developer' as developer;

import 'auto_source_health.dart';
import 'auto_search_policy.dart';
import 'buguyy_resolver.dart';
import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'flac_resolver.dart';
import 'lyrics_normalizer.dart';
import 'resolver_http_client.dart';
import 'provider_request_scheduler.dart';
import 'resolver_models.dart';
import 'music_source_policy.dart';
import 'operation_log.dart';
import 'resolver_utils.dart';
import 'song_match_identity.dart';
import 'twenty_four_bit_resolver.dart';

class RemoteMusicResolver
    implements
        MusicResolver,
        QualitySelectableMusicResolver,
        AutoSourceHealthResolver,
        AutoFallbackMusicResolver,
        CancellableMusicResolver,
        ScreenshotSearchResolver,
        StagedScreenshotSearchResolver,
        ScreenshotSearchSourceScopes,
        MusicSourcePolicyResolver,
        SourceAvailabilityResolver {
  RemoteMusicResolver({
    MusicResolverHttp? httpClient,
    String? initialFlacCookie,
    int pages = 8,
    List<String> platforms = const ['kuwo', 'wyy'],
    String prefer = 'flac',
    bool? useAppleBuguyyEndpoint,
    this.sourceCatalog = MusicSourceCatalog.standard,
    bool Function(MusicDataSource)? isSourceAuthorized,
  }) {
    _isSourceAuthorized = isSourceAuthorized ?? (_) => false;
    _sourceHealth = AutoSourceHealth(
      catalog: sourceCatalog,
      isAuthorized: _isSourceAuthorized,
    );
    final http = httpClient ?? (_ownedHttp = HttpMusicResolverClient());
    _http = http;
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
    _twentyFourBit = TwentyFourBitResolver(httpClient: http);
  }

  HttpMusicResolverClient? _ownedHttp;
  late final MusicResolverHttp _http;
  void close() => _ownedHttp?.close();

  late final BuguyyResolver _buguyy;
  late final FlacResolver _flac;
  late final TwentyFourBitResolver _twentyFourBit;
  late final AutoSourceHealth _sourceHealth;
  @override
  final MusicSourceCatalog sourceCatalog;
  late final bool Function(MusicDataSource) _isSourceAuthorized;
  @override
  bool isSourceAuthorized(MusicDataSource source) =>
      _isSourceAuthorized(source);
  final _availabilityProbes = <MusicDataSource, Future<void> Function()>{};
  Future<void>? _availabilityCheck;
  int _availabilityRevision = 0;
  @override
  int get sourceAvailabilityRevision => _availabilityRevision;
  @override
  MusicSourceAvailability sourceAvailability(MusicDataSource source) =>
      _sourceHealth.availability(source);

  void _rememberAvailabilityProbe(
    MusicDataSource source, {
    String? query,
    MusicSearchCandidate? candidate,
  }) {
    _availabilityProbes[source] = () async {
      if (candidate != null) {
        await switch (source) {
          MusicDataSource.flac => _flac.resolve(candidate),
          MusicDataSource.buguyy => _buguyy.resolve(candidate),
          MusicDataSource.twentyFourBit => _twentyFourBit.resolve(candidate),
          _ => throw UnsupportedError('No probe adapter for $source'),
        };
      } else {
        await switch (source) {
          MusicDataSource.flac => _flac.searchFirstPages(
            query!,
            stopAfterPage: (_) => true,
          ),
          MusicDataSource.buguyy => _buguyy.searchSingleKeyword(query!),
          MusicDataSource.twentyFourBit => _twentyFourBit.search(query!),
          _ => throw UnsupportedError('No probe adapter for $source'),
        };
      }
    };
  }

  @override
  Future<void> recheckSourceAvailability({bool networkChanged = false}) {
    if (_availabilityCheck case final pending?) return pending;
    final targets = [
      for (final policy in sourceCatalog.policies)
        if (_availabilityProbes.containsKey(policy.source) &&
            {
              MusicSourceAvailability.unavailable,
              MusicSourceAvailability.quotaExhausted,
            }.contains(sourceAvailability(policy.source)))
          policy.source,
    ];
    if (!networkChanged && targets.isEmpty) return Future.value();
    _availabilityRevision++;
    _autoPriorityCandidates.clear();
    if (_http is HttpMusicResolverClient) {
      (_http).resetSourceNetworkState();
    }
    for (final policy in sourceCatalog.policies) {
      if (networkChanged || targets.contains(policy.source)) {
        _sourceHealth.reset(
          policy.source,
          checking: targets.contains(policy.source),
        );
      }
    }
    final work = Future.wait([
      for (final source in targets)
        () async {
          try {
            await _sourceHealth.run(
              source,
              () => _availabilityProbes[source]!().timeout(
                const Duration(seconds: 8),
              ),
              automatic: false,
            );
          } catch (_) {
            // Status records the outcome; never download audio while probing.
          } finally {
            _sourceHealth.finishCheck(source);
          }
        }(),
    ]).then<void>((_) {});
    _availabilityCheck = work;
    return work.whenComplete(() => _availabilityCheck = null);
  }

  // Only results reached through the ordered Auto search can skip rechecking
  // earlier providers. Persisted candidates from the old mixed strategy cannot.
  final _autoPriorityCandidates = <String>{};

  String _candidateKey(MusicSearchCandidate candidate) =>
      '${candidate.source.storageValue}|${candidate.platform}|${candidate.id}';

  void _rememberAutoPriority(List<MusicSearchCandidate> candidates) {
    for (final candidate in candidates) {
      _autoPriorityCandidates.add(_candidateKey(candidate));
    }
    while (_autoPriorityCandidates.length > 1000) {
      _autoPriorityCandidates.remove(_autoPriorityCandidates.first);
    }
  }

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
  MusicDataSource get screenshotPrimarySource =>
      sourceCatalog.autoSources(isAuthorized: isSourceAuthorized).firstOrNull ??
      MusicDataSource.auto;

  @override
  MusicDataSource get screenshotFallbackSource => MusicDataSource.auto;

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotPrimary(String title) =>
      screenshotPrimarySource == MusicDataSource.auto
      ? Future.value(const [])
      : _searchScreenshotProvider(screenshotPrimarySource, title, '');

  @override
  Future<List<MusicSearchCandidate>> searchScreenshotFallback(
    String title,
    String artist,
  ) async {
    Object? firstFailure;
    for (final source in availableAutoSources) {
      if (source == screenshotPrimarySource) continue;
      try {
        final found = await _searchScreenshotProvider(source, title, artist);
        if (found.isNotEmpty) return found;
      } catch (error) {
        firstFailure ??= error;
      }
    }
    if (firstFailure != null) throw firstFailure;
    return const [];
  }

  Future<List<MusicSearchCandidate>> _searchScreenshotProvider(
    MusicDataSource source,
    String title,
    String artist,
  ) async {
    final found = await _searchScreenshotSource(
      source == MusicDataSource.twentyFourBit ? '$title $artist'.trim() : title,
      source,
      (query) => switch (source) {
        MusicDataSource.flac => _flac.searchFirstPages(
          query,
          stopAfterPage: (_) => true,
        ),
        MusicDataSource.buguyy => _buguyy.searchSingleKeyword(query),
        MusicDataSource.twentyFourBit => _twentyFourBit.search(query),
        _ => throw UnsupportedError('No screenshot adapter for $source'),
      },
    );
    _rememberAutoPriority(found);
    return found;
  }

  Future<List<MusicSearchCandidate>> _searchScreenshotSource(
    String title,
    MusicDataSource source,
    Future<List<MusicSearchCandidate>> Function(String) action,
  ) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    if (!isSourceAvailableForAuto(source)) return const [];
    _rememberAvailabilityProbe(source, query: query);
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
    if (source != MusicDataSource.auto && source != MusicDataSource.lan) {
      _rememberAvailabilityProbe(source, query: trimmed);
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
      MusicDataSource.twentyFourBit => await _sourceHealth.run(
        source,
        () => _twentyFourBit.search(trimmed),
        automatic: false,
      ),
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
  ) => searchWithCancellation(query, source, isCancelled: () => false);

  @override
  Stream<MusicSearchProgress> searchWithCancellation(
    String query,
    MusicDataSource source, {
    required bool Function() isCancelled,
  }) {
    final trimmed = query.trim();
    final merged = <MusicSearchCandidate>[];
    final bySource = <MusicDataSource, List<MusicSearchCandidate>>{};
    final policy = AutoSearchPolicy(trimmed, catalog: sourceCatalog);
    final errors = <Object>[];
    var cancelled = false;
    bool stopped() => cancelled || isCancelled();
    final stream = StreamController<MusicSearchProgress>(
      onCancel: () => cancelled = true,
    );
    final sources = source == MusicDataSource.auto
        ? policy.orderSources(availableAutoSources)
        : [source];
    void emit(bool complete) {
      if (stopped()) return;
      stream.add(
        MusicSearchProgress(
          candidates: List.unmodifiable(merged),
          isComplete: complete,
          error: complete && merged.isEmpty && errors.isNotEmpty
              ? _combinedAutoError(errors)
              : null,
        ),
      );
    }

    void update(
      MusicDataSource concrete,
      List<MusicSearchCandidate> candidates,
    ) {
      if (source == MusicDataSource.auto) {
        bySource[concrete] = candidates;
        merged
          ..clear()
          ..addAll(policy.rank(bySource.values.expand((items) => items)));
        return;
      }
      if (candidates.isEmpty) return;
      final keys = {
        for (final c in candidates) '${c.source}\t${c.platform}\t${c.id}',
      };
      merged.removeWhere(
        (c) => !keys.contains('${c.source}\t${c.platform}\t${c.id}'),
      );
      _appendStableCandidates(merged, candidates);
    }

    void batch(
      MusicDataSource concrete,
      List<MusicSearchCandidate> candidates,
    ) {
      if (stopped() || candidates.isEmpty) return;
      update(concrete, candidates);
      if (source == MusicDataSource.auto) _rememberAutoPriority(merged);
      emit(false);
    }

    if (trimmed.isEmpty || sources.isEmpty) {
      if (sources.isEmpty) errors.add(_noAvailableAutoSourceError());
      emit(true);
      unawaited(stream.close());
      return stream.stream;
    }
    unawaited(
      runZoned(() async {
        try {
          for (final concrete in sources) {
            if (stopped()) return;
            if (source == MusicDataSource.auto &&
                sourceCatalog.policyFor(concrete)?.fallbackOnly == true &&
                policy.hasStrongMatch(merged)) {
              OperationLog.event('search.auto.fallbackSkipped', {
                'query': trimmed,
                'source': concrete.storageValue,
                'reason': 'regular_source_strong_match',
              });
              break;
            }
            final result = await _searchAutoSource(
              trimmed,
              concrete,
              isCancelled: stopped,
              automatic: source == MusicDataSource.auto,
              onBatch: (candidates) => batch(concrete, candidates),
            );
            if (stopped()) return;
            if (result.error != null) errors.add(result.error!);
            if (result.error == null || result.candidates.isNotEmpty) {
              update(concrete, result.candidates);
              emit(false);
            }
            final complete = source != MusicDataSource.auto
                ? merged.isNotEmpty
                : policy.canStopEarly(merged);
            if (source == MusicDataSource.auto) {
              OperationLog.event('search.auto.source', {
                'query': trimmed,
                'source': concrete.storageValue,
                'count': result.candidates.length,
                'mergedCount': merged.length,
                'strongCount': merged
                    .where((c) => policy.matchLevel(c) >= 2)
                    .length,
                'earlyStop': complete,
              });
            }
            if (complete) {
              if (source == MusicDataSource.auto) _rememberAutoPriority(merged);
              break;
            }
            // Deliver this source before dispatching another request, so a
            // listener cancelling after the batch can prevent the fallback.
            await Future<void>.delayed(Duration.zero);
          }
          emit(true);
        } finally {
          await stream.close();
        }
      }, zoneValues: {providerCancellationKey: stopped}),
    );
    return stream.stream;
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
  }) async {
    final checkedEarlier = <MusicDataSource>{};
    final earlierSources =
        AutoSearchPolicy(candidate.query, catalog: sourceCatalog)
            .orderSources(availableAutoSources)
            .takeWhile((source) => source != candidate.source)
            .toSet();
    if (mode == MusicDataSource.auto &&
        earlierSources.isNotEmpty &&
        !_autoPriorityCandidates.contains(_candidateKey(candidate))) {
      checkedEarlier.addAll(earlierSources);
      try {
        return await resolveAlternative(
          candidate,
          excludedSources: {
            for (final source in availableAutoSources)
              if (!earlierSources.contains(source)) source,
          },
          quality: quality,
          isCancelled: _requestCancelled,
        );
      } catch (_) {
        if (_requestCancelled()) rethrow;
      }
    }
    try {
      final resolved = await _resolveWithPreference(
        candidate,
        quality?.resolverPreference,
        automatic: mode == MusicDataSource.auto,
      );
      if (mode == MusicDataSource.auto &&
          (resolved.panLink ||
              !SongMatchIdentity(
                candidate.name,
                candidate.artist,
              ).sameRecording(
                SongMatchIdentity(resolved.name, resolved.artist),
              ))) {
        throw StateError('未获取到同曲可播放的音频地址');
      }
      return resolved;
    } catch (_) {
      if (mode != MusicDataSource.auto || _requestCancelled()) rethrow;
      try {
        return await resolveAlternative(
          candidate,
          excludedSources: {candidate.source, ...checkedEarlier},
          quality: quality,
          isCancelled: _requestCancelled,
        );
      } catch (_) {
        // Preserve the useful original error when no verified alternate exists.
      }
      rethrow;
    }
  }

  @override
  Future<ResolvedMusic> resolveAlternative(
    MusicSearchCandidate candidate, {
    required Set<MusicDataSource> excludedSources,
    MusicQualityLevel? quality,
    bool Function()? isCancelled,
  }) async {
    bool stopped() => isCancelled?.call() == true || _requestCancelled();
    final identity = SongMatchIdentity(candidate.name, candidate.artist);
    bool matches(MusicSearchCandidate item) =>
        identity.sameRecording(SongMatchIdentity(item.name, item.artist));
    final sources = AutoSearchPolicy(
      candidate.query,
      catalog: sourceCatalog,
    ).orderSources(availableAutoSources);
    for (final source in sources) {
      if (stopped()) throw StateError('Source request cancelled');
      if (excludedSources.contains(source)) continue;
      try {
        final query = '${candidate.artist} ${candidate.name}'.trim();
        final found = await _sourceHealth.run(
          source,
          () => switch (source) {
            MusicDataSource.flac => _flac.search(
              query,
              initialKeyword: candidate.name,
              matchesTarget: matches,
              isCancelled: stopped,
            ),
            MusicDataSource.twentyFourBit => _twentyFourBit.search(
              query,
              matchesTarget: matches,
              isCancelled: stopped,
            ),
            _ => _buguyy.search(query),
          },
          automatic: true,
          isCancelled: stopped,
        );
        if (stopped()) throw StateError('Source request cancelled');
        // One attempt per provider; another recording must never be a fallback.
        final match = found.where(matches).firstOrNull;
        if (match == null) continue;
        _rememberAutoPriority([match]);
        final resolved = await _resolveWithPreference(
          match,
          quality?.resolverPreference,
          automatic: true,
        );
        if (stopped()) throw StateError('Source request cancelled');
        if (!identity.sameRecording(
              SongMatchIdentity(resolved.name, resolved.artist),
            ) ||
            resolved.panLink ||
            Uri.tryParse(resolved.url)?.scheme != 'https') {
          continue;
        }
        return resolved;
      } catch (_) {
        if (stopped()) rethrow;
      }
    }
    throw StateError('未找到可用的同曲备用来源');
  }

  Future<ResolvedMusic> _resolveWithPreference(
    MusicSearchCandidate candidate,
    String? qualityPreference, {
    bool automatic = false,
  }) async {
    _rememberAvailabilityProbe(candidate.source, candidate: candidate);
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
      MusicDataSource.twentyFourBit => _sourceHealth.run(
        candidate.source,
        () => _twentyFourBit.resolve(
          candidate,
          qualityPreference: qualityPreference,
        ),
        automatic: automatic,
        operation: AutoSourceOperation.resolve,
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
    // Capture the parent cancellation callback before entering the provider
    // zone; looking it up from inside its own replacement would recurse.
    final inherited = Zone.current[providerCancellationKey];
    bool cancelled() => inherited is bool Function() && inherited();
    MusicSearchProgress? latest;
    await for (final progress in searchWithCancellation(
      query,
      MusicDataSource.auto,
      isCancelled: cancelled,
    )) {
      latest = progress;
    }
    if (cancelled()) throw StateError('Source request cancelled');
    if (latest?.error != null) throw latest!.error!;
    return latest?.candidates ?? const [];
  }

  Future<_AutoSourceResult> _searchAutoSource(
    String query,
    MusicDataSource source, {
    bool Function()? isCancelled,
    bool automatic = true,
    void Function(List<MusicSearchCandidate>)? onBatch,
  }) async {
    if (isSourceAvailableForAuto(source) || !automatic) {
      _rememberAvailabilityProbe(source, query: query);
    }
    try {
      final candidates = await _sourceHealth.run(
        source,
        () => switch (source) {
          MusicDataSource.flac => _flac.search(
            query,
            onBatch: onBatch,
            isCancelled: isCancelled,
          ),
          MusicDataSource.twentyFourBit => _twentyFourBit.search(
            query,
            onBatch: onBatch,
            isCancelled: isCancelled,
          ),
          _ => _buguyy.search(query),
        },
        automatic: automatic,
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
      StateError('音源均多次请求失败，本次运行已暂停自动请求。可在设置中手动选择音源重试，或重新打开应用。');
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

bool _requestCancelled() {
  final check = Zone.current[providerCancellationKey];
  return check is bool Function() && check();
}

void _logResolver(String message) {
  OperationLog.event('resolver', {'message': message});
  developer.log(message, name: 'ai_music.resolver');
  // ignore: avoid_print
  print(message);
}

class _AutoSourceResult {
  const _AutoSourceResult({this.candidates = const [], this.error});

  final List<MusicSearchCandidate> candidates;
  final Object? error;
}
