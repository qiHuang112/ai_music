export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';

import 'dart:developer' as developer;

import 'buguyy_resolver.dart';
import 'candidate_scorer.dart';
import 'challenge_client.dart';
import 'flac_resolver.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

class RemoteMusicResolver implements MusicResolver {
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
      throw StateError(
        'buguyy failed: ${formatResolverError(buguyy.error!)}; '
        'flac failed: ${formatResolverError(flac.error!)}',
      );
    }
    final error = buguyy.error ?? flac.error;
    if (error != null) {
      throw StateError(formatResolverError(error));
    }
    return const [];
  }
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
