enum PlaybackMode { sequential, loopAll, repeatOne, shuffle }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.filePath = '',
    this.source = '',
    this.sizeBytes = 0,
    this.artworkUri,
    this.duration,
    this.cachedAt,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String source;
  final int sizeBytes;
  final Uri? artworkUri;
  final Duration? duration;
  final DateTime? cachedAt;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? filePath,
    String? source,
    int? sizeBytes,
    Uri? artworkUri,
    Duration? duration,
    DateTime? cachedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      filePath: filePath ?? this.filePath,
      source: source ?? this.source,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      artworkUri: artworkUri ?? this.artworkUri,
      duration: duration ?? this.duration,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  String get playbackSource => filePath.isEmpty ? source : filePath;

  String get subtitle {
    return album.isEmpty ? artist : '$artist - $album';
  }

  String get sizeLabel {
    if (sizeBytes <= 0) {
      return '';
    }
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}

class TrackMetadata {
  const TrackMetadata({
    this.artworkUri,
    this.lyrics = const [],
    this.source = '',
    this.artworkMiss,
    this.lyricsMiss,
    this.lyricsProviderMisses = const [],
  });

  final Uri? artworkUri;
  final List<LyricLine> lyrics;
  final String source;
  final MetadataFieldMiss? artworkMiss;
  final MetadataFieldMiss? lyricsMiss;
  final List<MetadataFieldMiss> lyricsProviderMisses;

  bool get hasArtwork => artworkUri != null;

  bool get hasLyrics => lyrics.isNotEmpty;

  TrackMetadata copyWith({
    Uri? artworkUri,
    List<LyricLine>? lyrics,
    String? source,
    MetadataFieldMiss? artworkMiss,
    MetadataFieldMiss? lyricsMiss,
    List<MetadataFieldMiss>? lyricsProviderMisses,
  }) {
    return TrackMetadata(
      artworkUri: artworkUri ?? this.artworkUri,
      lyrics: lyrics ?? this.lyrics,
      source: source ?? this.source,
      artworkMiss: artworkMiss ?? this.artworkMiss,
      lyricsMiss: lyricsMiss ?? this.lyricsMiss,
      lyricsProviderMisses: lyricsProviderMisses ?? this.lyricsProviderMisses,
    );
  }
}

class MetadataFieldMiss {
  const MetadataFieldMiss({
    required this.until,
    this.provider = '',
    this.status = 'miss',
  });

  final DateTime until;
  final String provider;
  final String status;

  bool isActive(DateTime now) => now.isBefore(until);
}

class Lyric {
  const Lyric({required this.lines});

  final List<LyricLine> lines;
}

class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

class Artwork {
  const Artwork({required this.uri, this.source = ''});

  final Uri uri;
  final String source;
}
