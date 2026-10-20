import 'dart:convert';
import 'dart:io';

import '../domain/music_models.dart';
import '../platform/app_storage.dart';
import 'json_file_store.dart';
import 'music_playlists.dart';

class PlaybackSession {
  const PlaybackSession({
    required this.tracks,
    required this.currentId,
    required this.position,
    this.entries = const [],
    this.playlistId,
    this.followingPlaylistId,
    this.originName,
    this.removedIds = const {},
    this.mode = PlaybackMode.sequential,
  });

  final List<Track> tracks;
  final List<PlaylistTrackEntry> entries;
  final String currentId;
  final Duration position;
  final String? playlistId, followingPlaylistId, originName;
  final Set<String> removedIds;
  final PlaybackMode mode;

  Map<String, Object?> body() {
    final onlineIds = {
      for (final e in entries)
        if (e.onlineTrack != null || e.song != null) e.trackId,
    };
    return {
      'tracks': [
        for (final t in tracks)
          {
            'id': t.id, 'title': t.title, 'artist': t.artist, 'album': t.album,
            'filePath': t.filePath,
            // Online audio URLs expire. Original identities/source choices below
            // allow a fresh resolution only after the user requests playback.
            'source': onlineIds.contains(t.id) ? '' : t.source,
            'artwork': t.artworkUri?.toString(),
            'durationMs': t.duration?.inMilliseconds, 'sizeBytes': t.sizeBytes,
          },
      ],
      'entries': [for (final e in entries) e.toJson()],
      'playlistId': playlistId,
      'followingPlaylistId': followingPlaylistId,
      'originName': originName,
      'removedIds': removedIds.toList(),
      'mode': mode.name,
    };
  }

  Map<String, Object?> checkpoint() => {
    'currentId': currentId,
    'positionMs': position.inMilliseconds,
  };

  static PlaybackSession? fromJson(Map data) {
    if (data['schema'] != 1 || data['tracks'] is! List) return null;
    final seen = <String>{};
    final tracks = <Track>[];
    for (final row in data['tracks'] as List) {
      if (row is! Map || row['id'] is! String || row['title'] is! String) {
        continue;
      }
      final id = row['id'] as String;
      if (id.isEmpty || !seen.add(id)) continue;
      tracks.add(
        Track(
          id: id,
          title: row['title'] as String,
          artist: row['artist'] is String ? row['artist'] as String : '',
          album: row['album'] is String ? row['album'] as String : '',
          filePath: row['filePath'] is String ? row['filePath'] as String : '',
          source: row['source'] is String ? row['source'] as String : '',
          artworkUri: row['artwork'] is String
              ? Uri.tryParse(row['artwork'] as String)
              : null,
          duration: row['durationMs'] is int && (row['durationMs'] as int) > 0
              ? Duration(milliseconds: row['durationMs'] as int)
              : null,
          sizeBytes: row['sizeBytes'] is int ? row['sizeBytes'] as int : 0,
        ),
      );
    }
    if (!seen.contains(data['currentId'])) return null;
    final position = data['positionMs'] is int ? data['positionMs'] as int : 0;
    return PlaybackSession(
      tracks: tracks,
      currentId: data['currentId'] as String,
      position: Duration(milliseconds: position.clamp(0, 604800000)),
      entries: [
        if (data['entries'] is List)
          for (final e in data['entries'] as List)
            if (e is Map && seen.contains(e['trackId']))
              ?PlaylistTrackEntry.fromJson(e, DateTime(1970)),
      ],
      playlistId: data['playlistId'] is String
          ? data['playlistId'] as String
          : null,
      followingPlaylistId: data['followingPlaylistId'] is String
          ? data['followingPlaylistId'] as String
          : null,
      originName: data['originName'] is String
          ? data['originName'] as String
          : null,
      removedIds: {
        if (data['removedIds'] is List)
          for (final id in data['removedIds'] as List)
            if (id is String) id,
      },
      mode:
          PlaybackMode.values
              .where((m) => m.name == data['mode'])
              .firstOrNull ??
          PlaybackMode.sequential,
    );
  }
}

/// Queue structure is written only when it changes; frequent progress updates
/// are a small, separately atomic checkpoint linked to that exact structure.
class PlaybackSessionStore {
  PlaybackSessionStore({Future<Directory> Function()? rootProvider})
    : _root = rootProvider ?? getAiMusicSupportDirectory;
  final Future<Directory> Function() _root;
  final _json = const JsonFileStore();
  Future<void> _tail = Future.value();
  String? _body, _revision;
  int _generation = 0;

  Future<File> _file(String name) async =>
      File('${(await _root()).path}/$name');

  Future<PlaybackSession?> load() async {
    await _tail;
    try {
      final saved = await _json.read(await _file('playback_session.json'));
      if (saved is! Map || saved['schema'] != 1) return null;
      Object? progress;
      try {
        progress = await _json.read(await _file('playback_position.json'));
      } on JsonFileStoreException {
        /* Retain the full snapshot's checkpoint. */
      }
      final session =
          PlaybackSession.fromJson({
            ...saved,
            if (progress is Map && progress['revision'] == saved['revision'])
              ...progress,
          }) ??
          PlaybackSession.fromJson(saved);
      if (session != null) {
        _body = jsonEncode(session.body());
        _revision = saved['revision'] as String?;
      }
      return session;
    } on JsonFileStoreException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(PlaybackSession? session) {
    final body = session?.body();
    final signature = body == null ? null : jsonEncode(body);
    final checkpoint = session?.checkpoint();
    final work = _tail.then((_) async {
      if (body == null) {
        if (_body == null && _revision == 'cleared') return;
        await _json.write(await _file('playback_session.json'), {
          'schema': 1,
          'revision': 'cleared',
        });
        _body = null;
        _revision = 'cleared';
        return;
      }
      if (_body != signature || _revision == null) {
        final revision =
            '${DateTime.now().microsecondsSinceEpoch}-${++_generation}';
        await _json.write(await _file('playback_session.json'), {
          'schema': 1,
          'revision': revision,
          ...body,
          ...checkpoint!,
        });
        _body = signature;
        _revision = revision;
      }
      await _json.write(await _file('playback_position.json'), {
        'revision': _revision,
        ...checkpoint!,
      });
    });
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }
}
