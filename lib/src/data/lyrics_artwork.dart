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

class CandidateArtworkProvider implements TrackMetadataProvider {
  const CandidateArtworkProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    final uri = artworkUriFromText(track.music.coverUrl);
    return TrackMetadata(artworkUri: uri, source: uri == null ? '' : 'source');
  }
}

class EmptyLyricsProvider implements TrackMetadataProvider {
  const EmptyLyricsProvider();

  @override
  Future<TrackMetadata> find(CachedTrack track) async {
    return const TrackMetadata();
  }
}

class ResolvedLyricsProvider implements TrackMetadataProvider {
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

class CachedLyricsFileProvider implements TrackMetadataProvider {
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
  }) : _cacheStore = cacheStore ?? MetadataCacheStore(),
       _providers =
           providers ??
           _defaultProviders(httpClient ?? HttpMusicResolverClient()),
       _now = now ?? DateTime.now;

  final MetadataCacheStore _cacheStore;
  final List<TrackMetadataProvider> _providers;
  final DateTime Function() _now;
  final Map<String, DateTime> _lyricsMissUntil = {};

  static const Duration lyricsMissTtl = Duration(minutes: 30);

  Future<TrackMetadata> load(CachedTrack track) async {
    var metadata =
        await _cacheStore.read(track.cacheId) ?? const TrackMetadata();
    if (_isComplete(metadata)) {
      return metadata;
    }
    final lyricsMissActive = _hasFreshLyricsMiss(track.cacheId);
    for (final provider in _providers) {
      if (_shouldSkipProvider(
        provider,
        metadata,
        skipNetworkLyrics: lyricsMissActive,
      )) {
        continue;
      }
      final next = await provider.find(track);
      if (!metadata.hasLyrics && next.hasLyrics) {
        await _writeLyricsSidecar(track, next.lyrics);
      }
      metadata = _merge(metadata, next);
      if (_isComplete(metadata)) {
        break;
      }
    }
    if (metadata.hasLyrics) {
      _lyricsMissUntil.remove(track.cacheId);
    } else if (!lyricsMissActive) {
      _lyricsMissUntil[track.cacheId] = _now().add(lyricsMissTtl);
    }
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
  }) {
    if (skipNetworkLyrics &&
        (provider is BuguyyLyricsProvider ||
            provider is LrcApiLyricsProvider)) {
      return true;
    }
    if (!metadata.hasLyrics) {
      return false;
    }
    return provider is ResolvedLyricsProvider ||
        provider is CachedLyricsFileProvider ||
        provider is BuguyyLyricsProvider ||
        provider is LrcApiLyricsProvider ||
        provider is EmptyLyricsProvider;
  }

  bool _hasFreshLyricsMiss(String cacheId) {
    final until = _lyricsMissUntil[cacheId];
    if (until == null) {
      return false;
    }
    if (_now().isBefore(until)) {
      return true;
    }
    _lyricsMissUntil.remove(cacheId);
    return false;
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
  return [
    const CandidateArtworkProvider(),
    const ResolvedLyricsProvider(),
    const CachedLyricsFileProvider(),
    BuguyyLyricsProvider(httpClient: httpClient),
    LrcApiLyricsProvider(httpClient: httpClient),
    const EmptyLyricsProvider(),
  ];
}

class BuguyyLyricsProvider implements TrackMetadataProvider {
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

class LrcApiLyricsProvider implements TrackMetadataProvider {
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
  );
}

Map<String, Object?> _metadataToJson(TrackMetadata metadata) {
  return {
    'artworkUri': metadata.artworkUri?.toString() ?? '',
    'source': metadata.source,
    'lyrics': [
      for (final line in metadata.lyrics)
        {'timeMs': line.time.inMilliseconds, 'text': line.text},
    ],
  };
}
