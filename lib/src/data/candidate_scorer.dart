import 'dart:math';

import 'resolver_models.dart';
import 'resolver_utils.dart';

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
    final artistExact = tokens.any((token) => best.artist == token);
    final nameExact = tokens.any(
      (token) => _normalize(best.name) == _normalize(token),
    );
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
    return _normalize(candidate.artist) == parts.artist &&
        _hasTitleMatch(candidate.name, parts.title);
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

String _normalize(Object? value) {
  return value.toString().toLowerCase().replaceAll(
    RegExp(r'''[\s\-_.＿—–()（）《》〈〉【】\[\]{}"'“”‘’]'''),
    '',
  );
}

String _normalizeTitleBase(Object? value) {
  return _normalize(
    value
        .toString()
        .replaceAll(RegExp(r'[（(][^（）()]{1,12}[）)]'), '')
        .replaceAll(
          RegExp(r'(?:国语|粤语|国|粤|现场版|现场|live|remix|伴奏)$', caseSensitive: false),
          '',
        ),
  );
}

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
    artist: _normalize(tokens.first),
    title: _normalize(tokens.skip(1).join()),
  );
}

bool _hasLooseArtistMatch(Object? candidateArtist, String queryArtist) {
  final artist = _normalize(candidateArtist);
  if (queryArtist.isEmpty || artist.isEmpty) {
    return true;
  }
  if (artist == queryArtist ||
      artist.contains(queryArtist) ||
      queryArtist.contains(artist)) {
    return true;
  }

  final common = <String>{};
  for (final rune in queryArtist.runes) {
    final char = String.fromCharCode(rune);
    if (artist.contains(char)) {
      common.add(char);
    }
  }
  return common.length >= min(2, queryArtist.length);
}

bool _hasTitleMatch(Object? candidateName, String queryTitle) {
  final name = _normalize(candidateName);
  final baseName = _normalizeTitleBase(candidateName);
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
