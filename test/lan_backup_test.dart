import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/application/lan_backup_tasks.dart';
import 'package:ai_music/src/application/lan_backup_use_case.dart';
import 'package:ai_music/src/application/library_use_case.dart';
import 'package:ai_music/src/data/lan_backup_client.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/saved_online_track.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The LAN service in memory: blobs by hash, one manifest per device.
class _FakeServer extends LanBackupClient {
  final blobs = <String, List<int>>{};
  final manifests = <String, Map<String, dynamic>>{};
  final uploads = <String>[];
  var downloads = 0;

  @override
  Future<Set<String>> missing(String base, Iterable<String> hashes) async =>
      {for (final h in hashes) if (!blobs.containsKey(h)) h};

  @override
  Future<void> putBlob(String base, String sha256, File file) async {
    uploads.add(sha256);
    blobs[sha256] = await file.readAsBytes();
  }

  @override
  Future<void> putManifest(
    String base,
    String deviceId,
    Map<String, Object?> manifest,
  ) async {
    manifests[deviceId] =
        jsonDecode(jsonEncode(manifest)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> manifest(String base, String deviceId) async =>
      manifests[deviceId]!;

  @override
  Future<void> downloadBlob(String base, String sha256, File target) async {
    downloads += 1;
    await target.parent.create(recursive: true);
    await target.writeAsBytes(blobs[sha256]!);
  }
}

ResolvedMusic _music(String id, String name, String bitrate, String format) =>
    ResolvedMusic(
      query: name,
      source: MusicDataSource.buguyy,
      platform: 'buguyy',
      id: id,
      name: name,
      artist: 'Artist',
      album: '',
      url: 'https://audio.test/$id',
      coverUrl: '',
      quality: MusicQuality(format: format, bitrate: bitrate),
    );

PlaylistTrackEntry _entry(ResolvedMusic music) {
  final candidate = MusicSearchCandidate(
    query: music.query,
    source: music.source,
    platform: music.platform,
    keyword: music.name,
    page: 1,
    id: music.id,
    name: music.name,
    artist: music.artist,
    album: '',
    duration: 200,
    link: '',
    coverUrl: '',
    qualities: [music.quality],
    score: 0,
    raw: const {},
  );
  final saved = SavedOnlineTrack(candidate: candidate);
  return PlaylistTrackEntry(
    trackId: saved.trackId,
    addedAt: DateTime(2026),
    onlineTrack: saved,
  );
}

Future<({CachedTrackStore cache, PlaylistStore playlists, LibraryUseCase library})>
_device(Directory root) async {
  final cache = CachedTrackStore(rootProvider: () async => root);
  final playlists = PlaylistStore(rootProvider: () async => root);
  final library = LibraryUseCase(
    cacheStore: cache,
    playlistStore: playlists,
    metadataRepository: TrackMetadataRepository(),
  );
  return (cache: cache, playlists: playlists, library: library);
}

void main() {
  test('uploads the best copy of each song and restores only what was picked', () async {
    final a = await Directory.systemTemp.createTemp('backup_a_');
    final b = await Directory.systemTemp.createTemp('backup_b_');
    addTearDown(() => a.delete(recursive: true));
    addTearDown(() => b.delete(recursive: true));

    // Device A: 晴天 cached twice (a 128k playback cache, then a 320k
    // download), 夜曲 once. 晴天 is a favorite and in 通勤; 夜曲 only in 睡前.
    final low = _music('qt', '晴天', '128', 'mp3');
    final high = _music('qt', '晴天', '320', 'mp3');
    final night = _music('yq', '夜曲', '320', 'mp3');
    Map<String, Object?> row(ResolvedMusic music, String file, bool playback) {
      File('${a.path}/$file').writeAsStringSync('audio of $file');
      return CachedTrack(
        cacheId: cacheIdForResolved(music),
        music: music,
        filePath: '${a.path}/$file',
        sizeBytes: 10,
        fromCache: true,
        playbackCache: playback,
      ).toJson();
    }

    File('${a.path}/_cache_index.json').writeAsStringSync(
      jsonEncode([
        row(low, 'qt-low.mp3', true),
        row(high, 'qt-high.mp3', false),
        row(night, 'yq.mp3', false),
      ]),
    );
    final deviceA = await _device(a);
    final sunny = _entry(high), nocturne = _entry(night);
    await deviceA.playlists.write(
      PlaylistLibrary(
        favoriteEntries: [sunny],
        playlists: [
          MusicPlaylist(
            id: 'p1',
            name: '通勤',
            entries: [sunny],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          MusicPlaylist(
            id: 'p2',
            name: '睡前',
            entries: [nocturne],
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      ),
    );

    final server = _FakeServer();
    const identity = LanBackupIdentity(
      deviceId: 'device-aaaa1111',
      deviceName: 'A',
      serverUrl: 'http://lan.test',
    );
    final result = await LanBackupUseCase(
      client: server,
      cacheStore: deviceA.cache,
      playlistStore: deviceA.playlists,
      library: deviceA.library,
    ).upload(identity);
    expect(result.tracks, 2);
    // Only the 320k 晴天 went up, never the 128k playback cache.
    final sunnyHash = sha256.convert(utf8.encode('audio of qt-high.mp3')).toString();
    expect(server.uploads, contains(sunnyHash));
    expect(
      server.uploads,
      isNot(contains(sha256.convert(utf8.encode('audio of qt-low.mp3')).toString())),
    );

    // Device B restores the favorite and 通勤, but nothing from 睡前.
    final deviceB = await _device(b);
    final manifest = LanBackupManifest.parse(
      await server.manifest('', 'device-aaaa1111'),
    );
    expect(manifest.playlists.map((p) => p.name), ['通勤', '睡前']);
    final selection = LanBackupSelection.all(manifest)..playlists[1] = {};
    final restored = await LanBackupUseCase(
      client: server,
      cacheStore: deviceB.cache,
      playlistStore: deviceB.playlists,
      library: deviceB.library,
    ).restore('http://lan.test', manifest, selection);
    expect(restored.downloaded, 1);
    expect(restored.failed, isEmpty);

    // Running it again (say after an interruption) skips songs already here.
    final downloadsBefore = server.downloads;
    final again = await LanBackupUseCase(
      client: server,
      cacheStore: deviceB.cache,
      playlistStore: deviceB.playlists,
      library: deviceB.library,
    ).restore('http://lan.test', manifest, selection);
    expect(again.failed, isEmpty);
    expect(again.downloaded, 0);
    expect(server.downloads, downloadsBefore);

    // The app-level task keeps the result after every page has gone.
    final tasks = LanBackupTasks(
      client: server,
      useCase: (client) => LanBackupUseCase(
        client: client,
        cacheStore: deviceA.cache,
        playlistStore: deviceA.playlists,
        library: deviceA.library,
      ),
    );
    final run = tasks.upload(identity);
    expect(tasks.uploading, isTrue);
    expect(tasks.upload(identity), same(run));
    await run;
    expect(tasks.uploading, isFalse);
    expect(tasks.uploadMessage, startsWith('已上传'));
    // Everything was already on the server, so nothing went up again.
    expect(tasks.uploadMessage, contains('新传 0 个文件'));

    final snapshot = await deviceB.library.loadCache();
    expect(snapshot.cachedRecords.single.cacheId, cacheIdForResolved(high));
    expect(
      await File(snapshot.cachedRecords.single.filePath).readAsString(),
      'audio of qt-high.mp3',
    );
    expect(snapshot.playlistLibrary.favoriteTrackIds, [sunny.trackId]);
    expect(snapshot.customPlaylists.map((p) => p.name), ['通勤']);
    expect(snapshot.favoriteTracks.single.filePath, isNotEmpty);
  });

  test('the real client and the Python LAN service agree end to end', () async {
    final python = await Process.run('python3', ['--version']);
    if (python.exitCode != 0) {
      markTestSkipped('python3 not available');
      return;
    }
    final root = await Directory.systemTemp.createTemp('backup_server_');
    addTearDown(() => root.delete(recursive: true));
    final port = 20000 + pid % 20000;
    final server = await Process.start('python3', [
      'tool/lan_update_server.py',
      '--root',
      '${root.path}/android',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
    ]);
    addTearDown(server.kill);
    final base = 'http://127.0.0.1:$port';
    final client = LanBackupClient();
    addTearDown(client.close);
    for (var i = 0; i < 50; i++) {
      try {
        await client.devices(base);
        break;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    final song = File('${root.path}/song.mp3')..writeAsStringSync('real audio');
    final hash = await fileSha256(song);
    expect(await client.missing(base, [hash]), {hash});
    await client.putBlob(base, hash, song);
    expect(await client.missing(base, [hash]), isEmpty);
    await client.putManifest(base, 'device-cccc3333', {
      'schemaVersion': 1,
      'device': {'id': 'device-cccc3333', 'name': '测试机'},
      'tracks': {
        't': {
          'title': '晴天',
          'files': [
            {'role': 'audio', 'sha256': hash, 'size': 10},
          ],
        },
      },
      'favorites': [
        {'trackId': 't'},
      ],
      'playlists': [],
    });
    final devices = await client.devices(base);
    expect(devices.single.deviceName, '测试机');
    expect(devices.single.favoriteCount, 1);
    final copy = File('${root.path}/copy.mp3');
    await client.downloadBlob(base, hash, copy);
    expect(await copy.readAsString(), 'real audio');
    await expectLater(
      client.putManifest(base, 'device-cccc3333', {
        'schemaVersion': 1,
        'device': {'id': 'device-cccc3333'},
        'tracks': {
          't': {
            'files': [
              {'role': 'audio', 'sha256': 'a' * 64, 'size': 1},
            ],
          },
        },
      }),
      throwsA(isA<LanBackupException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('plain HTTP backups stay on the home network', () async {
    expect(isPrivateOrLoopbackHost('192.168.31.167'), isTrue);
    expect(isPrivateOrLoopbackHost('10.1.2.3'), isTrue);
    expect(isPrivateOrLoopbackHost('127.0.0.1'), isTrue);
    expect(isPrivateOrLoopbackHost('8.8.8.8'), isFalse);
    expect(isPrivateOrLoopbackHost('example.com'), isFalse);
    final client = LanBackupClient();
    addTearDown(client.close);
    await expectLater(
      client.devices('http://8.8.8.8:8788'),
      throwsA(isA<LanBackupException>()),
    );
  });
}
