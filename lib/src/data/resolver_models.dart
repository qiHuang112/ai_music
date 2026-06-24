import 'dart:io';

enum MusicDataSource {
  auto('auto', 'Auto'),
  buguyy('buguyy', 'BuguYY'),
  flac('flac', 'FLAC');

  const MusicDataSource(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static MusicDataSource fromStorage(String? value) {
    return MusicDataSource.values.firstWhere(
      (source) => source.storageValue == value,
      orElse: () => MusicDataSource.auto,
    );
  }
}

class MusicQuality {
  const MusicQuality({required this.format, this.bitrate = '', this.size = ''});

  factory MusicQuality.fromJson(Object? value) {
    final json = _asStringMap(value);
    return MusicQuality(
      format: json['format']?.toString() ?? '',
      bitrate: json['bitrate']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
    );
  }

  final String format;
  final String bitrate;
  final String size;

  String get label {
    final parts = [
      if (format.trim().isNotEmpty) format.trim().toUpperCase(),
      if (bitrate.trim().isNotEmpty) bitrate.trim(),
      if (size.trim().isNotEmpty) size.trim(),
    ];
    return parts.join(' ');
  }

  Map<String, Object?> toJson() {
    return {'format': format, 'bitrate': bitrate, 'size': size};
  }
}

class MusicSearchCandidate {
  const MusicSearchCandidate({
    required this.query,
    required this.source,
    required this.platform,
    required this.keyword,
    required this.page,
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.duration,
    required this.link,
    required this.coverUrl,
    required this.qualities,
    required this.score,
    required this.raw,
  });

  final String query;
  final MusicDataSource source;
  final String platform;
  final String keyword;
  final int page;
  final String id;
  final String name;
  final String artist;
  final String album;
  final int duration;
  final String link;
  final String coverUrl;
  final List<MusicQuality> qualities;
  final double score;
  final Map<String, dynamic> raw;

  String get sourceLabel => source.label;

  String get qualityLabel {
    final quality = _bestQuality(qualities, 'flac');
    return quality?.label ?? '';
  }

  String get subtitle {
    final parts = [
      if (artist.isNotEmpty) artist,
      if (album.isNotEmpty) album,
      sourceLabel,
    ];
    return parts.join(' - ');
  }
}

class ResolvedMusic {
  const ResolvedMusic({
    required this.query,
    required this.source,
    required this.platform,
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.url,
    required this.quality,
    this.coverUrl = '',
    this.lyrics,
    this.panLink = false,
  });

  final String query;
  final MusicDataSource source;
  final String platform;
  final String id;
  final String name;
  final String artist;
  final String album;
  final String url;
  final MusicQuality quality;
  final String coverUrl;
  final ResolvedLyrics? lyrics;
  final bool panLink;

  factory ResolvedMusic.fromJson(Map<String, dynamic> json) {
    return ResolvedMusic(
      query: json['query']?.toString() ?? '',
      source: MusicDataSource.fromStorage(json['source']?.toString()),
      platform: json['platform']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      quality: MusicQuality.fromJson(json['quality']),
      coverUrl: json['coverUrl']?.toString() ?? '',
      lyrics: ResolvedLyrics.fromJson(json['lyrics']),
      panLink: json['panLink'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'query': query,
      'source': source.storageValue,
      'platform': platform,
      'id': id,
      'name': name,
      'artist': artist,
      'album': album,
      'url': url,
      'quality': quality.toJson(),
      'coverUrl': coverUrl,
      'lyrics': lyrics?.toJson(),
      'panLink': panLink,
    };
  }
}

class ResolvedLyrics {
  const ResolvedLyrics({
    required this.source,
    required this.text,
    required this.lines,
    required this.timed,
  });

  final String source;
  final String text;
  final int lines;
  final bool timed;

  static ResolvedLyrics? fromJson(Object? value) {
    final json = _asStringMap(value);
    final text = json['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      return null;
    }
    return ResolvedLyrics(
      source: json['source']?.toString() ?? '',
      text: text,
      lines: json['lines'] is num
          ? (json['lines'] as num).toInt()
          : int.tryParse(json['lines']?.toString() ?? '') ?? 0,
      timed: json['timed'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return {'source': source, 'text': text, 'lines': lines, 'timed': timed};
  }
}

abstract class MusicResolver {
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  );

  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate);
}

class MusicSearchProgress {
  const MusicSearchProgress({
    required this.candidates,
    required this.isComplete,
    this.error,
  });

  final List<MusicSearchCandidate> candidates;
  final bool isComplete;
  final Object? error;
}

abstract class ProgressiveMusicResolver {
  Stream<MusicSearchProgress> searchProgressively(
    String query,
    MusicDataSource source,
  );
}

class ResolverHttpResponse {
  const ResolverHttpResponse({
    required this.statusCode,
    required this.body,
    required this.finalUrl,
    this.cookies = const [],
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Uri finalUrl;
  final List<Cookie> cookies;
  final Map<String, String> headers;

  bool get ok => statusCode >= 200 && statusCode < 300;
}

abstract class MusicResolverHttp {
  Future<ResolverHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  });

  Future<ResolverHttpResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  });

  Future<ResolverHttpResponse> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  });
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return {};
}

MusicQuality? _bestQuality(List<MusicQuality> qualities, String prefer) {
  if (qualities.isEmpty) {
    return null;
  }
  final preferred = qualities
      .where((quality) => quality.format.toLowerCase() == prefer)
      .firstOrNull;
  if (preferred != null) {
    return preferred;
  }
  final flac = qualities
      .where((quality) => quality.format.toLowerCase() == 'flac')
      .firstOrNull;
  if (flac != null) {
    return flac;
  }
  final mp3 = qualities
      .where(
        (quality) =>
            quality.format.toLowerCase() == 'mp3' && quality.bitrate == '320',
      )
      .firstOrNull;
  return mp3 ?? qualities.first;
}
