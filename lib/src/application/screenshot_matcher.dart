import '../data/music_resolver.dart';
import 'screenshot_song_parser.dart';

class ScreenshotMatchPolicy {
  const ScreenshotMatchPolicy();

  bool resolvedStillMatches(ScreenshotSongDraft draft, ResolvedMusic resolved) {
    return resolved.panLink == false &&
        Uri.tryParse(resolved.url)?.scheme == 'https' &&
        _base(draft.title) == _base(resolved.name) &&
        _normal(draft.artist) == _normal(resolved.artist) &&
        _version(draft.title, draft.version) == _version(resolved.name, '');
  }

  static String _base(String value) => _normal(
    _withoutContext(value).replaceAll(
      RegExp(
        r'[（(]?\s*(?:live|现场(?:版)?|remix|混音(?:版)?|伴奏|翻唱|cover|纯音乐|instrumental|demo|acoustic|哼唱(?:版)?|钢琴版|[哄吹]睡版|英文版|中文版)\s*[）)]?',
        caseSensitive: false,
      ),
      '',
    ),
  );

  static String _withoutContext(String value) {
    // Strip only a trailing soundtrack/work annotation, not arbitrary subtitles.
    // The OCR may truncate it before the closing bracket.
    final annotation = RegExp(
      r'\s*(?:[（(]\s*(?:电影|电视剧|动画|选自《|《)|[-—]\s*(?:电影|电视剧|动画|选自《|《)|《)',
    ).firstMatch(value);
    return annotation != null && annotation.start > 0
        ? value.substring(0, annotation.start).trim()
        : value;
  }

  static String _version(String title, String explicit) {
    final value = '$title $explicit'.toLowerCase();
    if (RegExp(r'[哄吹]睡版').hasMatch(value)) return 'lullaby';
    if (RegExp(r'英文版').hasMatch(value)) return 'english';
    if (RegExp(r'中文版').hasMatch(value)) return 'chinese';
    if (RegExp(r'哼唱|humming').hasMatch(value)) return 'humming';
    if (RegExp(r'钢琴版').hasMatch(value)) return 'piano';
    if (RegExp(r'live|现场').hasMatch(value)) return 'live';
    if (RegExp(r'remix|混音').hasMatch(value)) return 'remix';
    if (RegExp(r'伴奏|instrumental').hasMatch(value)) return 'instrumental';
    if (RegExp(r'翻唱|cover').hasMatch(value)) return 'cover';
    if (RegExp(r'demo').hasMatch(value)) return 'demo';
    if (RegExp(r'acoustic').hasMatch(value)) return 'acoustic';
    if (RegExp(r'纯音乐').hasMatch(value)) return 'instrumental';
    return '';
  }

  static String _normal(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );
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
  }) : _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final MusicResolver resolver;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final Duration requestStartSpacing;
  final bool allowTitleFragments;
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
  }) async {
    if (draft.title.trim().isEmpty) {
      return const ScreenshotMatchResult([], null);
    }
    if (resolver is! StagedScreenshotSearchResolver) {
      final candidates = await search(draft);
      return _rank(draft, candidates);
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
    if (_hasTitleMatch(draft, primary)) return _rank(draft, primary);

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
      if (primary.isNotEmpty) return _rank(draft, primary);
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
    return _rank(draft, [
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
  }) async {
    final cached = cache[key];
    if (cached != null) return cached;
    final pending = inFlight[key];
    if (pending != null) return pending;
    if (_blockedUntil[source]?.isAfter(_now()) ?? false) {
      throw StateError('$source is temporarily unavailable');
    }
    final search = _paced(source, action);
    inFlight[key] = search;
    try {
      final found = await search;
      if (found.isNotEmpty) cache[key] = found;
      return found;
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
    final artist = ScreenshotMatchPolicy._normal(draft.artist);
    final version = ScreenshotMatchPolicy._version(draft.title, draft.version);
    bool sameVersion(MusicSearchCandidate candidate) =>
        version == ScreenshotMatchPolicy._version(candidate.name, '');
    bool exact(MusicSearchCandidate candidate) =>
        _titleSimilarity(draft, candidate) == 1 &&
        artist.isNotEmpty &&
        artist == ScreenshotMatchPolicy._normal(candidate.artist) &&
        sameVersion(candidate);
    double score(MusicSearchCandidate candidate) {
      final title = _titleSimilarity(draft, candidate);
      // Title is the identity gate. Artist similarity cannot promote a different song.
      return (exact(candidate) ? 1000 : 0) +
          title * 100 +
          (title >= 2 / 3
              ? _similarity(
                      artist,
                      ScreenshotMatchPolicy._normal(candidate.artist),
                    ) *
                    50
              : 0) +
          (sameVersion(candidate) ? 5 : -20);
    }

    final indexed = candidates.indexed.toList()
      ..sort((a, b) {
        final order = score(b.$2).compareTo(score(a.$2));
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    final ranked = [for (final entry in indexed) entry.$2];

    bool oneWrongCharacter(String a, String b, {required int minimumLength}) {
      if (a.length < minimumLength || a.length != b.length) return false;
      var differences = 0;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) differences++;
      }
      return differences == 1;
    }

    String identity(MusicSearchCandidate candidate) =>
        '${ScreenshotMatchPolicy._base(candidate.name)}|${ScreenshotMatchPolicy._normal(candidate.artist)}|${ScreenshotMatchPolicy._version(candidate.name, '')}';

    bool confidentCorrection(MusicSearchCandidate candidate) {
      if (!sameVersion(candidate) || artist.isEmpty) return false;
      final title = ScreenshotMatchPolicy._base(draft.title);
      final foundTitle = ScreenshotMatchPolicy._base(candidate.name);
      final foundArtist = ScreenshotMatchPolicy._normal(candidate.artist);
      final titleExact = title == foundTitle;
      final artistExact = artist == foundArtist;
      final titleClose = oneWrongCharacter(
        title,
        foundTitle,
        minimumLength: artistExact ? 3 : 4,
      );
      final artistClose = oneWrongCharacter(
        artist,
        foundArtist,
        minimumLength: 2,
      );
      if (!(titleExact || titleClose) || !(artistExact || artistClose)) {
        return false;
      }
      // Duplicate sources for the same song are not competing identities.
      // A close alternative song/artist must still be confirmed by the user.
      return !ranked.any(
        (other) =>
            sameVersion(other) &&
            identity(other) != identity(candidate) &&
            score(candidate) - score(other) < 12,
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

  Future<List<MusicSearchCandidate>> search(ScreenshotSongDraft draft) async {
    final query = ScreenshotMatchPolicy._withoutContext(draft.title).trim();
    if (query.isEmpty) return const [];
    final key = '$query\u001f${draft.artist.trim()}';
    return _stageSearch(
      key: key,
      cache: _searchCache,
      inFlight: _searchInFlight,
      source: MusicDataSource.auto.storageValue,
      action: () => resolver is ScreenshotSearchResolver
          ? (resolver as ScreenshotSearchResolver).searchScreenshot(
              query,
              draft.artist,
            )
          : resolver.search(query, MusicDataSource.auto),
    );
  }

  Future<T> _paced<T>(String source, Future<T> Function() action) {
    final tail = _networkTails[source] ?? Future<void>.value();
    final start = tail.then((_) async {
      if (_blockedUntil[source]?.isAfter(_now()) ?? false) {
        throw StateError('$source is temporarily unavailable');
      }
      final last = _lastNetworkStarts[source];
      if (last != null) {
        final remaining = requestStartSpacing - _now().difference(last);
        if (remaining > Duration.zero) await _wait(remaining);
      }
      if (_blockedUntil[source]?.isAfter(_now()) ?? false) {
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
