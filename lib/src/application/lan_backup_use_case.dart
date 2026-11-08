import 'dart:io';

import '../data/lan_backup_client.dart';
import '../data/music_cache.dart';
import '../data/music_playlists.dart';
import '../data/music_resolver.dart';
import '../data/song_match_identity.dart';
import 'library_use_case.dart';
import 'music_mappers.dart';

/// Uploads this device's playlists, favorites and their songs to the LAN,
/// and restores a chosen part of any device's backup.
class LanBackupUseCase {
  LanBackupUseCase({
    required this.client,
    required this.cacheStore,
    required this.playlistStore,
    required this.library,
    this.appVersion = '',
  });

  final LanBackupClient client;
  final CachedTrackStore cacheStore;
  final PlaylistStore playlistStore;
  final LibraryUseCase library;
  final String appVersion;

  Future<LanBackupUploadResult> upload(
    LanBackupIdentity identity, {
    void Function(LanBackupProgress progress)? onProgress,
  }) async {
    final plan = buildBackupPlan(
      await playlistStore.load(),
      await cacheStore.listCached(),
    );
    final files = [
      for (final track in plan.tracks.values) ...track.files,
    ];
    final base = identity.serverUrl;
    for (final (i, file) in files.indexed) {
      onProgress?.call(LanBackupProgress('核对文件', i, files.length));
      file.sha256 = await file.knownSha256 ?? await fileSha256(file.file);
      file.size = await file.file.length();
    }
    final missing = await client.missing(base, files.map((f) => f.sha256!));
    final toUpload = {
      for (final file in files)
        if (missing.contains(file.sha256)) file.sha256!: file,
    }.values.toList();
    var uploadedBytes = 0;
    for (final (i, file) in toUpload.indexed) {
      onProgress?.call(LanBackupProgress('上传歌曲', i, toUpload.length));
      await client.putBlob(base, file.sha256!, file.file);
      uploadedBytes += file.size;
    }
    onProgress?.call(LanBackupProgress('保存清单', 0, 1));
    await client.putManifest(
      base,
      identity.deviceId,
      plan.toManifest(identity, appVersion: appVersion),
    );
    return LanBackupUploadResult(
      playlists: plan.playlists.length,
      favorites: plan.favorites.length,
      tracks: plan.tracks.length,
      uploadedFiles: toUpload.length,
      uploadedBytes: uploadedBytes,
    );
  }

  /// Restores the songs picked in [selection] from one device's [manifest].
  /// A playlist with no picked song is skipped; nothing local is removed.
  Future<LanBackupRestoreResult> restore(
    String base,
    LanBackupManifest manifest,
    LanBackupSelection selection, {
    void Function(LanBackupProgress progress)? onProgress,
  }) async {
    final wanted = selection.allTrackIds;
    final staging = await cacheStore.backupStagingDirectory();
    final failed = <String>[];
    var downloaded = 0;
    final ids = [
      for (final id in wanted)
        if (manifest.tracks[id]?.hasAudio ?? false) id,
    ];
    for (final (i, id) in ids.indexed) {
      final track = manifest.tracks[id]!;
      onProgress?.call(LanBackupProgress(track.title, i, ids.length));
      try {
        Future<File?> fetch(LanBackupFile? file, String suffix) async {
          if (file == null) return null;
          final target = File('${staging.path}/${file.sha256}$suffix');
          await client.downloadBlob(base, file.sha256, target);
          return target;
        }

        final audio = await fetch(track.audio, track.audioSuffix);
        await cacheStore.importBackupTrack(
          track.cached!,
          audio: audio!,
          lyrics: await fetch(track.lyrics, '.lrc'),
          artwork: await fetch(track.artwork, '.jpg'),
        );
        downloaded += 1;
      } on Object {
        failed.add(track.title);
      }
    }
    // Reload so entries that point at the songs just cached are kept.
    final snapshot = await library.loadCache();
    PlaylistTrackEntry? entry(String id) => manifest.tracks[id]?.entry;
    await library.mergeBackup(
      current: snapshot,
      favorites: [
        for (final id in manifest.favorites)
          if (selection.favorites.contains(id)) ?entry(id),
      ],
      playlists: [
        for (final (i, playlist) in manifest.playlists.indexed)
          (
            name: playlist.name,
            entries: [
              for (final id in playlist.trackIds)
                if (selection.playlists[i]?.contains(id) ?? false) ?entry(id),
            ],
          ),
      ],
    );
    return LanBackupRestoreResult(
      songs: wanted.length,
      downloaded: downloaded,
      failed: failed,
    );
  }
}

class LanBackupProgress {
  const LanBackupProgress(this.stage, this.done, this.total);
  final String stage;
  final int done, total;
}

class LanBackupUploadResult {
  const LanBackupUploadResult({
    required this.playlists,
    required this.favorites,
    required this.tracks,
    required this.uploadedFiles,
    required this.uploadedBytes,
  });
  final int playlists, favorites, tracks, uploadedFiles, uploadedBytes;
}

class LanBackupRestoreResult {
  const LanBackupRestoreResult({
    required this.songs,
    required this.downloaded,
    required this.failed,
  });
  final int songs, downloaded;
  final List<String> failed;
}

/// What the user picked to restore: songs of the favorites and, per
/// playlist (by its position in the manifest), the songs to keep.
class LanBackupSelection {
  LanBackupSelection({Set<String>? favorites, Map<int, Set<String>>? playlists})
    : favorites = favorites ?? {},
      playlists = playlists ?? {};

  final Set<String> favorites;
  final Map<int, Set<String>> playlists;

  /// Everything selected, for a manifest's default: all of it.
  factory LanBackupSelection.all(LanBackupManifest manifest) =>
      LanBackupSelection(
        favorites: manifest.favorites.toSet(),
        playlists: {
          for (final (i, p) in manifest.playlists.indexed)
            i: p.trackIds.toSet(),
        },
      );

  Set<String> get allTrackIds => {
    ...favorites,
    for (final ids in playlists.values) ...ids,
  };
}

// ---- Upload plan ------------------------------------------------------------

class BackupFilePlan {
  BackupFilePlan(this.role, this.file, {String knownSha256 = ''})
    : _known = knownSha256;
  final String role;
  final File file;
  final String _known;
  String? sha256;
  int size = 0;

  Future<String?> get knownSha256 async =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(_known) ? _known : null;
}

class BackupTrackPlan {
  BackupTrackPlan(this.entry, this.cached, this.files);
  final PlaylistTrackEntry entry;
  final CachedTrack? cached;
  final List<BackupFilePlan> files;
}

class BackupPlan {
  BackupPlan(this.tracks, this.favorites, this.playlists);
  final Map<String, BackupTrackPlan> tracks;
  final List<PlaylistTrackEntry> favorites;
  final List<MusicPlaylist> playlists;

  Map<String, Object?> toManifest(
    LanBackupIdentity identity, {
    String appVersion = '',
  }) {
    String title(BackupTrackPlan t) =>
        t.entry.onlineTrack?.candidate.name ??
        t.entry.song?.title ??
        t.cached?.music.name ??
        '';
    String artist(BackupTrackPlan t) =>
        t.entry.onlineTrack?.candidate.artist ??
        t.entry.song?.artist ??
        t.cached?.music.artist ??
        '';
    return {
      'schemaVersion': 1,
      'device': {
        'id': identity.deviceId,
        'name': identity.deviceName,
        'platform': Platform.operatingSystem,
        'appVersion': appVersion,
      },
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tracks': {
        for (final MapEntry(:key, :value) in tracks.entries)
          key: {
            'title': title(value),
            'artist': artist(value),
            'entry': value.entry.toJson(),
            if (value.cached != null) 'cached': _portable(value.cached!),
            'files': [
              for (final f in value.files)
                {
                  'role': f.role,
                  'sha256': f.sha256,
                  'size': f.size,
                  'name': f.file.path.split(Platform.pathSeparator).last,
                },
            ],
          },
      },
      'favorites': [
        for (final e in favorites)
          {'trackId': e.trackId, 'addedAt': e.addedAt.toIso8601String()},
      ],
      'playlists': [
        for (final p in playlists)
          {
            'id': p.id,
            'name': p.name,
            'entries': [
              for (final e in p.entries)
                {'trackId': e.trackId, 'addedAt': e.addedAt.toIso8601String()},
            ],
          },
      ],
    };
  }

  /// The record without this device's absolute paths.
  static Map<String, Object?> _portable(CachedTrack record) {
    String name(String path) => path.split(Platform.pathSeparator).last;
    return {
      ...record.toJson(),
      'filePath': name(record.filePath),
      'lyricsPath': name(record.lyricsPath),
      'artworkPath': name(record.artworkPath),
    };
  }
}

/// Which local file stands for each song of the favorites and the custom
/// playlists: the one playback would use (best quality, a real download
/// before a playback cache), the same choice the library makes. Lower
/// quality copies of the same song stay home.
BackupPlan buildBackupPlan(PlaylistLibrary library, List<CachedTrack> records) {
  final byCacheId = {for (final r in records) r.cacheId: r};
  final byIdentity = <(Object, String, String), CachedTrack>{};
  final byRecording = <String, CachedTrack>{};
  CachedTrack better(CachedTrack a, CachedTrack b) =>
      cachedTrackPlaybackPreference(a) >= cachedTrackPlaybackPreference(b)
      ? a
      : b;
  for (final record in records) {
    final music = record.music;
    byIdentity.update(
      (music.source, music.platform, music.id),
      (current) => better(record, current),
      ifAbsent: () => record,
    );
    if (music.source != MusicDataSource.lan) {
      final recording = SongMatchIdentity(music.name, music.artist);
      if (recording.title.isNotEmpty && recording.artists.isNotEmpty) {
        byRecording.update(
          recording.key,
          (current) => better(record, current),
          ifAbsent: () => record,
        );
      }
    }
  }
  CachedTrack? bestFor(PlaylistTrackEntry entry) {
    final saved = entry.onlineTrack;
    if (saved != null) {
      final c = saved.candidate;
      return byIdentity[(c.source, c.platform, c.id)] ??
          (entry.manualSource
              ? null
              : byRecording[SongMatchIdentity(c.name, c.artist).key]) ??
          byCacheId[entry.trackId];
    }
    final song = entry.song;
    return byCacheId[entry.trackId] ??
        (song == null
            ? null
            : byRecording[SongMatchIdentity(song.title, song.artist).key]);
  }

  final tracks = <String, BackupTrackPlan>{};
  void add(PlaylistTrackEntry entry) {
    tracks.putIfAbsent(entry.trackId, () {
      final cached = bestFor(entry);
      final files = <BackupFilePlan>[];
      if (cached != null && File(cached.filePath).existsSync()) {
        files.add(
          BackupFilePlan(
            'audio',
            File(cached.filePath),
            knownSha256: cached.contentSha256,
          ),
        );
        if (cached.lyricsPath.isNotEmpty &&
            File(cached.lyricsPath).existsSync()) {
          files.add(
            BackupFilePlan(
              'lyrics',
              File(cached.lyricsPath),
              knownSha256: cached.lyricsSha256,
            ),
          );
        }
        if (cached.artworkPath.isNotEmpty &&
            File(cached.artworkPath).existsSync()) {
          files.add(
            BackupFilePlan(
              'artwork',
              File(cached.artworkPath),
              knownSha256: cached.artworkSha256,
            ),
          );
        }
      }
      return BackupTrackPlan(entry, files.isEmpty ? null : cached, files);
    });
  }

  final playlists = [
    for (final p in library.playlists)
      if (!p.isBuiltIn && p.entries.isNotEmpty) p,
  ];
  for (final entry in library.favoriteEntries) {
    add(entry);
  }
  for (final p in playlists) {
    p.entries.forEach(add);
  }
  return BackupPlan(tracks, library.favoriteEntries, playlists);
}

// ---- Downloaded manifest ----------------------------------------------------

class LanBackupFile {
  const LanBackupFile(this.role, this.sha256, this.size, this.name);
  final String role, sha256, name;
  final int size;
}

class LanBackupTrack {
  LanBackupTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.entry,
    required this.cached,
    required this.files,
  });
  final String id, title, artist;
  final PlaylistTrackEntry? entry;
  final CachedTrack? cached;
  final List<LanBackupFile> files;

  LanBackupFile? _role(String role) =>
      files.where((f) => f.role == role).firstOrNull;
  LanBackupFile? get audio => _role('audio');
  LanBackupFile? get lyrics => _role('lyrics');
  LanBackupFile? get artwork => _role('artwork');
  bool get hasAudio => audio != null && cached != null;
  int get size => files.fold(0, (sum, f) => sum + f.size);

  String get audioSuffix {
    final name = audio?.name ?? '';
    final dot = name.lastIndexOf('.');
    return dot > 0 && name.length - dot <= 6 ? name.substring(dot) : '.mp3';
  }
}

class LanBackupPlaylist {
  const LanBackupPlaylist(this.name, this.trackIds);
  final String name;
  final List<String> trackIds;
}

class LanBackupManifest {
  LanBackupManifest({
    required this.deviceName,
    required this.tracks,
    required this.favorites,
    required this.playlists,
  });
  final String deviceName;
  final Map<String, LanBackupTrack> tracks;
  final List<String> favorites;
  final List<LanBackupPlaylist> playlists;

  static LanBackupManifest parse(Map<String, dynamic> json) {
    final now = DateTime.now();
    final tracks = <String, LanBackupTrack>{};
    final rawTracks = json['tracks'];
    if (rawTracks is Map) {
      for (final MapEntry(:key, :value) in rawTracks.entries) {
        if (value is! Map) continue;
        final cachedJson = value['cached'];
        tracks['$key'] = LanBackupTrack(
          id: '$key',
          title: value['title']?.toString() ?? '',
          artist: value['artist']?.toString() ?? '',
          entry: PlaylistTrackEntry.fromJson(value['entry'], now),
          cached: cachedJson is Map
              ? CachedTrack.fromJson(cachedJson.cast<String, dynamic>())
              : null,
          files: [
            for (final f in value['files'] is List ? value['files'] as List : const [])
              if (f is Map && f['sha256'] is String)
                LanBackupFile(
                  f['role']?.toString() ?? '',
                  f['sha256'] as String,
                  (f['size'] as num?)?.toInt() ?? 0,
                  f['name']?.toString() ?? '',
                ),
          ],
        );
      }
    }
    List<String> ids(Object? rows) => [
      for (final row in rows is List ? rows : const [])
        if (row is Map && tracks.containsKey('${row['trackId']}'))
          '${row['trackId']}',
    ];
    final device = json['device'];
    return LanBackupManifest(
      deviceName: device is Map ? '${device['name'] ?? ''}' : '',
      tracks: tracks,
      favorites: ids(json['favorites']),
      playlists: [
        for (final p in json['playlists'] is List ? json['playlists'] as List : const [])
          if (p is Map)
            LanBackupPlaylist(p['name']?.toString() ?? '', ids(p['entries'])),
      ],
    );
  }
}
