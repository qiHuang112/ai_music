import 'dart:convert';

enum TrackCacheState { remoteOnly, cached, failed }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.fileName,
    required this.extension,
    required this.size,
    required this.sourceUrl,
    this.localPath,
    this.cacheState = TrackCacheState.remoteOnly,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String fileName;
  final String extension;
  final int size;
  final String sourceUrl;
  final String? localPath;
  final TrackCacheState cacheState;

  bool get isCached =>
      cacheState == TrackCacheState.cached && localPath != null;

  String get displaySubtitle {
    if (artist == 'Unknown' && album == 'Local Music') {
      return extension.toUpperCase();
    }
    return '$artist · ${extension.toUpperCase()}';
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? fileName,
    String? extension,
    int? size,
    String? sourceUrl,
    String? localPath,
    bool clearLocalPath = false,
    TrackCacheState? cacheState,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      fileName: fileName ?? this.fileName,
      extension: extension ?? this.extension,
      size: size ?? this.size,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      cacheState: cacheState ?? this.cacheState,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'fileName': fileName,
      'extension': extension,
      'size': size,
      'sourceUrl': sourceUrl,
      'localPath': localPath,
      'cacheState': cacheState.name,
    };
  }

  factory Track.fromJson(Map<String, Object?> json) {
    final stateName = json['cacheState'] as String?;
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? 'Unknown',
      album: json['album'] as String? ?? 'Local Music',
      fileName: json['fileName'] as String,
      extension: json['extension'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sourceUrl: json['sourceUrl'] as String,
      localPath: json['localPath'] as String?,
      cacheState: TrackCacheState.values.firstWhere(
        (state) => state.name == stateName,
        orElse: () => TrackCacheState.remoteOnly,
      ),
    );
  }
}

List<Track> tracksFromLibraryJson(String body) {
  final decoded = jsonDecode(body) as Map<String, Object?>;
  final items = decoded['tracks'] as List<Object?>? ?? const [];
  return items
      .cast<Map<String, Object?>>()
      .map(Track.fromJson)
      .toList(growable: false);
}

String tracksToLibraryJson(List<Track> tracks) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'version': 1,
    'tracks': tracks.map((track) => track.toJson()).toList(),
  });
}
