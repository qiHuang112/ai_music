import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/application/lan_sync_use_case.dart';
import 'package:ai_music/src/data/lan_library_client.dart';
import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'first sync imports files and repeated sync skips identical content',
    () async {
      final root = await Directory.systemTemp.createTemp('ai_music_lan_sync_');
      final audio = _mp3Bytes(1);
      final lyrics = utf8.encode('[00:00.00]现场医护指令优先\n');
      final artwork = _pngBytes();
      final gateway = _FakeLanGateway(
        manifest: _manifest([
          _trackJson(
            id: 'lamaze-1',
            title: '慢呼放松',
            audio: audio,
            lyrics: lyrics,
            artwork: artwork,
          ),
        ]),
        bytes: {
          '/api/v1/files/lamaze-1.mp3': audio,
          '/api/v1/files/lamaze-1.lrc': lyrics,
          '/api/v1/files/lamaze-1.png': artwork,
        },
      );
      final store = CachedTrackStore(rootProvider: () async => root);
      final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

      try {
        final first = await useCase.sync('http://127.0.0.1:8787');
        final second = await useCase.sync('http://127.0.0.1:8787');
        final cached = (await store.listCached()).single;

        expect(first.added, 1);
        expect(first.failed, 0);
        expect(second.skipped, 1);
        expect(gateway.downloadCalls, 3);
        expect(cached.music.source, MusicDataSource.lan);
        expect(cached.contentSha256, sha256.convert(audio).toString());
        expect(await File(cached.lyricsPath).readAsString(), contains('医护'));
        expect(await File(cached.artworkPath).exists(), isTrue);
        expect(cached.music.coverUrl, File(cached.artworkPath).uri.toString());
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('content update keeps stable track id and replaces the audio', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_update_');
    final oldAudio = _mp3Bytes(1);
    final newAudio = _mp3Bytes(2);
    final gateway = _FakeLanGateway(
      manifest: _manifest([
        _trackJson(id: 'stable-id', title: '宫缩浪潮', audio: oldAudio),
      ]),
      bytes: {'/api/v1/files/stable-id.mp3': oldAudio},
    );
    final store = CachedTrackStore(rootProvider: () async => root);
    final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

    try {
      await useCase.sync('http://127.0.0.1:8787');
      final before = (await store.listCached()).single;
      gateway
        ..manifest = _manifest([
          _trackJson(id: 'stable-id', title: '宫缩浪潮', audio: newAudio),
        ])
        ..bytes['/api/v1/files/stable-id.mp3'] = newAudio;

      final result = await useCase.sync('http://127.0.0.1:8787');
      final after = (await store.listCached()).single;

      expect(result.updated, 1);
      expect(after.cacheId, before.cacheId);
      expect(after.filePath, isNot(before.filePath));
      expect(await File(after.filePath).readAsBytes(), newAudio);
      expect(await File(before.filePath).exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'metadata-only update keeps files and refreshes the cached title',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai_music_lan_metadata_',
      );
      final audio = _mp3Bytes(7);
      final gateway = _FakeLanGateway(
        manifest: _manifest([
          _trackJson(id: 'metadata-id', title: '旧标题', audio: audio),
        ]),
        bytes: {'/api/v1/files/metadata-id.mp3': audio},
      );
      final store = CachedTrackStore(rootProvider: () async => root);
      final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

      try {
        await useCase.sync('http://127.0.0.1:8787');
        final before = (await store.listCached()).single;
        gateway.manifest = _manifest([
          _trackJson(id: 'metadata-id', title: '新标题', audio: audio),
        ]);

        final result = await useCase.sync('http://127.0.0.1:8787');
        final after = (await store.listCached()).single;

        expect(result.updated, 1);
        expect(gateway.downloadCalls, 1);
        expect(after.cacheId, before.cacheId);
        expect(after.filePath, before.filePath);
        expect(after.music.name, '新标题');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('same track id from different libraries stays isolated', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_lan_namespaces_',
    );
    final firstAudio = _mp3Bytes(8);
    final secondAudio = _mp3Bytes(9);
    final gateway = _FakeLanGateway(
      manifest: _manifest([
        _trackJson(id: 'shared-id', title: '第一音乐库', audio: firstAudio),
      ], libraryId: 'library-one'),
      bytes: {'/api/v1/files/shared-id.mp3': firstAudio},
    );
    final store = CachedTrackStore(rootProvider: () async => root);
    final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

    try {
      await useCase.sync('http://127.0.0.1:8787');
      gateway
        ..manifest = _manifest([
          _trackJson(id: 'shared-id', title: '第二音乐库', audio: secondAudio),
        ], libraryId: 'library-two')
        ..bytes['/api/v1/files/shared-id.mp3'] = secondAudio;

      await useCase.sync('http://127.0.0.1:8787');
      final cached = await store.listCached();

      expect(cached, hasLength(2));
      expect(cached.map((item) => item.cacheId).toSet(), hasLength(2));
      expect(cached.map((item) => item.music.platform).toSet(), {
        'lan:library-one',
        'lan:library-two',
      });
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('matching hash cannot disguise a non-audio LAN payload', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_lan_signature_',
    );
    final invalidAudio = List<int>.filled(16 * 1024 + 32, 0);
    final gateway = _FakeLanGateway(
      manifest: _manifest([
        _trackJson(id: 'not-audio', title: '无效音频', audio: invalidAudio),
      ]),
      bytes: {'/api/v1/files/not-audio.mp3': invalidAudio},
    );
    final store = CachedTrackStore(rootProvider: () async => root);
    final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

    try {
      final result = await useCase.sync('http://127.0.0.1:8787');

      expect(result.failed, 1);
      expect(await store.listCached(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('hash failure is isolated and phone-only cache remains', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_partial_');
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: _SeedDownloader(),
    );
    final phoneOnly = await store.downloadOrReuse(_phoneOnlyMusic());
    final good = _mp3Bytes(3);
    final badExpected = _mp3Bytes(4);
    final gateway = _FakeLanGateway(
      manifest: _manifest([
        _trackJson(id: 'good', title: '跟随医护', audio: good),
        _trackJson(id: 'bad', title: '哈希错误', audio: badExpected),
      ]),
      bytes: {
        '/api/v1/files/good.mp3': good,
        '/api/v1/files/bad.mp3': _mp3Bytes(99),
      },
    );
    final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

    try {
      final result = await useCase.sync('http://127.0.0.1:8787');
      final cached = await store.listCached();

      expect(result.added, 1);
      expect(result.failed, 1);
      expect(result.failures.single.trackId, 'bad');
      expect(cached.map((item) => item.cacheId), contains(phoneOnly.cacheId));
      expect(
        cached.where((item) => item.music.source == MusicDataSource.lan),
        hasLength(1),
      );
      expect(
        root.listSync().whereType<File>().where(
          (file) => file.path.contains('.download-'),
        ),
        isEmpty,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('sync downloads at most two tracks concurrently', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_pool_');
    final rows = <Map<String, Object?>>[];
    final bytes = <String, List<int>>{};
    for (var index = 0; index < 5; index += 1) {
      final id = 'pool-$index';
      final audio = _mp3Bytes(index + 10);
      rows.add(_trackJson(id: id, title: id, audio: audio));
      bytes['/api/v1/files/$id.mp3'] = audio;
    }
    final gateway = _FakeLanGateway(
      manifest: _manifest(rows),
      bytes: bytes,
      delay: const Duration(milliseconds: 20),
    );
    final useCase = LanSyncUseCase(
      gateway: gateway,
      cacheStore: CachedTrackStore(rootProvider: () async => root),
    );

    try {
      final result = await useCase.sync('http://127.0.0.1:8787');

      expect(result.added, 5);
      expect(gateway.maxActiveDownloads, 2);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('empty library is a successful no-op', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_empty_');
    final gateway = _FakeLanGateway(manifest: _manifest(const []), bytes: {});
    final useCase = LanSyncUseCase(
      gateway: gateway,
      cacheStore: CachedTrackStore(rootProvider: () async => root),
    );

    try {
      final result = await useCase.sync('http://127.0.0.1:8787');

      expect(result.total, 0);
      expect(result.added, 0);
      expect(result.failed, 0);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('offline manifest fetch leaves the existing cache untouched', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_offline_');
    final store = CachedTrackStore(
      rootProvider: () async => root,
      downloader: _SeedDownloader(),
    );
    final phoneOnly = await store.downloadOrReuse(_phoneOnlyMusic());
    final useCase = LanSyncUseCase(
      gateway: _OfflineLanGateway(),
      cacheStore: store,
    );

    try {
      await expectLater(
        useCase.sync('http://127.0.0.1:8787'),
        throwsA(isA<LanLibraryException>()),
      );
      expect((await store.listCached()).single.cacheId, phoneOnly.cacheId);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('content update preserves favorite and playlist references', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_lan_lists_');
    final audio1 = _mp3Bytes(30);
    final audio2 = _mp3Bytes(31);
    final gateway = _FakeLanGateway(
      manifest: _manifest([
        _trackJson(id: 'playlist-stable', title: '暂缓用力', audio: audio1),
      ]),
      bytes: {'/api/v1/files/playlist-stable.mp3': audio1},
    );
    final store = CachedTrackStore(rootProvider: () async => root);
    final playlists = PlaylistStore(rootProvider: () async => root);
    final useCase = LanSyncUseCase(gateway: gateway, cacheStore: store);

    try {
      await useCase.sync('http://127.0.0.1:8787');
      final trackId = (await store.listCached()).single.cacheId;
      final now = DateTime(2026, 8, 2);
      await playlists.write(
        PlaylistLibrary(
          favoriteTrackIds: [trackId],
          playlists: [
            MusicPlaylist(
              id: 'birth',
              name: '待产',
              trackIds: [trackId],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      gateway
        ..manifest = _manifest([
          _trackJson(id: 'playlist-stable', title: '暂缓用力', audio: audio2),
        ])
        ..bytes['/api/v1/files/playlist-stable.mp3'] = audio2;

      await useCase.sync('http://127.0.0.1:8787');
      final after = await store.listCached();
      final library = await playlists.load(
        validTrackIds: {after.single.cacheId},
      );

      expect(after.single.cacheId, trackId);
      expect(library.favoriteTrackIds, [trackId]);
      expect(library.playlists.single.trackIds, [trackId]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}

class _FakeLanGateway implements LanLibraryGateway {
  _FakeLanGateway({
    required this.manifest,
    required this.bytes,
    this.delay = Duration.zero,
  });

  LanLibraryManifest manifest;
  final Map<String, List<int>> bytes;
  final Duration delay;
  int downloadCalls = 0;
  int activeDownloads = 0;
  int maxActiveDownloads = 0;

  @override
  Future<LanLibraryHealth> testConnection(String baseUrl) async {
    return LanLibraryHealth(
      schemaVersion: 1,
      trackCount: manifest.tracks.length,
    );
  }

  @override
  Future<LanLibraryManifest> fetchLibrary(String baseUrl) async => manifest;

  @override
  Uri resolveAssetUri(String baseUrl, LanAsset asset) {
    return Uri.parse(baseUrl).resolveUri(asset.url);
  }

  @override
  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target) async {
    downloadCalls += 1;
    activeDownloads += 1;
    if (activeDownloads > maxActiveDownloads) {
      maxActiveDownloads = activeDownloads;
    }
    try {
      if (delay != Duration.zero) {
        await Future<void>.delayed(delay);
      }
      final payload = bytes[asset.url.path];
      if (payload == null) {
        throw StateError('missing ${asset.url.path}');
      }
      await target.writeAsBytes(payload);
      return payload.length;
    } finally {
      activeDownloads -= 1;
    }
  }
}

class _SeedDownloader implements AudioDownloader {
  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final bytes = _mp3Bytes(42);
    await target.writeAsBytes(bytes);
    return bytes.length;
  }
}

class _OfflineLanGateway implements LanLibraryGateway {
  @override
  Future<LanLibraryHealth> testConnection(String baseUrl) {
    throw const LanLibraryException('offline');
  }

  @override
  Future<LanLibraryManifest> fetchLibrary(String baseUrl) {
    throw const LanLibraryException('offline');
  }

  @override
  Uri resolveAssetUri(String baseUrl, LanAsset asset) {
    throw const LanLibraryException('offline');
  }

  @override
  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target) {
    throw const LanLibraryException('offline');
  }
}

ResolvedMusic _phoneOnlyMusic() {
  return const ResolvedMusic(
    query: '手机独有',
    source: MusicDataSource.buguyy,
    platform: 'buguyy',
    id: 'phone-only',
    name: '手机独有',
    artist: '本机',
    album: '',
    url: 'https://cdn.example.test/phone-only.mp3',
    quality: MusicQuality(format: 'mp3'),
  );
}

LanLibraryManifest _manifest(
  List<Map<String, Object?>> tracks, {
  String libraryId = 'test-library',
}) {
  return LanLibraryManifest.fromJson({
    'schemaVersion': 1,
    'libraryId': libraryId,
    'generatedAt': '2026-08-02T00:00:00Z',
    'tracks': tracks,
  });
}

Map<String, Object?> _trackJson({
  required String id,
  required String title,
  required List<int> audio,
  List<int>? lyrics,
  List<int>? artwork,
}) {
  return {
    'id': id,
    'title': title,
    'artist': 'AI Home',
    'album': '拉玛泽呼吸引导',
    'audio': _assetJson('/api/v1/files/$id.mp3', audio, format: 'mp3'),
    if (lyrics != null)
      'lyrics': _assetJson('/api/v1/files/$id.lrc', lyrics, format: 'lrc'),
    if (artwork != null)
      'artwork': _assetJson(
        '/api/v1/files/$id.png',
        artwork,
        mimeType: 'image/png',
      ),
  };
}

Map<String, Object?> _assetJson(
  String url,
  List<int> bytes, {
  String? format,
  String? mimeType,
}) {
  return {
    'url': url,
    'sizeBytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'format': ?format,
    'mimeType': ?mimeType,
  };
}

List<int> _mp3Bytes(int marker) {
  return [
    0x49,
    0x44,
    0x33,
    0x04,
    0x00,
    marker,
    ...List<int>.filled(16 * 1024, marker & 0xff),
  ];
}

List<int> _pngBytes() {
  return [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ...List.filled(64, 0),
  ];
}
