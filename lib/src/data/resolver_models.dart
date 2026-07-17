import 'dart:io';

enum MusicDataSource {
  auto('auto', 'Auto'),
  buguyy('buguyy', 'BuguYY'),
  flac('flac', 'FLAC'),
  source2t58('source_2t58', '2t58'),
  source22a5('source_22a5', '22a5'),
  gequhai('source_gequhai', '歌曲海'),
  gequbao('source_gequbao', '歌曲宝'),
  kuwoFullAudio('source_kuwo_full_audio', 'Kuwo Full Audio'),
  itunesPreview('itunes_preview', 'iTunes Preview');

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

  bool get isValidating => raw['validationStatus'] == 'validating';

  bool get isClientReady =>
      raw['clientReady'] == true &&
      raw['urlType'] == MediaUrlType.directAudio.storageValue;

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
    this.duration = 0,
    this.urlType = MediaUrlType.directAudio,
    this.canCacheAudio = true,
    this.sourceAttempts = const [],
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
  final int duration;
  final MediaUrlType urlType;
  final bool canCacheAudio;
  final List<SourceAttempt> sourceAttempts;

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
      duration: int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      urlType: MediaUrlType.fromStorage(json['urlType']?.toString()),
      canCacheAudio: json.containsKey('canCacheAudio')
          ? json['canCacheAudio'] == true
          : _defaultCanCacheAudio(
              MediaUrlType.fromStorage(json['urlType']?.toString()),
            ),
      sourceAttempts: SourceAttempt.listFromJson(json['sourceAttempts']),
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
      'duration': duration,
      'urlType': urlType.storageValue,
      'canCacheAudio': canCacheAudio,
      'sourceAttempts': [
        for (final attempt in sourceAttempts) attempt.toJson(),
      ],
    };
  }

  ResolvedMusic copyWith({
    String? url,
    MusicQuality? quality,
    bool? panLink,
    int? duration,
    MediaUrlType? urlType,
    bool? canCacheAudio,
    List<SourceAttempt>? sourceAttempts,
  }) {
    return ResolvedMusic(
      query: query,
      source: source,
      platform: platform,
      id: id,
      name: name,
      artist: artist,
      album: album,
      url: url ?? this.url,
      quality: quality ?? this.quality,
      coverUrl: coverUrl,
      lyrics: lyrics,
      panLink: panLink ?? this.panLink,
      duration: duration ?? this.duration,
      urlType: urlType ?? this.urlType,
      canCacheAudio: canCacheAudio ?? this.canCacheAudio,
      sourceAttempts: sourceAttempts ?? this.sourceAttempts,
    );
  }
}

enum MediaUrlType {
  directAudio('direct_audio'),
  directAudioCandidate('direct_audio_candidate'),
  previewAudio('preview_audio'),
  externalPan('external_pan'),
  htmlPage('html_page'),
  unknown('unknown');

  const MediaUrlType(this.storageValue);

  final String storageValue;

  static MediaUrlType fromStorage(String? value) {
    return MediaUrlType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => MediaUrlType.unknown,
    );
  }
}

bool _defaultCanCacheAudio(MediaUrlType urlType) {
  return switch (urlType) {
    MediaUrlType.directAudio || MediaUrlType.unknown => true,
    MediaUrlType.directAudioCandidate => false,
    MediaUrlType.previewAudio ||
    MediaUrlType.externalPan ||
    MediaUrlType.htmlPage => false,
  };
}

enum SourceAttemptStatus {
  ok('ok'),
  failed('failed'),
  skipped('skipped');

  const SourceAttemptStatus(this.storageValue);

  final String storageValue;

  static SourceAttemptStatus fromStorage(String? value) {
    return SourceAttemptStatus.values.firstWhere(
      (status) => status.storageValue == value,
      orElse: () => SourceAttemptStatus.failed,
    );
  }
}

class SourceAttempt {
  const SourceAttempt({
    required this.query,
    required this.source,
    required this.stage,
    required this.status,
    this.failureCode = '',
    this.reasonCode = '',
    this.candidateId = '',
    this.candidateTitle = '',
    this.candidateArtist = '',
    this.matchConfidence,
    this.mediaUrl = '',
    this.mediaUrlType = MediaUrlType.unknown,
    this.mediaContentType = '',
    this.mediaContentLength,
    this.lyricsStatus = '',
    this.coverUrl = '',
    this.browserPlayable = false,
    this.scriptReproducible = false,
    this.clientReady = false,
    this.mediaValidation = '',
    this.evidenceUrl = '',
    this.coverStatus = '',
  });

  final String query;
  final MusicDataSource source;
  final String stage;
  final SourceAttemptStatus status;
  final String failureCode;
  final String reasonCode;
  final String candidateId;
  final String candidateTitle;
  final String candidateArtist;
  final double? matchConfidence;
  final String mediaUrl;
  final MediaUrlType mediaUrlType;
  final String mediaContentType;
  final int? mediaContentLength;
  final String lyricsStatus;
  final String coverUrl;
  final bool browserPlayable;
  final bool scriptReproducible;
  final bool clientReady;
  final String mediaValidation;
  final String evidenceUrl;
  final String coverStatus;

  factory SourceAttempt.fromJson(Object? value) {
    final json = _asStringMap(value);
    return SourceAttempt(
      query: json['query']?.toString() ?? '',
      source: MusicDataSource.fromStorage(json['source']?.toString()),
      stage: json['stage']?.toString() ?? '',
      status: SourceAttemptStatus.fromStorage(json['status']?.toString()),
      failureCode: json['failureCode']?.toString() ?? '',
      reasonCode: json['reasonCode']?.toString() ?? '',
      candidateId: json['candidateId']?.toString() ?? '',
      candidateTitle: json['candidateTitle']?.toString() ?? '',
      candidateArtist: json['candidateArtist']?.toString() ?? '',
      matchConfidence: json['matchConfidence'] is num
          ? (json['matchConfidence'] as num).toDouble()
          : double.tryParse(json['matchConfidence']?.toString() ?? ''),
      mediaUrl: json['mediaUrl']?.toString() ?? '',
      mediaUrlType: MediaUrlType.fromStorage(json['mediaUrlType']?.toString()),
      mediaContentType: json['mediaContentType']?.toString() ?? '',
      mediaContentLength: json['mediaContentLength'] is num
          ? (json['mediaContentLength'] as num).toInt()
          : int.tryParse(json['mediaContentLength']?.toString() ?? ''),
      lyricsStatus: json['lyricsStatus']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      browserPlayable: json['browserPlayable'] == true,
      scriptReproducible: json['scriptReproducible'] == true,
      clientReady: json['clientReady'] == true,
      mediaValidation: json['mediaValidation']?.toString() ?? '',
      evidenceUrl: json['evidenceUrl']?.toString() ?? '',
      coverStatus: json['coverStatus']?.toString() ?? '',
    );
  }

  static List<SourceAttempt> listFromJson(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map(SourceAttempt.fromJson).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return {
      'query': query,
      'source': source.storageValue,
      'stage': stage,
      'status': status.storageValue,
      'failureCode': failureCode,
      'reasonCode': reasonCode,
      'candidateId': candidateId,
      'candidateTitle': candidateTitle,
      'candidateArtist': candidateArtist,
      'matchConfidence': matchConfidence,
      'mediaUrl': mediaUrl,
      'mediaUrlType': mediaUrlType.storageValue,
      'mediaContentType': mediaContentType,
      'mediaContentLength': mediaContentLength,
      'lyricsStatus': lyricsStatus,
      'coverUrl': coverUrl,
      'browserPlayable': browserPlayable,
      'scriptReproducible': scriptReproducible,
      'clientReady': clientReady,
      'mediaValidation': mediaValidation,
      'evidenceUrl': evidenceUrl,
      'coverStatus': coverStatus,
    };
  }
}

class SourceDownloadException implements Exception {
  const SourceDownloadException(
    this.message, {
    this.failureCode = '',
    this.sourceAttempts = const [],
  });

  final String message;
  final String failureCode;
  final List<SourceAttempt> sourceAttempts;

  @override
  String toString() {
    if (failureCode.isEmpty) {
      return message;
    }
    return '$message ($failureCode)';
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

abstract class PreferredMusicResolver {
  Future<ResolvedMusic> resolveWithPrefer(
    MusicSearchCandidate candidate, {
    required String prefer,
  });
}

class MusicSearchProgress {
  const MusicSearchProgress({
    required this.candidates,
    required this.isComplete,
    this.page = 1,
    this.hasNextPage = false,
    this.error,
  });

  final List<MusicSearchCandidate> candidates;
  final bool isComplete;
  final int page;
  final bool hasNextPage;
  final Object? error;
}

abstract class ProgressiveMusicResolver {
  Stream<MusicSearchProgress> searchProgressively(
    String query,
    MusicDataSource source,
  );
}

abstract class PaginatedProgressiveMusicResolver {
  Stream<MusicSearchProgress> searchPageProgressively(
    String query,
    MusicDataSource source, {
    required int page,
  });
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

  Future<ResolverHttpResponse> head(
    Uri uri, {
    Map<String, String> headers = const {},
  });

  Future<ResolverHttpResponse> range(
    Uri uri, {
    int start = 0,
    int end = 0,
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
