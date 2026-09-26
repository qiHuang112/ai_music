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
    value.replaceAll(
      RegExp(
        r'[（(]?\s*(?:live|现场(?:版)?|remix|混音(?:版)?|伴奏|翻唱|cover|纯音乐|instrumental|demo|acoustic)\s*[）)]?',
        caseSensitive: false,
      ),
      '',
    ),
  );

  static String _version(String title, String explicit) {
    final value = '$title $explicit'.toLowerCase();
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
  const ScreenshotMatchResult(this.candidates, this.recommended);

  final List<MusicSearchCandidate> candidates;
  final MusicSearchCandidate? recommended;
}

class ScreenshotMatcher {
  ScreenshotMatcher({
    required this.resolver,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
    this.requestStartSpacing = const Duration(milliseconds: 350),
  }) : _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final MusicResolver resolver;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final Duration requestStartSpacing;
  final Map<String, List<MusicSearchCandidate>> _searchCache = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _searchInFlight = {};
  final Map<String, List<MusicSearchCandidate>> _primaryCache = {};
  final Map<String, List<MusicSearchCandidate>> _fallbackCache = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _primaryInFlight = {};
  final Map<String, Future<List<MusicSearchCandidate>>> _fallbackInFlight = {};
  final Map<String, Future<void>> _networkTails = {};
  final Map<String, DateTime> _lastNetworkStarts = {};
  final Map<String, DateTime> _blockedUntil = {};

  Future<ScreenshotMatchResult> match(
    ScreenshotSongDraft draft, {
    bool failOnSourceErrorWhenEmpty = false,
  }) async {
    if (draft.title.trim().isEmpty) {
      return const ScreenshotMatchResult([], null);
    }
    if (resolver is! StagedScreenshotSearchResolver) {
      final candidates = await search(draft);
      return ScreenshotMatchResult(candidates, _recommend(draft, candidates));
    }
    final staged = resolver as StagedScreenshotSearchResolver;

    final key = draft.title.trim().toLowerCase();
    Object? primaryFailure;
    List<MusicSearchCandidate> primary;
    try {
      primary = await _stageSearch(
        key: key,
        cache: _primaryCache,
        inFlight: _primaryInFlight,
        source: MusicDataSource.buguyy.storageValue,
        action: () => staged.searchScreenshotPrimary(draft.title),
      );
    } catch (error) {
      primaryFailure = error;
      primary = const [];
    }
    if (primary.isNotEmpty) {
      return ScreenshotMatchResult(primary, _recommend(draft, primary));
    }

    List<MusicSearchCandidate> fallback;
    try {
      fallback = await _stageSearch(
        key: key,
        cache: _fallbackCache,
        inFlight: _fallbackInFlight,
        source: MusicDataSource.flac.storageValue,
        action: () =>
            staged.searchScreenshotFallback(draft.title, draft.artist),
      );
    } catch (_) {
      if (primaryFailure != null) throw primaryFailure;
      rethrow;
    }
    if (fallback.isEmpty &&
        primaryFailure != null &&
        failOnSourceErrorWhenEmpty) {
      throw primaryFailure;
    }
    return ScreenshotMatchResult(fallback, _recommend(draft, fallback));
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

  MusicSearchCandidate? _recommend(
    ScreenshotSongDraft draft,
    List<MusicSearchCandidate> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final artist = ScreenshotMatchPolicy._normal(draft.artist);
    if (artist.isNotEmpty) {
      for (final candidate in candidates) {
        if (ScreenshotMatchPolicy._normal(candidate.artist) == artist) {
          return candidate;
        }
      }
      if (artist.length >= 2) {
        for (final candidate in candidates) {
          if (ScreenshotMatchPolicy._normal(
            candidate.artist,
          ).contains(artist)) {
            return candidate;
          }
        }
      }
    }
    return candidates.first;
  }

  Future<List<MusicSearchCandidate>> search(ScreenshotSongDraft draft) async {
    final query = draft.title.trim();
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
