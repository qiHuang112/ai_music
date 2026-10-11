import 'music_cache.dart';
import 'resolver_models.dart';
import 'song_match_identity.dart';

/// Indexes downloaded recordings once when the library changes, rather than
/// normalizing every cached song while each search-result row is laid out.
class CachedTrackLookup {
  List<CachedTrack> _records = const [];
  Map<(String, String), String?> _identities = {};
  final _recordings = <String, List<int>>{};
  final _ids = <(MusicDataSource, String, String), List<int>>{};
  final _names = <(MusicDataSource, String, String, String), List<int>>{};

  void replace(List<CachedTrack> records) {
    _records = List.unmodifiable(records);
    _recordings.clear();
    _ids.clear();
    _names.clear();
    final identities = <(String, String), String?>{};
    for (var i = 0; i < records.length; i++) {
      final music = records[i].music;
      _ids
          .putIfAbsent((music.source, music.platform, music.id), () => [])
          .add(i);
      _names
          .putIfAbsent((
            music.source,
            music.platform,
            music.name,
            music.artist,
          ), () => [])
          .add(i);
      if (music.source == MusicDataSource.lan) continue;
      final raw = (music.name, music.artist);
      final key = identities.putIfAbsent(
        raw,
        () => _identities.containsKey(raw)
            ? _identities[raw]
            : _recordingKey(music.name, music.artist),
      );
      if (key != null) _recordings.putIfAbsent(key, () => []).add(i);
    }
    // Retain only identities still present, including cached negative results.
    _identities = identities;
  }

  Iterable<CachedTrack> matching(
    MusicSearchCandidate candidate, {
    required bool allowOtherSources,
  }) {
    final exact = candidate.id.isNotEmpty
        ? _ids[(candidate.source, candidate.platform, candidate.id)]
        : _names[(
            candidate.source,
            candidate.platform,
            candidate.name,
            candidate.artist,
          )];
    final recording =
        allowOtherSources && candidate.source != MusicDataSource.lan
        ? _recordings[_recordingKey(candidate.name, candidate.artist)]
        : null;
    // Preserve library order and avoid returning one record twice when both
    // its provider ID and its recording identity match.
    final indices = {...?exact, ...?recording}.toList()..sort();
    final records = _records;
    return indices.map((i) => records[i]);
  }
}

String? _recordingKey(String name, String artist) {
  final identity = SongMatchIdentity(name, artist);
  if (identity.title.isEmpty || identity.artists.isEmpty) return null;
  return identity.key;
}
