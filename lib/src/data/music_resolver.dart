export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';

import 'dart:async';
import 'dart:developer' as developer;

import 'buguyy_resolver.dart';
import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'flac_resolver.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class RemoteMusicResolver implements MusicResolver, ProgressiveMusicResolver {
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
    var remaining = 2;

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
    yield* stream.stream;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    final resolved = await switch (candidate.source) {
      MusicDataSource.buguyy => _buguyy.resolve(candidate),
      MusicDataSource.flac => _flac.resolve(candidate),
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
    final results = await Future.wait([buguyyFuture, flacFuture]);
    final buguyy = results[0];
    final flac = results[1];
    final merged = [...buguyy.candidates, ...flac.candidates]
      ..sort((a, b) => b.score.compareTo(a.score));
    _logResolver(
      '[AI Music][resolver] auto merged query="$query" '
      'buguyy=${buguyy.candidates.length} flac=${flac.candidates.length} '
      'count=${merged.length}',
    );
    if (merged.isNotEmpty) {
      return merged.take(80).toList(growable: false);
    }
    if (buguyy.error != null && flac.error != null) {
      throw _combinedAutoError([buguyy.error!, flac.error!]);
    }
    final error = buguyy.error ?? flac.error;
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
    'buguyy failed: ${formatResolverError(errors[0])}; '
    'flac failed: ${formatResolverError(errors[1])}',
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
