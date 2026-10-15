import 'music_source_policy.dart';
import 'resolver_models.dart';
import 'song_match_identity.dart';

/// Search confidence is independent of codec, duration and provider scores.
class AutoSearchPolicy {
  AutoSearchPolicy(String query, {required this.catalog})
    : query = query.trim();

  final String query;
  final MusicSourceCatalog catalog;
  final _identities = <MusicSearchCandidate, SongMatchIdentity>{};
  final _levels = <MusicSearchCandidate, int>{};
  late final _requestedTitle = SongMatchIdentity(query, '');
  late final _requestedArtists = artistNamesForMatch(query);
  late final _requestedVersionDetails = _versionDetails(query, _requestedTitle);

  late final _parts = query
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  late final _explicit = query.split(RegExp(r'\s+[-–—|/]\s+'));
  late final _pairs = <({String artist, String title})>[
    if (_explicit.length == 2) ...[
      (artist: _explicit.first, title: _explicit.last),
      (artist: _explicit.last, title: _explicit.first),
    ],
    for (var i = 1; i < _parts.length; i++) ...[
      (artist: _parts.take(i).join(' '), title: _parts.skip(i).join(' ')),
      (artist: _parts.skip(i).join(' '), title: _parts.take(i).join(' ')),
    ],
  ];
  late final _pairIdentities = [
    for (final pair in _pairs)
      (
        artists: artistNamesForMatch(pair.artist),
        title: SongMatchIdentity(pair.title, ''),
        details: _versionDetails(pair.title, SongMatchIdentity(pair.title, '')),
      ),
  ];

  // Explicit artist fields only: titles containing the name are not evidence.
  late final _prefersBuguyy =
      _requestedArtists.contains('周杰伦') ||
      _pairIdentities.any((pair) => pair.artists.contains('周杰伦'));

  List<MusicDataSource> orderSources(Iterable<MusicDataSource> available) {
    final sources = available.toList();
    if (_prefersBuguyy &&
        catalog.policyFor(MusicDataSource.buguyy)?.fallbackOnly == false &&
        sources.remove(MusicDataSource.buguyy)) {
      sources.insert(0, MusicDataSource.buguyy);
    }
    return sources;
  }

  SongMatchIdentity _identity(MusicSearchCandidate c) =>
      _identities.putIfAbsent(c, () => SongMatchIdentity(c.name, c.artist));

  // Unstructured English words may all belong to a song or artist name.
  // They still receive exact field matching, but do not skip the second source.
  bool get allowsEarlyStop =>
      _pairs.isNotEmpty &&
      (_explicit.length == 2 || RegExp(r'[\u4e00-\u9fff]').hasMatch(query));

  bool _matchesPair(MusicSearchCandidate candidate) {
    final actual = _identity(candidate);
    if (actual.title.isEmpty || actual.artists.isEmpty) return false;
    return _pairIdentities.any((pair) {
      final title = pair.title;
      final artists = pair.artists;
      return artists.isNotEmpty &&
          actual.artists.containsAll(artists) &&
          actual.title == title.title &&
          actual.version == title.version &&
          (pair.details.isEmpty ||
              pair.details == _versionDetails(candidate.name, actual));
    });
  }

  int matchLevel(MusicSearchCandidate candidate) =>
      _levels.putIfAbsent(candidate, () => _matchLevel(candidate));

  int _matchLevel(MusicSearchCandidate candidate) {
    if (_matchesPair(candidate)) return 3;
    final actual = _identity(candidate);
    final requested = _requestedTitle;
    final artists = _requestedArtists;
    if (artists.isNotEmpty && actual.artists.containsAll(artists)) return 2;
    if (actual.artists.isNotEmpty &&
        requested.title.isNotEmpty &&
        actual.title == requested.title &&
        actual.version == requested.version &&
        (_requestedVersionDetails.isEmpty ||
            _requestedVersionDetails ==
                _versionDetails(candidate.name, actual))) {
      return 2;
    }
    final name = normalizeSongText(candidate.name);
    final artist = normalizeSongText(candidate.artist);
    return _parts.any((part) {
          final token = normalizeSongText(part);
          return token.isNotEmpty &&
              (name.contains(token) || artist.contains(token));
        })
        ? 1
        : 0;
  }

  bool hasStrongMatch(Iterable<MusicSearchCandidate> candidates) =>
      candidates.any((c) => matchLevel(c) >= 2);

  bool canStopEarly(Iterable<MusicSearchCandidate> candidates) =>
      allowsEarlyStop && candidates.any(_matchesPair);

  int _priority(MusicSearchCandidate c) =>
      _prefersBuguyy &&
          c.source == MusicDataSource.buguyy &&
          catalog.policyFor(c.source)?.fallbackOnly == false
      ? -1
      : catalog.policyFor(c.source)?.priority ?? 1000;

  List<MusicSearchCandidate> rank(Iterable<MusicSearchCandidate> candidates) {
    final unique = <String, MusicSearchCandidate>{};
    for (final c in candidates) {
      final identity = _identity(c);
      // Preserve complete version/venue/year wording when merging recordings.
      // Missing artist metadata is not evidence of cross-source identity.
      final key = identity.title.isNotEmpty && identity.artists.isNotEmpty
          ? '${normalizeSongText(c.name)}\t${identity.artistKey}\t${identity.version}'
          : '${c.source}\t${c.platform}\t${c.id}\t${c.name}\t${c.artist}';
      final previous = unique[key];
      if (previous == null ||
          _priority(c) < _priority(previous) ||
          (_priority(c) == _priority(previous) && c.score > previous.score)) {
        unique[key] = c;
      }
    }
    final result = unique.values.toList();
    result.sort((a, b) {
      final match = matchLevel(b).compareTo(matchLevel(a));
      if (match != 0) return match;
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final source = _priority(a).compareTo(_priority(b));
      if (source != 0) return source;
      return '${a.platform}\t${a.id}'.compareTo('${b.platform}\t${b.id}');
    });
    return result.take(80).toList(growable: false);
  }
}

// Generic Live/现场 spelling is interchangeable. Extra year, venue or remix
// wording is part of the requested performance and must survive matching.
String _versionDetails(String title, SongMatchIdentity identity) {
  if (identity.version.isEmpty) return '';
  final full = normalizeSongText(title);
  if (!full.startsWith(identity.title)) return full;
  final suffix = full.substring(identity.title.length);
  return _genericVersionOnly.hasMatch(suffix) ? '' : full;
}

final _genericVersionOnly = RegExp(
  r'^(?:live(?:版)?|现场(?:版)?|remix|混音(?:版)?|伴奏|instrumental|翻唱|cover|'
  r'demo|acoustic|纯音乐|哼唱(?:版)?|humming|钢琴版|[哄吹]睡版|'
  r'英文版|中文版|国语版|粤语版|dj(?:版)?|version)*$',
);
