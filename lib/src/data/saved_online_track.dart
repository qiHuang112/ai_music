import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'music_resolver.dart';

class SavedOnlineTrack {
  const SavedOnlineTrack({required this.candidate});

  final MusicSearchCandidate candidate;

  String get trackId {
    final identity = [
      candidate.source.storageValue,
      candidate.platform,
      candidate.id,
      candidate.name.trim().toLowerCase(),
      candidate.artist.trim().toLowerCase(),
    ].join('\u001f');
    return 'online-${sha256.convert(utf8.encode(identity))}';
  }

  Map<String, Object?> toJson() => {
    'query': candidate.query,
    'source': candidate.source.storageValue,
    'platform': candidate.platform,
    'keyword': candidate.keyword,
    'page': candidate.page,
    'id': candidate.id,
    'name': candidate.name,
    'artist': candidate.artist,
    'album': candidate.album,
    'duration': candidate.duration,
    // Direct media URLs expire and are deliberately not persisted.
    'coverUrl': candidate.coverUrl,
    'qualities': [for (final quality in candidate.qualities) quality.toJson()],
    'raw': _persistentRaw(candidate),
  };

  static Map<String, String> _persistentRaw(MusicSearchCandidate candidate) {
    final raw = candidate.raw;
    final keys = candidate.source == MusicDataSource.flac
        ? const [
            'time',
            'sign',
            'lrc',
            'lrcText',
            'lrc_text',
            'lyric',
            'lyricText',
            'lyric_text',
            'lyrics',
            'lyricsText',
            'about',
          ]
        : const ['about', 'lrc', 'lyric', 'lyrics'];
    final nested = raw['raw'];
    final result = <String, String>{};
    for (final key in keys) {
      final value = raw[key] ?? (nested is Map ? nested[key] : null);
      if (value is String && value.trim().isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  static SavedOnlineTrack? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    final source = MusicDataSource.fromStorage(json['source']?.toString());
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final artist = json['artist']?.toString().trim() ?? '';
    if (source == MusicDataSource.auto ||
        source == MusicDataSource.lan ||
        id.isEmpty ||
        name.isEmpty) {
      return null;
    }
    final raw = json['raw'];
    return SavedOnlineTrack(
      candidate: MusicSearchCandidate(
        query: json['query']?.toString() ?? '$artist $name',
        source: source,
        platform: json['platform']?.toString() ?? '',
        keyword: json['keyword']?.toString() ?? name,
        page: (json['page'] as num?)?.toInt() ?? 1,
        id: id,
        name: name,
        artist: artist,
        album: json['album']?.toString() ?? '',
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        link: '',
        coverUrl: json['coverUrl']?.toString() ?? '',
        qualities: [
          for (final row
              in json['qualities'] is List
                  ? json['qualities'] as List
                  : const [])
            MusicQuality.fromJson(row),
        ],
        score: 0,
        raw: raw is Map ? raw.cast<String, dynamic>() : const {},
      ),
    );
  }
}
