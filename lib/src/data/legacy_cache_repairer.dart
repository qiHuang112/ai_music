import 'dart:io';

import 'music_cache.dart';
import 'music_resolver.dart';
import 'song_match_identity.dart';

class LegacyCacheRepairer {
  const LegacyCacheRepairer({
    required this.resolver,
    required this.cacheStore,
    this.minimumScore = 80,
    this.minimumGap = 10,
    this.sourceProvider,
  });

  final MusicResolver resolver;
  final CachedTrackStore cacheStore;
  final double minimumScore;
  final double minimumGap;
  final MusicDataSource Function()? sourceProvider;

  MusicDataSource get _source => sourceProvider?.call() ?? MusicDataSource.flac;

  Future<int> repair(List<CachedTrack> tracks) async {
    var repaired = 0;
    for (final track in tracks) {
      if (!_needsRepair(track)) {
        continue;
      }
      final query = _repairQuery(track);
      if (query.isEmpty) {
        continue;
      }
      while (true) {
        final source = _source;
        try {
          final candidates = await resolver.search(query, source);
          if (source != _source) continue;
          final chosen = _highConfidenceCandidate([
            for (final candidate in candidates)
              if ((source == MusicDataSource.auto ||
                      candidate.source == source) &&
                  _matchesKnownIdentity(track.music, candidate))
                candidate,
          ]);
          if (chosen == null) break;
          final resolved = resolver is AutoSourceHealthResolver
              ? await (resolver as AutoSourceHealthResolver)
                    .resolveForSourceMode(chosen, source)
              : await resolver.resolve(chosen);
          if (source != _source) continue;
          if (!SongMatchIdentity(
            chosen.name,
            chosen.artist,
          ).sameRecording(SongMatchIdentity(resolved.name, resolved.artist))) {
            break;
          }
          final merged = _mergeResolved(track.music, resolved, query);
          await cacheStore.updateCachedMusic(track, merged);
          repaired += 1;
        } catch (_) {
          if (source != _source) continue;
          // Repair is opportunistic; individual failures should not block startup.
        }
        break;
      }
    }
    return repaired;
  }

  bool _hasKnownTitle(ResolvedMusic music) =>
      music.name.trim().isNotEmpty &&
      normalizeSongText(music.name) != 'unknowntitle';

  bool _hasKnownArtist(ResolvedMusic music) =>
      music.artist.trim().isNotEmpty &&
      normalizeSongText(music.artist) != 'unknownartist';

  bool _matchesKnownIdentity(
    ResolvedMusic current,
    MusicSearchCandidate candidate,
  ) {
    final expected = SongMatchIdentity(current.name, current.artist);
    final found = SongMatchIdentity(candidate.name, candidate.artist);
    if (_hasKnownTitle(current) &&
        (expected.title != found.title || expected.version != found.version)) {
      return false;
    }
    return !_hasKnownArtist(current) || expected.sameArtists(found);
  }

  bool _needsRepair(CachedTrack track) {
    final music = track.music;
    if (music.source == MusicDataSource.lan) {
      return false;
    }
    final missingTitle =
        music.name.trim().isEmpty ||
        music.name.trim() == music.query.trim() ||
        music.name.trim().toLowerCase() == 'unknown-title';
    final missingArtist =
        music.artist.trim().isEmpty ||
        music.artist.trim().toLowerCase() == 'unknown artist' ||
        music.artist.trim().toLowerCase() == 'unknown-artist';
    final missingLyrics =
        music.lyrics == null && track.lyricsPath.trim().isEmpty;
    final missingArtwork = music.coverUrl.trim().isEmpty;
    final legacyIdentity = music.id.trim().isEmpty;
    return legacyIdentity ||
        missingTitle ||
        missingArtist ||
        missingLyrics ||
        missingArtwork;
  }

  MusicSearchCandidate? _highConfidenceCandidate(
    List<MusicSearchCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    final top = sorted.first;
    final secondScore = sorted.length > 1 ? sorted[1].score : 0.0;
    if (top.score < minimumScore) {
      return null;
    }
    if (sorted.length > 1 && top.score - secondScore < minimumGap) {
      return null;
    }
    return top;
  }

  ResolvedMusic _mergeResolved(
    ResolvedMusic current,
    ResolvedMusic resolved,
    String query,
  ) {
    final hasIdentity = current.id.trim().isNotEmpty;
    return ResolvedMusic(
      query: current.query.trim().isNotEmpty ? current.query : query,
      source: hasIdentity ? current.source : resolved.source,
      platform: hasIdentity ? current.platform : resolved.platform,
      id: hasIdentity ? current.id : resolved.id,
      name: _hasKnownTitle(current) ? current.name : resolved.name,
      artist: _hasKnownArtist(current) ? current.artist : resolved.artist,
      album: current.album.trim().isNotEmpty ? current.album : resolved.album,
      url: current.url.trim().isNotEmpty ? current.url : resolved.url,
      quality: current.quality.format.trim().isNotEmpty
          ? current.quality
          : resolved.quality,
      coverUrl: current.coverUrl.trim().isNotEmpty
          ? current.coverUrl
          : resolved.coverUrl,
      lyrics: current.lyrics ?? resolved.lyrics,
      panLink: current.panLink,
    );
  }

  String _repairQuery(CachedTrack track) {
    final music = track.music;
    final direct = [
      music.artist,
      music.name,
    ].map((value) => value.trim()).where((value) => value.isNotEmpty).join(' ');
    if (direct.trim().isNotEmpty && !direct.toLowerCase().contains('unknown')) {
      return direct;
    }
    if (music.query.trim().isNotEmpty &&
        !music.query.toLowerCase().contains('unknown')) {
      return music.query.trim();
    }
    return _queryFromFileName(track.filePath);
  }

  String _queryFromFileName(String filePath) {
    final name = File(filePath).uri.pathSegments.last;
    final withoutExtension = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final withoutHash = withoutExtension.replaceFirst(
      RegExp(r'-[0-9a-f]{8,16}$', caseSensitive: false),
      '',
    );
    return withoutHash
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s*-\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
