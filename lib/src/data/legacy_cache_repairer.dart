import 'dart:io';

import 'music_cache.dart';
import 'music_resolver.dart';

class LegacyCacheRepairer {
  const LegacyCacheRepairer({
    required this.resolver,
    required this.cacheStore,
    this.minimumScore = 80,
    this.minimumGap = 10,
  });

  final MusicResolver resolver;
  final CachedTrackStore cacheStore;
  final double minimumScore;
  final double minimumGap;

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
      try {
        final candidates = await resolver.search(query, MusicDataSource.buguyy);
        final chosen = _highConfidenceCandidate(candidates);
        if (chosen == null) {
          continue;
        }
        final resolved = await resolver.resolve(chosen);
        final merged = _mergeResolved(track.music, resolved, query);
        await cacheStore.updateCachedMusic(track, merged);
        repaired += 1;
      } catch (_) {
        // Repair is opportunistic; individual failures should not block startup.
      }
    }
    return repaired;
  }

  bool _needsRepair(CachedTrack track) {
    final music = track.music;
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
    return ResolvedMusic(
      query: current.query.trim().isNotEmpty ? current.query : query,
      source: MusicDataSource.buguyy,
      platform: resolved.platform,
      id: resolved.id,
      name: resolved.name.trim().isNotEmpty ? resolved.name : current.name,
      artist: resolved.artist.trim().isNotEmpty
          ? resolved.artist
          : current.artist,
      album: resolved.album.trim().isNotEmpty ? resolved.album : current.album,
      url: current.url.trim().isNotEmpty ? current.url : resolved.url,
      quality: current.quality.format.trim().isNotEmpty
          ? current.quality
          : resolved.quality,
      coverUrl: resolved.coverUrl.trim().isNotEmpty
          ? resolved.coverUrl
          : current.coverUrl,
      lyrics: resolved.lyrics ?? current.lyrics,
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
