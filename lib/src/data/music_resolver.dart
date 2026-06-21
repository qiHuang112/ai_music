export 'buguyy_resolver.dart';
export 'candidate_scorer.dart'
    show CandidateScorer, isLooseArtistTitleCandidate, isStrictArtistCandidate;
export 'challenge_client.dart' show ChallengeClient;
export 'flac_resolver.dart';
export 'resolver_http_client.dart';
export 'resolver_models.dart';

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

    return switch (source) {
      MusicDataSource.buguyy => _buguyy.search(trimmed),
      MusicDataSource.flac => _flac.search(trimmed),
      MusicDataSource.auto => _searchAuto(trimmed),
    };
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async {
    return switch (candidate.source) {
      MusicDataSource.buguyy => _buguyy.resolve(candidate),
      MusicDataSource.flac => _flac.resolve(candidate),
      MusicDataSource.auto => throw StateError(
        'Auto candidates must be tagged with their concrete source.',
      ),
    };
  }

  Future<List<MusicSearchCandidate>> _searchAuto(String query) async {
    Object? buguyyError;
    try {
      final buguyy = await _buguyy.search(query);
      if (buguyy.isNotEmpty) {
        return buguyy;
      }
    } catch (error) {
      buguyyError = error;
    }

    try {
      return await _flac.search(query);
    } catch (flacError) {
      if (buguyyError != null) {
        throw StateError(
          'buguyy failed: ${formatResolverError(buguyyError)}; '
          'flac failed: ${formatResolverError(flacError)}',
        );
      }
      rethrow;
    }
  }
}
