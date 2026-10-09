import 'dart:math';

import 'resolver_models.dart';
import 'resolver_utils.dart';
import 'song_match_identity.dart';

class CandidateScorer {
  const CandidateScorer();

  List<String> buildKeywords(String query) {
    final tokens = _splitTokens(query);
    final keywords = <String>{query.trim(), ...tokens};
    if (tokens.length > 1) {
      keywords.add(tokens.reversed.join(' '));
    }
    return keywords
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false);
  }

  double scoreCandidate(
    Map<String, dynamic> item,
    String query,
    String platform,
    String keyword,
    int page,
  ) {
    final tokens = _splitTokens(query);
    final name = item['name']?.toString() ?? '';
    final artist = item['artist']?.toString() ?? '';
    final album = item['album_name']?.toString() ?? '';
    final normName = _normalize(name);
    final normArtist = _normalize(artist);
    final normAlbum = _normalize(album);

    var score = 0.0;
    for (final token in tokens) {
      final normToken = _normalize(token);
      if (normToken.isEmpty) {
        continue;
      }

      if (normName == normToken) {
        score += 95;
      } else if (normName.contains(normToken)) {
        score += 42;
      }

      if (artist == token) {
        score += 95;
      } else if (normArtist == normToken) {
        score += 55;
      } else if (normArtist.contains(normToken)) {
        score += 36;
      }

      if (normAlbum.contains(normToken)) {
        score += 8;
      }
    }

    if (_normalize('$name$artist').contains(_normalize(query))) {
      score += 20;
    }
    if (_normalize(keyword) == normName) {
      score += 20;
    }
    if (normName.isNotEmpty &&
        tokens.any((token) => normName == _normalize(token))) {
      score += 18;
    }

    final duration = intFrom(item['duration']);
    final seconds = duration > 1000 ? duration / 1000 : duration;
    if (seconds >= 150 && seconds <= 360) {
      score += 10;
    }
    if (artist.isNotEmpty && RegExp(r'[-_.]$').hasMatch(artist)) {
      score -= 25;
    }

    final requestedVersion = SongMatchIdentity(query, '').version;
    final candidateVersion = SongMatchIdentity(name, '').version;
    if (requestedVersion != candidateVersion) {
      // Codec quality must not promote a different performance (Live/DJ/etc.).
      score -= 60;
    } else if (requestedVersion.isNotEmpty) {
      score += 30;
    }
    score += _qualityScore(item['minfo']);
    score -= max(0, page - 1) * 0.4;
    if (platform == 'kuwo') {
      score += 2;
    }
    return score;
  }

  bool needsDeepSearch(MusicSearchCandidate? best, String query) {
    if (best == null) {
      return true;
    }
    final tokens = _splitTokens(query);
    final artists = SongMatchIdentity('', best.artist);
    final artistExact = tokens.any(
      (token) => artists.sameArtists(SongMatchIdentity('', token)),
    );
    final nameExact = tokens.any(
      (token) => _normalize(best.name) == _normalize(token),
    );
    if (SongMatchIdentity(query, '').version !=
        SongMatchIdentity(best.name, '').version) {
      return true;
    }
    if (artistExact && nameExact) {
      return false;
    }
    if (best.score < 210) {
      return true;
    }
    return !artistExact && tokens.length > 1;
  }

  bool isStrictArtistCandidate(MusicSearchCandidate candidate, String query) {
    final parts = _queryArtistTitle(query);
    if (parts.tokens.length < 2) {
      return true;
    }
    return SongMatchIdentity(
          '',
          candidate.artist,
        ).sameArtists(SongMatchIdentity('', parts.artist)) &&
        _hasTitleMatch(candidate.name, parts.title) &&
        SongMatchIdentity(candidate.name, '').version ==
            SongMatchIdentity(parts.title, '').version;
  }

  bool isLooseArtistTitleCandidate(
    MusicSearchCandidate candidate,
    String query,
  ) {
    final parts = _queryArtistTitle(query);
    if (parts.tokens.length < 2) {
      return true;
    }
    return _hasTitleMatch(candidate.name, parts.title) &&
        _hasLooseArtistMatch(candidate.artist, parts.artist);
  }
}

bool isStrictArtistCandidate(MusicSearchCandidate candidate, String query) {
  return const CandidateScorer().isStrictArtistCandidate(candidate, query);
}

bool isLooseArtistTitleCandidate(MusicSearchCandidate candidate, String query) {
  return const CandidateScorer().isLooseArtistTitleCandidate(candidate, query);
}

double _qualityScore(Object? minfo) {
  final qualities = (minfo is List ? minfo : [])
      .map(MusicQuality.fromJson)
      .toList(growable: false);
  final quality = bestQuality(qualities, 'flac');
  if (quality == null) {
    return 0;
  }
  final format = quality.format.toLowerCase();
  final bitrate = double.tryParse(quality.bitrate) ?? 0;
  if (format == 'flac') {
    return 30 + min(20, bitrate / 80);
  }
  if (format == 'mp3' && bitrate >= 320) {
    return 20;
  }
  return 5;
}

String _normalize(Object? value) => normalizeSongText(value?.toString() ?? '');

String _normalizeTitleBase(Object? value) =>
    SongMatchIdentity(value?.toString() ?? '', '').title;

List<String> _splitTokens(String query) {
  return query
      .trim()
      .split(RegExp(r'[\s,，/]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

_ArtistTitle _queryArtistTitle(String query) {
  final tokens = _splitTokens(query);
  if (tokens.length < 2) {
    return _ArtistTitle(
      tokens: tokens,
      artist: '',
      title: _normalize(tokens.join()),
    );
  }
  return _ArtistTitle(
    tokens: tokens,
    artist: tokens.first,
    title: tokens.skip(1).join(' '),
  );
}

bool _hasLooseArtistMatch(Object? candidateArtist, String queryArtist) {
  final artist = artistNamesForMatch(candidateArtist?.toString() ?? '');
  final query = artistNamesForMatch(queryArtist);
  if (query.isEmpty || artist.isEmpty) return true;
  // A shared credited artist is useful for duet recall; two shared Chinese
  // characters alone are not evidence that these are the same performer.
  return artist.intersection(query).isNotEmpty;
}

bool _hasTitleMatch(Object? candidateName, String queryTitle) {
  final name = _normalize(candidateName);
  final baseName = _normalizeTitleBase(candidateName);
  queryTitle = _normalizeTitleBase(queryTitle);
  if (queryTitle.isEmpty || name.isEmpty) {
    return true;
  }
  if (name == queryTitle || baseName == queryTitle) {
    return true;
  }
  if (queryTitle.length < 3) {
    return false;
  }
  return baseName.contains(queryTitle) ||
      queryTitle.contains(baseName) ||
      name.contains(queryTitle);
}

class _ArtistTitle {
  const _ArtistTitle({
    required this.tokens,
    required this.artist,
    required this.title,
  });

  final List<String> tokens;
  final String artist;
  final String title;
}
