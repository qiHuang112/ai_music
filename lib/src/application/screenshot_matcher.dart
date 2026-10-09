import '../data/music_resolver.dart';
import '../data/song_match_identity.dart';
import 'screenshot_song_parser.dart';

class ScreenshotMatchPolicy {
  const ScreenshotMatchPolicy();

  bool resolvedStillMatches(ScreenshotSongDraft draft, ResolvedMusic resolved) {
    return resolved.panLink == false &&
        Uri.tryParse(resolved.url)?.scheme == 'https' &&
        SongMatchIdentity(
          draft.title,
          draft.artist,
          version: draft.version,
        ).sameRecording(SongMatchIdentity(resolved.name, resolved.artist));
  }

  static String _base(String value) => SongMatchIdentity(value, '').title;
  static String _withoutContext(String value) => withoutSongContext(value);
}

class ScreenshotMatchResult {
  const ScreenshotMatchResult(
    this.candidates,
    this.recommended, {
    this.needsReview = false,
  });

  final List<MusicSearchCandidate> candidates;
  final MusicSearchCandidate? recommended;
  final bool needsReview;
}

class ScreenshotMatcher {
  ScreenshotMatcher({
    required this.resolver,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
    this.requestStartSpacing = const Duration(milliseconds: 350),
    this.allowTitleFragments = true,
    this.source = MusicDataSource.auto,
    this.sourceProvider,
  }) : _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final MusicResolver resolver;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final Duration requestStartSpacing;
  final bool allowTitleFragments;
  final MusicDataSource source;
  final MusicDataSource Function()? sourceProvider;
  final Map<String, List<MusicSearchCandidate>> _searchCache = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _searchInFlight = {};
  final Map<String, List<MusicSearchCandidate>> _primaryCache = {};
  final Map<String, List<MusicSearchCandidate>> _fallbackCache = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _primaryInFlight = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _fallbackInFlight = {};
  final Map<String, Future<void>> _networkTails = {};
  final Map<String, DateTime> _lastNetworkStarts = {};
  final Map<String, DateTime> _blockedUntil = {};

  ScreenshotMatchResult rankCached(
    ScreenshotSongDraft draft,
    List<MusicSearchCandidate> candidates,
  ) => _rank(draft, candidates);

  Future<ScreenshotMatchResult> match(
    ScreenshotSongDraft draft, {
    bool failOnSourceErrorWhenEmpty = false,
    MusicDataSource? source,
  }) async {
    final selectedSource = source ?? sourceProvider?.call() ?? this.source;
    ScreenshotMatchResult rank(List<MusicSearchCandidate> candidates) {
      final health = resolver;
      return _rank(
        draft,
        selectedSource == MusicDataSource.auto &&
                health is AutoSourceHealthResolver
            ? candidates
                  .where(
                    (c) => (health as AutoSourceHealthResolver)
                        .isSourceAvailableForAuto(c.source),
                  )
                  .toList()
            : candidates,
      );
    }

    if (draft.title.trim().isEmpty) {
      return const ScreenshotMatchResult([], null);
    }
    if (!allowTitleFragments ||
        selectedSource != MusicDataSource.auto ||
        resolver is! StagedScreenshotSearchResolver) {
      final candidates = await search(draft, source: selectedSource);
      return rank(candidates);
    }
    final staged = resolver as StagedScreenshotSearchResolver;

    final query = ScreenshotMatchPolicy._withoutContext(draft.title).trim();
    final key = query.toLowerCase();
    Object? primaryFailure;
    List<MusicSearchCandidate> primary;
    try {
      primary = await _stageSearch(
        key: key,
        cache: _primaryCache,
        inFlight: _primaryInFlight,
        source: MusicDataSource.buguyy.storageValue,
        action: () => staged.searchScreenshotPrimary(query),
      );
    } catch (error) {
      primaryFailure = error;
      primary = const [];
    }
    final primaryMatch = rank(primary);
    if (allowTitleFragments
        ? _hasTitleMatch(draft, primary)
        : primaryMatch.recommended != null && !primaryMatch.needsReview) {
      return primaryMatch;
    }

    List<MusicSearchCandidate> fallback;
    try {
      fallback = await _stageSearch(
        key: '$key\u001f${draft.artist.trim().toLowerCase()}',
        cache: _fallbackCache,
        inFlight: _fallbackInFlight,
        source: MusicDataSource.flac.storageValue,
        action: () => staged.searchScreenshotFallback(query, draft.artist),
      );
    } catch (_) {
      if (primary.isNotEmpty) return rank(primary);
      if (primaryFailure != null) throw primaryFailure;
      rethrow;
    }
    if (fallback.isEmpty &&
        primaryFailure != null &&
        failOnSourceErrorWhenEmpty) {
      throw primaryFailure;
    }
    final combined = [...primary, ...fallback];
    // Bounded fragment recall: never invent a corrected name or search an
    // artist's entire catalogue. Reuse source pacing, caches and protection.
    final title = ScreenshotMatchPolicy._base(draft.title);
    if (allowTitleFragments &&
        !_hasTitleMatch(draft, combined) &&
        RegExp(r'^[\u4e00-\u9fff]{4,12}$').hasMatch(title)) {
      final size = (title.length / 2).ceil();
      for (final fragment in {
        title.substring(0, size),
        title.substring(title.length - size),
      }) {
        try {
          combined.addAll(
            await _stageSearch(
              key: fragment,
              cache: _primaryCache,
              inFlight: _primaryInFlight,
              source: MusicDataSource.buguyy.storageValue,
              action: () => staged.searchScreenshotPrimary(fragment),
            ),
          );
        } catch (_) {
          // Existing candidates remain available when supplemental recall fails.
        }
      }
    }
    final seen = <String>{};
    return rank([
      for (final candidate in combined)
        if (seen.add(
          '${candidate.source.storageValue}|${candidate.platform}|${candidate.id}',
        ))
          candidate,
    ]);
  }

  Future<List<MusicSearchCandidate>> _stageSearch({
    required String key,
    required Map<String, List<MusicSearchCandidate>> cache,
    required Map<String, Future<List<MusicSearchCandidate>>> inFlight,
    required String source,
    required Future<List<MusicSearchCandidate>> Function() action,
    bool automatic = true,
  }) async {
    final health = resolver;
    final originalKey = key;
    String scope() => automatic && health is AutoSourceHealthResolver
        ? (health as AutoSourceHealthResolver).availableAutoSources
              .map((s) => s.storageValue)
              .join(',')
        : '';
    final initialScope = scope();
    if (automatic) key = '$key|health:$initialScope';
    List<MusicSearchCandidate> available(List<MusicSearchCandidate> found) =>
        automatic && health is AutoSourceHealthResolver
        ? found
              .where(
                (candidate) => (health as AutoSourceHealthResolver)
                    .isSourceAvailableForAuto(candidate.source),
              )
              .toList()
        : found;
    Future<List<MusicSearchCandidate>> current(
      Future<List<MusicSearchCandidate>> pending,
    ) async {
      final found = await pending;
      // A queued or in-flight query can finish after another request degrades
      // a provider. Re-query under the new health scope before recommending.
      if (automatic &&
          source == MusicDataSource.auto.storageValue &&
          initialScope != scope()) {
        return _stageSearch(
          key: originalKey,
          cache: cache,
          inFlight: inFlight,
          source: source,
          action: action,
          automatic: automatic,
        );
      }
      return available(found);
    }

    if (automatic &&
        health is AutoSourceHealthResolver &&
        source != MusicDataSource.auto.storageValue &&
        !(health as AutoSourceHealthResolver).isSourceAvailableForAuto(
          MusicDataSource.fromStorage(source),
        )) {
      return const [];
    }
    final cached = cache[key];
    if (cached != null) return available(cached);
    final pending = inFlight[key];
    if (pending != null) return current(pending);
    if (automatic && (_blockedUntil[source]?.isAfter(_now()) ?? false)) {
      throw StateError('$source is temporarily unavailable');
    }
    final search = _paced(source, action, automatic: automatic);
    inFlight[key] = search;
    try {
      final found = await search;
      if (found.isNotEmpty) cache[key] = found;
      return current(Future.value(found));
    } catch (error) {
      if (_isSourceProtection(error)) {
        _blockedUntil[source] = _now().add(const Duration(minutes: 15));
      }
      rethrow;
    } finally {
      inFlight.remove(key);
    }
  }

  static bool _isSourceProtection(Object error) => RegExp(
    r'\b(?:403|429)\b|captcha|challenge|defender|防护|验证码',
    caseSensitive: false,
  ).hasMatch(error.toString());

  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = <int>[i];
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current.add(
          [substitution, deletion, insertion].reduce((x, y) => x < y ? x : y),
        );
      }
      previous = current;
    }
    return 1 - previous.last / (a.length > b.length ? a.length : b.length);
  }

  static double _titleSimilarity(
    ScreenshotSongDraft draft,
    MusicSearchCandidate candidate,
  ) => _similarity(
    ScreenshotMatchPolicy._base(draft.title),
    ScreenshotMatchPolicy._base(candidate.name),
  );

  static bool _hasTitleMatch(
    ScreenshotSongDraft draft,
    List<MusicSearchCandidate> candidates,
  ) => candidates.any((candidate) => _titleSimilarity(draft, candidate) >= 0.7);

  ScreenshotMatchResult _rank(
    ScreenshotSongDraft draft,
    List<MusicSearchCandidate> candidates,
  ) {
    final expected = SongMatchIdentity(
      draft.title,
      draft.artist,
      version: draft.version,
    );
    final identities = {
      for (final candidate in candidates)
        candidate: SongMatchIdentity(candidate.name, candidate.artist),
    };
    bool sameVersion(MusicSearchCandidate candidate) =>
        expected.version == identities[candidate]!.version;
    bool exact(MusicSearchCandidate candidate) =>
        expected.sameRecording(identities[candidate]!);
    double artistSimilarity(SongMatchIdentity found) {
      if (expected.artists.isEmpty || found.artists.isEmpty) return 0;
      if (expected.sameArtists(found)) return 1;
      final overlap = expected.artists.intersection(found.artists).length;
      if (overlap > 0) {
        final largest = expected.artists.length > found.artists.length
            ? expected.artists.length
            : found.artists.length;
        return overlap / largest;
      }
      return _similarity(expected.artistKey, found.artistKey);
    }

    final titleScores = {
      for (final candidate in candidates)
        candidate: _similarity(expected.title, identities[candidate]!.title),
    };
    final titleWithoutAnnotations = normalizeSongText(
      withoutSongContext(
        draft.title,
      ).replaceAll(RegExp(r'[（(][^（）()]*[）)]'), ''),
    );
    double durationBonus(MusicSearchCandidate candidate) {
      if (draft.durationSeconds <= 0 || candidate.duration <= 0) return 0;
      final found = identities[candidate]!;
      if ((titleScores[candidate]! < 2 / 3 &&
              titleWithoutAnnotations != found.title) ||
          expected.artists.intersection(found.artists).isEmpty) {
        return 0;
      }
      // Resolver durations are usually seconds; a millisecond response is
      // recognizable relative to the known platform duration, not by a fixed
      // threshold that would corrupt a legitimately long song.
      final seconds = candidate.duration > draft.durationSeconds * 100
          ? candidate.duration / 1000
          : candidate.duration.toDouble();
      final difference = (seconds - draft.durationSeconds).abs();
      return difference <= 2
          ? 10
          : difference <= 5
          ? 5
          : 0;
    }

    final scores = {
      for (final candidate in candidates)
        candidate:
            (exact(candidate) ? 1000 : 0) +
            titleScores[candidate]! * 100 +
            (titleScores[candidate]! >= 2 / 3
                ? artistSimilarity(identities[candidate]!) * 50
                : 0) +
            (sameVersion(candidate) ? 5 : -20) +
            (sameVersion(candidate) &&
                    titleScores[candidate] == 1 &&
                    expected.artists
                        .intersection(identities[candidate]!.artists)
                        .isNotEmpty
                ? 40
                : 0) +
            durationBonus(candidate),
    };
    final indexed = candidates.indexed.toList();
    // Without even a plausible title, preserve the source's first fallback.
    // An arbitrary partial overlap must not promote another unrelated song.
    if (titleScores.values.any((score) => score >= 2 / 3) ||
        candidates.any((candidate) => durationBonus(candidate) > 0)) {
      indexed.sort((a, b) {
        final order = scores[b.$2]!.compareTo(scores[a.$2]!);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    }
    final ranked = [for (final entry in indexed) entry.$2];

    bool oneWrongCharacter(String a, String b, {required int minimumLength}) {
      if (a.length < minimumLength || a.length != b.length) return false;
      var differences = 0;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) differences++;
      }
      return differences == 1;
    }

    bool confidentCorrection(MusicSearchCandidate candidate) {
      if (!allowTitleFragments ||
          !sameVersion(candidate) ||
          expected.artists.isEmpty) {
        return false;
      }
      final found = identities[candidate]!;
      final titleExact = expected.title == found.title;
      final artistExact = expected.sameArtists(found);
      final titleClose = oneWrongCharacter(
        expected.title,
        found.title,
        minimumLength: artistExact ? 3 : 4,
      );
      final artistClose =
          expected.artists.length == 1 &&
          found.artists.length == 1 &&
          oneWrongCharacter(
            expected.artistKey,
            found.artistKey,
            minimumLength: 2,
          );
      if (!(titleExact || titleClose) || !(artistExact || artistClose)) {
        return false;
      }
      return !ranked.any(
        (other) =>
            sameVersion(other) &&
            identities[other]!.key != found.key &&
            scores[candidate]! - scores[other]! < 12,
      );
    }

    return ScreenshotMatchResult(
      ranked,
      ranked.isEmpty ? null : ranked.first,
      needsReview:
          ranked.isNotEmpty &&
          !(exact(ranked.first) || confidentCorrection(ranked.first)),
    );
  }

  Future<List<MusicSearchCandidate>> search(
    ScreenshotSongDraft draft, {
    MusicDataSource? source,
  }) async {
    final selectedSource = source ?? sourceProvider?.call() ?? this.source;
    final query = ScreenshotMatchPolicy._withoutContext(draft.title).trim();
    if (query.isEmpty) return const [];
    final searchQuery = !allowTitleFragments && draft.artist.trim().isNotEmpty
        ? '${draft.artist.trim()} $query'
        : query;
    final key =
        '${selectedSource.storageValue}\u001f$query\u001f${draft.artist.trim()}';
    return _stageSearch(
      key: key,
      cache: _searchCache,
      inFlight: _searchInFlight,
      source: selectedSource.storageValue,
      automatic: selectedSource == MusicDataSource.auto,
      action: () =>
          allowTitleFragments &&
              selectedSource == MusicDataSource.auto &&
              resolver is ScreenshotSearchResolver
          ? (resolver as ScreenshotSearchResolver).searchScreenshot(
              query,
              draft.artist,
            )
          : resolver.search(searchQuery, selectedSource),
    );
  }

  Future<T> _paced<T>(
    String source,
    Future<T> Function() action, {
    required bool automatic,
  }) {
    final tail = _networkTails[source] ?? Future<void>.value();
    final start = tail.then((_) async {
      if (automatic && (_blockedUntil[source]?.isAfter(_now()) ?? false)) {
        throw StateError('$source is temporarily unavailable');
      }
      final last = _lastNetworkStarts[source];
      if (last != null) {
        final remaining = requestStartSpacing - _now().difference(last);
        if (remaining > Duration.zero) await _wait(remaining);
      }
      if (automatic && (_blockedUntil[source]?.isAfter(_now()) ?? false)) {
        throw StateError('$source is temporarily unavailable');
      }
      _lastNetworkStarts[source] = _now();
    });
    // Pace request starts, while allowing already-started searches to overlap.
    _networkTails[source] = start.then<void>((_) {}, onError: (_) {});
    return start.then((_) async {
      try {
        return await action();
      } catch (error) {
        if (_isSourceProtection(error)) {
          _blockedUntil[source] = _now().add(const Duration(minutes: 15));
        }
        rethrow;
      }
    });
  }
}
