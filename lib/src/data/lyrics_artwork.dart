// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'challenge_client.dart';
import 'buguyy_resolver.dart';
import '../domain/music_models.dart';
import '../platform/app_storage.dart';
import 'json_file_store.dart';
import 'lyrics_normalizer.dart';
import 'music_cache.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';
import 'resolver_utils.dart';

export 'lyrics_normalizer.dart'
    show extractLyricsText, normalizeLyricsText, parseLrcLines;

abstract class TrackMetadataProvider {
  Future<TrackMetadata> find(CachedTrack track);
}

abstract class ArtworkMetadataProvider implements TrackMetadataProvider {}

abstract class LyricsMetadataProvider implements TrackMetadataProvider {}

abstract class NetworkMetadataProvider implements TrackMetadataProvider {}

class CandidateArtworkProvider
    implements TrackMetadataProvider, ArtworkMetadataProvider {
  const CandidateArtworkProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final uri = artworkUriFromText(track.music.coverUrl);
    return TrackMetadata(artworkUri: uri, source: uri == null ? '' : 'source');
  }
}

class EmptyLyricsProvider
    implements TrackMetadataProvider, LyricsMetadataProvider {
  const EmptyLyricsProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    return const TrackMetadata();
  }
}

class ResolvedLyricsProvider
    implements TrackMetadataProvider, LyricsMetadataProvider {
  const ResolvedLyricsProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final lyrics = track.music.lyrics;
    if (lyrics == null || lyrics.text.trim().isEmpty) {
      return const TrackMetadata();
    }
    final lines = parseLrcLines(lyrics.text);
    return TrackMetadata(lyrics: lines, source: lyrics.source);
  }
}

class CachedLyricsFileProvider
    implements TrackMetadataProvider, LyricsMetadataProvider {
  const CachedLyricsFileProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final path = track.lyricsPath.trim().isNotEmpty
        ? track.lyricsPath
        : lyricsPathForAudioPath(track.filePath);
    if (path.isEmpty) {
      return const TrackMetadata();
    }
    final file = File(path);
    if (!await file.exists()) {
      return const TrackMetadata();
    }
    final lines = parseLrcLines(await file.readAsString());
    return TrackMetadata(lyrics: lines, source: 'cache:lrc');
  }
}

class TrackMetadataRepository {
  TrackMetadataRepository({
    MetadataCacheStore? cacheStore,
    List<TrackMetadataProvider>? providers,
    MusicResolverHttp? httpClient,
    DateTime Function()? now,
    Duration? missTtl,
    Duration? providerTimeout,
  }) : _cacheStore = cacheStore ?? MetadataCacheStore(),
       _providers =
           providers ??
           _defaultProviders(httpClient ?? HttpMusicResolverClient()),
       _now = now ?? DateTime.now,
       _missTtl = missTtl ?? defaultMissTtl,
       _providerTimeout = providerTimeout ?? defaultProviderTimeout;

  final MetadataCacheStore _cacheStore;
  final List<TrackMetadataProvider> _providers;
  final DateTime Function() _now;
  final Map<String, DateTime> _lyricsMissUntil = {};
  final Map<String, DateTime> _artworkMissUntil = {};
  final Duration _missTtl;
  final Duration _providerTimeout;

  static const Duration defaultMissTtl = Duration(minutes: 30);
  static const Duration defaultProviderTimeout = Duration(seconds: 8);

  Future<TrackMetadata> load(CachedTrack track) async {
    return _load(track, bypassMissTtl: false);
  }

  Future<TrackMetadata> loadBypassingMetadataMiss(CachedTrack track) async {
    return _load(track, bypassMissTtl: true);
  }

  Future<TrackMetadata> loadBypassingLyricsMiss(CachedTrack track) {
    return loadBypassingMetadataMiss(track);
  }

  Future<TrackMetadata> _load(
    CachedTrack track, {
    required bool bypassMissTtl,
  }) async {
    var metadata =
        await _cacheStore.read(track.cacheId) ?? const TrackMetadata();
    if (_isComplete(metadata)) {
      return metadata;
    }
    // 字段级 miss 避免歌词失败挡住封面，也避免空结果覆盖已有成功值。
    final cachedLyricsMiss = _freshMiss(metadata.lyricsMiss);
    final cachedArtworkMiss = _freshMiss(metadata.artworkMiss);
    final lyricsMissActive =
        !bypassMissTtl &&
        (cachedLyricsMiss != null ||
            _hasFreshMiss(_lyricsMissUntil, track.cacheId));
    final artworkMissActive =
        !bypassMissTtl &&
        (cachedArtworkMiss != null ||
            _hasFreshMiss(_artworkMissUntil, track.cacheId));
    final hadLyrics = metadata.hasLyrics;
    final hadArtwork = metadata.hasArtwork;
    String? attemptedLyricsProvider;
    String? attemptedArtworkProvider;
    for (final provider in _providers) {
      if (_shouldSkipProvider(
        provider,
        metadata,
        skipNetworkLyrics: lyricsMissActive,
        skipNetworkArtwork: artworkMissActive,
      )) {
        continue;
      }
      if (provider is NetworkMetadataProvider) {
        if (provider is LyricsMetadataProvider && !metadata.hasLyrics) {
          attemptedLyricsProvider = _providerId(provider);
        }
        if (provider is ArtworkMetadataProvider && !metadata.hasArtwork) {
          attemptedArtworkProvider = _providerId(provider);
        }
      }
      final next = await _findWithTimeout(provider, track);
      if (!metadata.hasLyrics && next.hasLyrics) {
        await _writeLyricsSidecar(track, next.lyrics);
      }
      metadata = _merge(metadata, next);
      if (_isComplete(metadata)) {
        break;
      }
    }
    MetadataFieldMiss? nextLyricsMiss;
    MetadataFieldMiss? nextArtworkMiss;
    if (metadata.hasLyrics) {
      _lyricsMissUntil.remove(track.cacheId);
    } else if (!hadLyrics && !lyricsMissActive) {
      nextLyricsMiss = MetadataFieldMiss(
        until: _now().add(_missTtl),
        provider: attemptedLyricsProvider ?? 'metadata',
      );
      _lyricsMissUntil[track.cacheId] = nextLyricsMiss.until;
    } else if (!bypassMissTtl) {
      nextLyricsMiss = cachedLyricsMiss ?? metadata.lyricsMiss;
    }
    if (metadata.hasArtwork) {
      _artworkMissUntil.remove(track.cacheId);
    } else if (!hadArtwork && !artworkMissActive) {
      nextArtworkMiss = MetadataFieldMiss(
        until: _now().add(_missTtl),
        provider: attemptedArtworkProvider ?? 'metadata',
      );
      _artworkMissUntil[track.cacheId] = nextArtworkMiss.until;
    } else if (!bypassMissTtl) {
      nextArtworkMiss = cachedArtworkMiss ?? metadata.artworkMiss;
    }
    metadata = TrackMetadata(
      artworkUri: metadata.artworkUri,
      lyrics: metadata.lyrics,
      source: metadata.source,
      artworkMiss: metadata.hasArtwork ? null : nextArtworkMiss,
      lyricsMiss: metadata.hasLyrics ? null : nextLyricsMiss,
    );
    await _cacheStore.write(track.cacheId, metadata);
    return metadata;
  }

  Future<void> delete(String cacheId) {
    return _cacheStore.delete(cacheId);
  }

  TrackMetadata _merge(TrackMetadata current, TrackMetadata next) {
    return TrackMetadata(
      artworkUri: current.artworkUri ?? next.artworkUri,
      lyrics: current.lyrics.isNotEmpty ? current.lyrics : next.lyrics,
      source: current.source.isNotEmpty ? current.source : next.source,
    );
  }

  bool _isComplete(TrackMetadata metadata) {
    return metadata.hasArtwork && metadata.hasLyrics;
  }

  bool _shouldSkipProvider(
    TrackMetadataProvider provider,
    TrackMetadata metadata, {
    required bool skipNetworkLyrics,
    required bool skipNetworkArtwork,
  }) {
    if (skipNetworkLyrics &&
        provider is LyricsMetadataProvider &&
        provider is NetworkMetadataProvider) {
      return true;
    }
    if (skipNetworkArtwork &&
        provider is ArtworkMetadataProvider &&
        provider is NetworkMetadataProvider) {
      return true;
    }
    final artworkOnly =
        provider is ArtworkMetadataProvider &&
        provider is! LyricsMetadataProvider;
    if (metadata.hasArtwork && artworkOnly) {
      return true;
    }
    final lyricsOnly =
        provider is LyricsMetadataProvider &&
        provider is! ArtworkMetadataProvider;
    if (metadata.hasLyrics && lyricsOnly) {
      return true;
    }
    return false;
  }

  Future<TrackMetadata> _findWithTimeout(
    TrackMetadataProvider provider,
    CachedTrack track,
  ) async {
    try {
      return await provider.find(track).timeout(_providerTimeout);
    } catch (_) {
      return const TrackMetadata();
    }
  }

  bool _hasFreshMiss(Map<String, DateTime> misses, String cacheId) {
    final until = misses[cacheId];
    if (until == null) {
      return false;
    }
    if (_now().isBefore(until)) {
      return true;
    }
    misses.remove(cacheId);
    return false;
  }

  MetadataFieldMiss? _freshMiss(MetadataFieldMiss? miss) {
    if (miss == null) {
      return null;
    }
    return miss.isActive(_now()) ? miss : null;
  }

  Future<void> _writeLyricsSidecar(
    CachedTrack track,
    List<LyricLine> lyrics,
  ) async {
    if (lyrics.isEmpty) {
      return;
    }
    final path = track.lyricsPath.trim().isNotEmpty
        ? track.lyricsPath
        : lyricsPathForAudioPath(track.filePath);
    if (path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      return;
    }
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final content = [
      for (final line in lyrics) '${_formatLrcTime(line.time)}${line.text}',
      '',
    ].join('\n');
    try {
      await temp.writeAsString(content);
      if (await file.exists()) {
        await temp.delete();
      } else {
        await temp.rename(file.path);
      }
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }
}

String _formatLrcTime(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final centiseconds = (value.inMilliseconds.remainder(1000) ~/ 10)
      .toString()
      .padLeft(2, '0');
  return '[$minutes:$seconds.$centiseconds]';
}

List<TrackMetadataProvider> _defaultProviders(MusicResolverHttp httpClient) {
  // provider 顺序从“零成本/本地”到“网络兜底”，避免每次进播放页都重新搜歌词。
  return [
    const CandidateArtworkProvider(),
    const ResolvedLyricsProvider(),
    const CachedLyricsFileProvider(),
    BuguyyLyricsProvider(httpClient: httpClient),
    ItunesArtworkProvider(httpClient: httpClient),
    LrcLibLyricsProvider(httpClient: httpClient),
    LrcApiLyricsProvider(httpClient: httpClient),
    const EmptyLyricsProvider(),
  ];
}

class BuguyyLyricsProvider
    implements
        TrackMetadataProvider,
        LyricsMetadataProvider,
        NetworkMetadataProvider {
  BuguyyLyricsProvider({
    required MusicResolverHttp httpClient,
    String? baseUrl,
    bool? useAppleEndpoint,
  }) : baseUrl =
           baseUrl ?? defaultBuguyyBaseUrl(isApplePlatform: useAppleEndpoint),
       _http = httpClient;

  final MusicResolverHttp _http;
  final String baseUrl;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    if (track.music.source != MusicDataSource.buguyy ||
        track.music.id.trim().isEmpty) {
      return const TrackMetadata();
    }
    try {
      for (final path in const ['/api/geturl', '/api/getdown']) {
        final json = await _json(path, {'id': track.music.id});
        final lyrics = parseLrcLines(extractLyricsText(json));
        if (lyrics.isNotEmpty) {
          return TrackMetadata(lyrics: lyrics, source: 'buguyy');
        }
      }
    } catch (_) {
      return const TrackMetadata();
    }
    return const TrackMetadata();
  }

  Future<Map<String, dynamic>> _json(
    String pathname,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$baseUrl$pathname').replace(
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      },
    );
    final response = await getBuguyyWithRetry(
      _http,
      uri,
      headers: {
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9',
        'referer': '$baseUrl/',
        'user-agent': ChallengeClient.userAgent,
      },
    );
    if (!response.ok) {
      throw HttpException(
        'buguyy lyrics HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return asStringMap(
      response.body.isEmpty ? const {} : jsonDecode(response.body),
    );
  }
}

class ItunesArtworkProvider
    implements
        TrackMetadataProvider,
        ArtworkMetadataProvider,
        NetworkMetadataProvider {
  const ItunesArtworkProvider({
    required MusicResolverHttp httpClient,
    this.baseUrl = 'https://itunes.apple.com/search',
  }) : _http = httpClient;

  final MusicResolverHttp _http;
  final String baseUrl;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final term = _metadataTerm(track);
    if (term.isEmpty) {
      return const TrackMetadata();
    }
    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          'term': term,
          'entity': 'song',
          'limit': '5',
          'media': 'music',
          'country': 'CN',
        },
      );
      final response = await _http.get(
        uri,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'user-agent': ChallengeClient.userAgent,
        },
      );
      if (!response.ok) {
        return const TrackMetadata();
      }
      final decoded = jsonDecode(response.body);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List) {
        return const TrackMetadata();
      }
      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final row in results.whereType<Map>()) {
        final json = row.cast<String, dynamic>();
        final score = _trackMatchScore(track, json);
        if (score < 0 || score <= bestScore) {
          continue;
        }
        best = json;
        bestScore = score;
      }
      if (best != null) {
        final json = best;
        final artwork = _bestItunesArtwork(json);
        final uri = artworkUriFromText(artwork);
        if (uri != null) {
          return TrackMetadata(artworkUri: uri, source: 'itunes');
        }
      }
    } catch (_) {
      return const TrackMetadata();
    }
    return const TrackMetadata();
  }

  String _bestItunesArtwork(Map<String, dynamic> json) {
    final raw =
        json['artworkUrl100']?.toString() ??
        json['artworkUrl60']?.toString() ??
        json['artworkUrl30']?.toString() ??
        '';
    return raw.replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/600x600bb.');
  }
}

class LrcLibLyricsProvider
    implements
        TrackMetadataProvider,
        LyricsMetadataProvider,
        NetworkMetadataProvider {
  const LrcLibLyricsProvider({
    required MusicResolverHttp httpClient,
    this.baseUrl = 'https://lrclib.net',
  }) : _http = httpClient;

  final MusicResolverHttp _http;
  final String baseUrl;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final title = _trackTitle(track);
    if (title.isEmpty) {
      return const TrackMetadata();
    }
    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/api/search').replace(
          queryParameters: {
            'track_name': title,
            if (track.music.artist.trim().isNotEmpty)
              'artist_name': track.music.artist.trim(),
            if (track.music.album.trim().isNotEmpty)
              'album_name': track.music.album.trim(),
          },
        ),
        headers: {
          'accept': 'application/json, text/plain, */*',
          'user-agent': ChallengeClient.userAgent,
        },
      );
      if (!response.ok) {
        return const TrackMetadata();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return const TrackMetadata();
      }
      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final row in decoded.whereType<Map>()) {
        final json = row.cast<String, dynamic>();
        final score = _trackMatchScore(track, json);
        if (score < 0 || score <= bestScore) {
          continue;
        }
        best = json;
        bestScore = score;
      }
      if (best != null) {
        final json = best;
        final text =
            json['syncedLyrics']?.toString() ??
            json['plainLyrics']?.toString() ??
            '';
        final lines = parseLrcLines(text);
        if (lines.isNotEmpty) {
          return TrackMetadata(lyrics: lines, source: 'lrclib');
        }
      }
    } catch (_) {
      return const TrackMetadata();
    }
    return const TrackMetadata();
  }
}

class LrcApiLyricsProvider
    implements
        TrackMetadataProvider,
        LyricsMetadataProvider,
        NetworkMetadataProvider {
  const LrcApiLyricsProvider({
    required MusicResolverHttp httpClient,
    this.baseUrl = 'https://api.lrc.cx',
  }) : _http = httpClient;

  final MusicResolverHttp _http;
  final String baseUrl;

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    try {
      final single = await _get('/api/v1/lyrics/single', track);
      final singleLines = parseLrcLines(single.body);
      if (single.ok && singleLines.isNotEmpty) {
        return TrackMetadata(lyrics: singleLines, source: 'lrcapi');
      }

      final advance = await _get('/api/v1/lyrics/advance', track);
      if (!advance.ok) {
        return const TrackMetadata();
      }
      final decoded = jsonDecode(advance.body);
      final lyricsText = extractLyricsText(decoded);
      final advanceLines = parseLrcLines(lyricsText);
      if (advanceLines.isNotEmpty) {
        return TrackMetadata(lyrics: advanceLines, source: 'lrcapi');
      }
    } catch (_) {
      return const TrackMetadata();
    }
    return const TrackMetadata();
  }

  Future<ResolverHttpResponse> _get(String path, CachedTrack track) {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        'title': track.music.name.isNotEmpty
            ? track.music.name
            : track.music.query,
        'album': track.music.album,
        'artist': track.music.artist,
      },
    );
    return _http.get(
      uri,
      headers: {
        'accept': path.endsWith('advance')
            ? 'application/json, text/plain, */*'
            : 'text/html, text/plain, */*',
        'user-agent': ChallengeClient.userAgent,
      },
    );
  }
}

String _metadataTerm(CachedTrack track) {
  return [
    if (track.music.name.trim().isNotEmpty) track.music.name.trim(),
    if (track.music.artist.trim().isNotEmpty) track.music.artist.trim(),
  ].join(' ');
}

String _trackTitle(CachedTrack track) {
  return track.music.name.trim().isNotEmpty
      ? track.music.name.trim()
      : track.music.query.trim();
}

int _trackMatchScore(CachedTrack track, Map<String, dynamic> json) {
  final title = _normalizeMatch(_trackTitle(track));
  final artist = _normalizeMatch(track.music.artist);
  final album = _normalizeMatch(track.music.album);
  final candidates = [
    json['trackName'],
    json['name'],
    json['title'],
    json['track_name'],
  ].map((value) => _normalizeMatch(value?.toString() ?? ''));
  final artistCandidates = [
    json['artistName'],
    json['artist'],
    json['artist_name'],
  ].map((value) => _normalizeMatch(value?.toString() ?? ''));
  final albumCandidates = [
    json['collectionName'],
    json['albumName'],
    json['album'],
    json['album_name'],
  ].map((value) => _normalizeMatch(value?.toString() ?? ''));
  final titleMatches =
      title.isEmpty || candidates.any((value) => value == title);
  final artistMatches =
      artist.isEmpty || artistCandidates.any((value) => value == artist);
  if (!titleMatches || !artistMatches) {
    return -1;
  }
  var score = 100;
  if (album.isNotEmpty) {
    final nonEmptyAlbums = albumCandidates
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (nonEmptyAlbums.any((value) => value == album)) {
      score += 30;
    } else if (nonEmptyAlbums.isNotEmpty) {
      score -= 40;
    }
  }
  return score;
}

String _normalizeMatch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_·.]+'), '')
      .replaceAll(RegExp(r'[（(].*?[）)]'), '')
      .trim();
}

String _providerId(TrackMetadataProvider provider) {
  final type = provider.runtimeType.toString();
  return type
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
}

class MetadataCacheStore {
  MetadataCacheStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? _defaultRoot;

  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _jsonStore = const JsonFileStore();

  Future<TrackMetadata?> read(String cacheId) async {
    final file = await _metadataFile(cacheId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        await _backupCorrupt(file);
        return null;
      }
      return _metadataFromJson(decoded);
    } catch (_) {
      await _backupCorrupt(file);
      return null;
    }
  }

  Future<void> write(String cacheId, TrackMetadata metadata) async {
    final root = await _rootProvider();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final file = _metadataFileIn(root, cacheId);
    await _jsonStore.write(file, _metadataToJson(metadata));
  }

  Future<void> delete(String cacheId) async {
    final file = await _metadataFile(cacheId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _metadataFile(String cacheId) async {
    final root = await _rootProvider();
    return _metadataFileIn(root, cacheId);
  }

  File _metadataFileIn(Directory root, String cacheId) {
    return File('${root.path}${Platform.pathSeparator}$cacheId.metadata.json');
  }

  Future<void> _backupCorrupt(File file) async {
    if (!await file.exists()) {
      return;
    }
    await _jsonStore.backupCorruptFile(file);
  }

  static Future<Directory> _defaultRoot() async {
    return getAiMusicSupportSubdirectory('ai_music_metadata');
  }
}

Uri? artworkUriFromText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  return uri;
}

TrackMetadata _metadataFromJson(Map<String, dynamic> json) {
  return TrackMetadata(
    artworkUri: artworkUriFromText(json['artworkUri']?.toString() ?? ''),
    lyrics: (json['lyrics'] is List ? json['lyrics'] as List : [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .map(
          (row) => LyricLine(
            time: Duration(
              milliseconds: row['timeMs'] is num
                  ? (row['timeMs'] as num).toInt()
                  : int.tryParse(row['timeMs']?.toString() ?? '') ?? 0,
            ),
            text: row['text']?.toString() ?? '',
          ),
        )
        .where((line) => line.text.trim().isNotEmpty)
        .toList(growable: false),
    source: json['source']?.toString() ?? '',
    artworkMiss: _missFromJson(json['artworkMiss']),
    lyricsMiss: _missFromJson(json['lyricsMiss']),
  );
}

Map<String, Object?> _metadataToJson(TrackMetadata metadata) {
  return {
    'artworkUri': metadata.artworkUri?.toString() ?? '',
    'source': metadata.source,
    'artworkMiss': _missToJson(metadata.artworkMiss),
    'lyricsMiss': _missToJson(metadata.lyricsMiss),
    'lyrics': [
      for (final line in metadata.lyrics)
        {'timeMs': line.time.inMilliseconds, 'text': line.text},
    ],
  };
}

MetadataFieldMiss? _missFromJson(Object? value) {
  if (value is! Map) {
    return null;
  }
  final json = value.cast<String, dynamic>();
  final until = DateTime.tryParse(json['until']?.toString() ?? '');
  if (until == null) {
    return null;
  }
  return MetadataFieldMiss(
    until: until,
    provider: json['provider']?.toString() ?? '',
    status: json['status']?.toString() ?? 'miss',
  );
}

Map<String, Object?>? _missToJson(MetadataFieldMiss? miss) {
  if (miss == null) {
    return null;
  }
  return {
    'until': miss.until.toIso8601String(),
    'provider': miss.provider,
    'status': miss.status,
  };
}
