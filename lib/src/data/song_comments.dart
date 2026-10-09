import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/music_models.dart';
import '../platform/app_storage.dart';
import 'json_file_store.dart';
import 'playlist_song.dart';
import 'resolver_http_client.dart';
import 'resolver_models.dart';

enum SongCommentPlatform { netease, qq }

extension SongCommentPlatformLabel on SongCommentPlatform {
  String get label => this == SongCommentPlatform.qq ? 'QQ 音乐' : '网易云音乐';
}

class SongCommentQuery {
  const SongCommentQuery({
    required this.title,
    required this.artist,
    this.album = '',
    this.durationSeconds = 0,
    this.platformIds = const {},
  });

  factory SongCommentQuery.fromTrack(
    Track track, {
    PlaylistSong? original,
    MusicSearchCandidate? candidate,
  }) {
    final ids = <SongCommentPlatform, String>{};
    final key = original?.key.split(':');
    if (key != null && key.length == 2) {
      final platform = _platform(key[0]);
      if (platform != null) ids[platform] = key[1];
    }
    // Provider IDs are only hints. Verify them against official song metadata
    // before asking for comments; BuguYY's IDs are never QQ/NetEase song IDs.
    if (candidate?.source == MusicDataSource.flac) {
      final platform = _platform(candidate!.platform);
      if (platform != null) ids.putIfAbsent(platform, () => candidate.id);
    }
    final artists = _artists(track.artist);
    // A playback provider may report a truncated/incorrect duration. Preserve
    // the original recording's duration only when its full identity agrees.
    final useOriginalDuration =
        original != null &&
        original.durationSeconds > 0 &&
        _normalize(track.title).isNotEmpty &&
        _normalize(original.title) == _normalize(track.title) &&
        artists.isNotEmpty &&
        artists.containsAll(_artists(original.artist)) &&
        _artists(original.artist).containsAll(artists);
    return SongCommentQuery(
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationSeconds: useOriginalDuration
          ? original.durationSeconds
          : track.duration?.inSeconds ?? 0,
      platformIds: ids,
    );
  }

  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final Map<SongCommentPlatform, String> platformIds;
  String get searchText => '$title $artist'.trim();

  Uri searchUrl(SongCommentPlatform platform) =>
      platform == SongCommentPlatform.qq
      ? Uri.https('y.qq.com', '/n/ryqq/search', {'w': searchText})
      : Uri.https('music.163.com', '/').replace(
          fragment: '/search/m/?s=${Uri.encodeComponent(searchText)}&type=1',
        );

  String key(SongCommentPlatform platform) => jsonEncode([
    platform.name,
    _normalize(title),
    _normalize(artist),
    _normalize(album),
    durationSeconds,
    platformIds[platform],
  ]);
}

class CommentSong {
  const CommentSong({
    required this.id,
    required this.title,
    required this.artist,
    this.webId = '',
    this.album = '',
    this.durationSeconds = 0,
  });
  final String id;
  final String webId;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;

  Uri url(SongCommentPlatform platform) => platform == SongCommentPlatform.qq
      ? Uri.https(
          'y.qq.com',
          '/n/ryqq/songDetail/${webId.isEmpty ? id : webId}',
        )
      : Uri.https('music.163.com', '/song', {'id': id});

  Map<String, Object?> toJson() => {
    'id': id,
    'webId': webId,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': durationSeconds,
  };
  factory CommentSong.fromJson(Map<String, dynamic> json) => CommentSong(
    id: _text(json['id']),
    webId: _text(json['webId']),
    title: _text(json['title']),
    artist: _text(json['artist']),
    album: _text(json['album']),
    durationSeconds: _int(json['duration']),
  );
}

class SongComment {
  const SongComment({
    required this.id,
    required this.author,
    required this.content,
    required this.likes,
    this.createdAt,
  });
  final String id;
  final String author;
  final String content;
  final int likes;
  final DateTime? createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'author': author,
    'content': content,
    'likes': likes,
    'createdAt': createdAt?.toIso8601String(),
  };
  factory SongComment.fromJson(Map<String, dynamic> json) => SongComment(
    id: _text(json['id']),
    author: _text(json['author']),
    content: _text(json['content']),
    likes: _int(json['likes']),
    createdAt: DateTime.tryParse('${json['createdAt']}'),
  );
}

enum SongCommentsStatus { ready, noMatch, unavailable }

class SongCommentsResult {
  const SongCommentsResult({
    required this.platform,
    required this.status,
    required this.pageUrl,
    this.song,
    this.comments = const [],
    this.fromCache = false,
    this.stale = false,
    this.hasMore = false,
    this.nextCursor,
  });
  final SongCommentPlatform platform;
  final SongCommentsStatus status;
  final Uri pageUrl;
  final CommentSong? song;
  final List<SongComment> comments;
  final bool fromCache;
  final bool stale;
  final bool hasMore;
  final String? nextCursor;
}

/// Read-only, on-demand public comments. This never runs on the playback path.
class SongCommentsRepository {
  SongCommentsRepository({
    MusicResolverHttp? httpClient,
    Future<Directory> Function()? rootProvider,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 8),
  }) : _http = httpClient,
       _rootProvider = rootProvider ?? getAiMusicSupportDirectory,
       _now = now ?? DateTime.now;

  static final shared = SongCommentsRepository();
  final MusicResolverHttp? _http;
  final Future<Directory> Function() _rootProvider;
  final DateTime Function() _now;
  final Duration requestTimeout;
  static const _commentsLifetime = Duration(hours: 6);
  static const _mappingLifetime = Duration(days: 30);
  final _entries = <String, _CacheEntry>{};
  // Only the first page is persisted. Keep at most 100 further pages in memory
  // so reading a long thread cannot grow the disk cache without a bound.
  final _pages = <(String, int, String?), _CacheEntry>{};
  final _pending = <(String, int, String?), _PendingPage>{};
  final _generations = <String, int>{};
  Future<void>? _loading;
  Future<void> _writeTail = Future.value();
  File? _file;

  Future<SongCommentsResult> load(
    SongCommentQuery query,
    SongCommentPlatform platform, {
    bool refresh = false,
    int page = 0,
    String? cursor,
  }) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    await _loadCache();
    final key = query.key(platform);
    cursor = platform == SongCommentPlatform.qq && page > 0 ? cursor : null;
    final pageKey = (key, page, cursor);
    var generation = _generations[key] ?? 0;
    final pending = _pending[pageKey];
    if (pending != null &&
        pending.generation == generation &&
        (!refresh || pending.refresh)) {
      return pending.work;
    }
    if (refresh && page == 0) {
      generation += 1;
      _generations[key] = generation;
      _pages.removeWhere((k, _) => k.$1 == key);
    }
    if (page > 0) {
      // A page requested during a new first-page refresh must use that mapping,
      // not the previous song/cursor while its replacement is still in flight.
      final first = _pending[(key, 0, null)];
      if (first != null && first.generation == generation) await first.work;
      if ((_generations[key] ?? 0) != generation) {
        return _unavailable(query, platform);
      }
      if (platform == SongCommentPlatform.qq && (cursor?.isEmpty ?? true)) {
        return _unavailable(query, platform);
      }
      final joined = _pending[pageKey];
      if (joined != null && joined.generation == generation) return joined.work;
    }
    final cached = page == 0 ? _entries[key] : _pages[pageKey];
    if (!refresh && cached != null && _fresh(cached.at, _commentsLifetime)) {
      if (page > 0) {
        _pages.remove(pageKey);
        _pages[pageKey] = cached;
      }
      return _result(platform, cached, fromCache: true);
    }
    final work = _fetch(
      query,
      platform,
      cached,
      refresh: refresh,
      page: page,
      cursor: cursor,
      generation: generation,
    );
    final request = _PendingPage(work, generation, refresh);
    _pending[pageKey] = request;
    try {
      return await work;
    } finally {
      if (identical(_pending[pageKey], request)) _pending.remove(pageKey);
    }
  }

  Future<SongCommentsResult> _fetch(
    SongCommentQuery query,
    SongCommentPlatform platform,
    _CacheEntry? cached, {
    required bool refresh,
    required int page,
    required String? cursor,
    required int generation,
  }) async {
    final key = query.key(platform);
    bool isCurrent() => (_generations[key] ?? 0) == generation;
    CommentSong? song;
    try {
      final mapping = _entries[key] ?? cached;
      song =
          !(refresh && page == 0) &&
              mapping != null &&
              _fresh(mapping.at, _mappingLifetime)
          ? mapping.song
          : await _findSong(query, platform);
      if (!isCurrent()) return _unavailable(query, platform);
      if (song == null) {
        if (page == 0) {
          _entries.remove(key);
          _pages.removeWhere((k, _) => k.$1 == key);
          await _saveCache();
        }
        return SongCommentsResult(
          platform: platform,
          status: SongCommentsStatus.noMatch,
          pageUrl: query.searchUrl(platform),
        );
      }
      final response = await _request(
        platform,
        (http, headers) => http.get(
          platform == SongCommentPlatform.netease
              ? Uri.https(
                  'music.163.com',
                  '/api/v1/resource/hotcomments/R_SO_4_${song!.id}',
                  {'limit': '20', 'offset': '${page * 20}'},
                )
              : Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
                  'format': 'json',
                  'data': jsonEncode({
                    'comm': {'ct': 24, 'cv': 0, 'format': 'json', 'uin': 0},
                    'request': {
                      'module': 'music.globalComment.CommentRead',
                      'method': 'GetHotCommentList',
                      'param': {
                        'BizType': 1,
                        'BizId': song!.id,
                        'LastCommentSeqNo': cursor ?? '',
                        'PageSize': 20,
                        'PageNum': page,
                        'HotType': 1,
                        'WithAirborne': 0,
                        'PicEnable': 1,
                      },
                    },
                  }),
                }),
          headers: headers,
        ),
      );
      if (!isCurrent()) return _unavailable(query, platform);
      final parsed = _parseCommentsPage(response.body, platform);
      final hasMore =
          parsed.hasMore &&
          (platform != SongCommentPlatform.qq || parsed.nextCursor != cursor);
      final entry = _CacheEntry(
        song,
        parsed.comments,
        _now(),
        hasMore: hasMore,
        nextCursor: hasMore ? parsed.nextCursor : null,
      );
      if (page == 0) {
        _entries[key] = entry;
        await _saveCache();
      } else {
        final pageKey = (key, page, cursor);
        _pages.remove(pageKey);
        _pages[pageKey] = entry;
        while (_pages.length > 100) {
          _pages.remove(_pages.keys.first);
        }
      }
      return _result(platform, entry);
    } catch (_) {
      if (!isCurrent()) return _unavailable(query, platform);
      if (cached != null && _fresh(cached.at, _mappingLifetime)) {
        return _result(platform, cached, fromCache: true, stale: true);
      }
      return SongCommentsResult(
        platform: platform,
        status: SongCommentsStatus.unavailable,
        pageUrl: song?.url(platform) ?? query.searchUrl(platform),
        song: song,
      );
    }
  }

  SongCommentsResult _unavailable(
    SongCommentQuery query,
    SongCommentPlatform platform,
  ) => SongCommentsResult(
    platform: platform,
    status: SongCommentsStatus.unavailable,
    pageUrl: query.searchUrl(platform),
  );

  SongCommentsResult _result(
    SongCommentPlatform platform,
    _CacheEntry entry, {
    bool fromCache = false,
    bool stale = false,
  }) => SongCommentsResult(
    platform: platform,
    status: SongCommentsStatus.ready,
    pageUrl: entry.song.url(platform),
    song: entry.song,
    comments: entry.comments,
    fromCache: fromCache,
    stale: stale,
    hasMore: entry.hasMore,
    nextCursor: entry.nextCursor,
  );

  Future<CommentSong?> _findSong(
    SongCommentQuery query,
    SongCommentPlatform platform,
  ) async {
    if (_normalize(query.title).isEmpty || _normalize(query.artist).isEmpty) {
      return null;
    }
    final knownId = query.platformIds[platform];
    if (knownId != null && _validId(knownId, platform)) {
      try {
        final details = await _songDetails(knownId, platform);
        final exact = selectCommentSong(query, details);
        if (exact != null) return exact;
      } catch (_) {
        // IDs from saved playlists/providers are optional hints. A failed
        // detail endpoint must not bypass the same strict search verification.
      }
    }
    final response = await _request(
      platform,
      (http, headers) => platform == SongCommentPlatform.netease
          ? http.postForm(Uri.https('music.163.com', '/api/search/get'), {
              's': query.searchText,
              'type': '1',
              'limit': '20',
              'offset': '0',
            }, headers: headers)
          : http.get(
              Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {
                'format': 'json',
                'w': query.searchText,
                'n': '20',
                'p': '1',
              }),
              headers: headers,
            ),
    );
    final root = _decode(response.body, platform);
    final rows = platform == SongCommentPlatform.netease
        ? _map(root['result'])['songs']
        : _map(_map(root['data'])['song'])['list'];
    if (rows is! List) {
      throw const FormatException('Missing song search results');
    }
    return selectCommentSong(query, [
      for (final row in rows) _song(_map(row), platform),
    ]);
  }

  Future<List<CommentSong>> _songDetails(
    String id,
    SongCommentPlatform platform,
  ) async {
    final response = await _request(
      platform,
      (http, headers) => http.get(
        platform == SongCommentPlatform.netease
            ? Uri.https('music.163.com', '/api/song/detail', {
                'ids': jsonEncode([int.parse(id)]),
              })
            : Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
                'format': 'json',
                'data': jsonEncode({
                  'request': {
                    'module': 'music.pf_song_detail_svr',
                    'method': 'get_song_detail_yqq',
                    'param': {
                      if (RegExp(r'^\d+$').hasMatch(id))
                        'song_id': int.parse(id)
                      else
                        'song_mid': id,
                    },
                  },
                }),
              }),
        headers: headers,
      ),
    );
    final root = _decode(response.body, platform);
    if (platform == SongCommentPlatform.netease) {
      final songs = root['songs'];
      if (songs is! List) throw const FormatException('Missing song details');
      return [for (final row in songs) _song(_map(row), platform)];
    }
    final request = _map(root['request']);
    if (request['code'] != 0) throw const FormatException('Song unavailable');
    final row = _map(_map(request['data'])['track_info']);
    return [_song(row, platform)];
  }

  Future<ResolverHttpResponse> _request(
    SongCommentPlatform platform,
    Future<ResolverHttpResponse> Function(
      MusicResolverHttp,
      Map<String, String>,
    )
    request,
  ) async {
    final ownedClient = _http == null ? HttpClient() : null;
    try {
      final response =
          await request(_http ?? HttpMusicResolverClient(client: ownedClient), {
            'User-Agent': 'Mozilla/5.0',
            'Referer': platform == SongCommentPlatform.qq
                ? 'https://y.qq.com/'
                : 'https://music.163.com/',
          }).timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return response;
    } finally {
      ownedClient?.close(force: true);
    }
  }

  bool _fresh(DateTime at, Duration lifetime) =>
      !_now().isBefore(at) && _now().difference(at) < lifetime;
  Future<void> _loadCache() => _loading ??= () async {
    try {
      _file = File('${(await _rootProvider()).path}/song_comments_cache.json');
      final data = _map(await const JsonFileStore().read(_file!));
      if (data['schema'] != 3 || data['entries'] is! List) return;
      for (final value in (data['entries'] as List).take(100)) {
        try {
          final row = _map(value);
          final at = DateTime.parse('${row['at']}');
          final song = CommentSong.fromJson(_map(row['song']));
          if (!_fresh(at, _mappingLifetime) ||
              song.id.isEmpty ||
              song.title.isEmpty ||
              row['comments'] is! List) {
            continue;
          }
          _entries[_text(row['key'])] = _CacheEntry(
            song,
            [
              for (final item in (row['comments'] as List).take(20))
                SongComment.fromJson(_map(item)),
            ],
            at,
            hasMore: row['hasMore'] == true,
            nextCursor: row['nextCursor'] as String?,
          );
        } catch (_) {
          /* Skip one damaged entry. */
        }
      }
    } catch (_) {
      /* Cache is optional. */
    }
  }();

  Future<void> _saveCache() {
    _entries.removeWhere((_, entry) => !_fresh(entry.at, _mappingLifetime));
    final keys = _entries.keys.toList()
      ..sort((a, b) => _entries[a]!.at.compareTo(_entries[b]!.at));
    for (final key in keys.take(
      (_entries.length - 100).clamp(0, keys.length),
    )) {
      _entries.remove(key);
    }
    final data = {
      'schema': 3,
      'entries': [
        for (final row in _entries.entries)
          {
            'key': row.key,
            'at': row.value.at.toIso8601String(),
            'song': row.value.song.toJson(),
            'hasMore': row.value.hasMore,
            'nextCursor': row.value.nextCursor,
            'comments': [
              for (final comment in row.value.comments) comment.toJson(),
            ],
          },
      ],
    };
    return _writeTail = _writeTail.then((_) async {
      try {
        if (_file != null) await const JsonFileStore().write(_file!, data);
      } catch (_) {
        /* Cache is optional. */
      }
    });
  }
}

class _CacheEntry {
  _CacheEntry(
    this.song,
    List<SongComment> comments,
    this.at, {
    this.hasMore = false,
    this.nextCursor,
  }) : comments = List.unmodifiable(comments);
  final CommentSong song;
  final List<SongComment> comments;
  final DateTime at;
  final bool hasMore;
  final String? nextCursor;
}

class _PendingPage {
  _PendingPage(this.work, this.generation, this.refresh);
  final Future<SongCommentsResult> work;
  final int generation;
  final bool refresh;
}

/// Deliberately stricter than playback fallback: never show another singer's
/// comments merely because their cover is the first search result.
CommentSong? selectCommentSong(
  SongCommentQuery query,
  List<CommentSong> songs,
) {
  final artists = _artists(query.artist);
  final matches = songs
      .where(
        (song) =>
            RegExp(r'^\d+$').hasMatch(song.id) &&
            _normalize(song.title) == _normalize(query.title) &&
            artists.isNotEmpty &&
            _artists(song.artist).containsAll(artists) &&
            artists.containsAll(_artists(song.artist)) &&
            (query.durationSeconds <= 0 ||
                song.durationSeconds <= 0 ||
                (query.durationSeconds - song.durationSeconds).abs() <= 12),
      )
      .toList();
  if (matches.isEmpty) return null;
  if (_normalize(query.album).isNotEmpty) {
    final album = matches
        .where((song) => _normalize(song.album) == _normalize(query.album))
        .firstOrNull;
    if (album != null) return album;
  }
  return matches.first;
}

List<SongComment> parseSongComments(
  String body,
  SongCommentPlatform platform,
) => _parseCommentsPage(body, platform).comments;

class _CommentsPage {
  const _CommentsPage(this.comments, this.hasMore, this.nextCursor);
  final List<SongComment> comments;
  final bool hasMore;
  final String? nextCursor;
}

_CommentsPage _parseCommentsPage(String body, SongCommentPlatform platform) {
  final root = _decode(body, platform);
  final qq = platform == SongCommentPlatform.qq;
  final modernQq = qq && root.containsKey('request');
  final request = _map(root['request']);
  if (modernQq && request['code'] != 0) {
    throw const FormatException('Hot comments unavailable');
  }
  final list = _map(_map(request['data'])['CommentList']);
  final rows = !qq
      ? root['hotComments']
      : modernQq
      ? list['Comments']
      : _map(root['hot_comment'])['commentlist'];
  if (rows is! List) throw const FormatException('Hot comments unavailable');
  final comments = <SongComment>[];
  final seen = <String>{};
  for (final value in rows.take(20)) {
    final row = _map(value);
    final id = _text(
      row[modernQq
          ? 'CmId'
          : qq
          ? 'commentid'
          : 'commentId'],
    );
    final content = _text(
      row[modernQq
          ? 'Content'
          : qq
          ? 'rootcommentcontent'
          : 'content'],
    );
    if (id.isEmpty || content.isEmpty || !seen.add(id)) continue;
    final time = _int(row[modernQq ? 'PubTime' : 'time']);
    comments.add(
      SongComment(
        id: id,
        author: _text(
          qq ? row[modernQq ? 'Nick' : 'nick'] : _map(row['user'])['nickname'],
        ),
        content: content,
        likes: _int(
          row[modernQq
              ? 'PraiseNum'
              : qq
              ? 'praisenum'
              : 'likedCount'],
        ).clamp(0, 1 << 53),
        createdAt: time > 0
            ? DateTime.fromMillisecondsSinceEpoch(qq ? time * 1000 : time)
            : null,
      ),
    );
  }
  comments.sort((a, b) => b.likes.compareTo(a.likes));
  // QQ's cursor is the last *wire-order* SeqNo, not the ID or last row after
  // sorting by likes. NextOffset remains zero even on valid later QQ pages.
  final cursor = modernQq && rows.isNotEmpty
      ? _text(_map(rows.take(20).last)['SeqNo'])
      : '';
  final rawMore = qq ? list['HasMore'] : root['hasMore'];
  final hasMore =
      comments.isNotEmpty &&
      (rawMore == true || _int(rawMore) == 1) &&
      (!qq || cursor.isNotEmpty);
  return _CommentsPage(
    List.unmodifiable(comments),
    hasMore,
    hasMore && qq ? cursor : null,
  );
}

CommentSong _song(Map<String, dynamic> row, SongCommentPlatform platform) {
  final qq = platform == SongCommentPlatform.qq;
  final artists = row[qq ? 'singer' : 'artists'] ?? row['ar'];
  final album = _map(row['album'] ?? row['al']);
  return CommentSong(
    id: _text(row['songid'] ?? row['id']),
    webId: _text(row['songmid'] ?? row['mid']),
    // QQ's name/songname may omit the version suffix that title preserves.
    // Keep accompaniment/live/remix identities distinct before comment lookup.
    title: qq
        ? [
                row['title'],
                row['songname'],
                row['name'],
              ].map(_text).where((value) => value.isNotEmpty).firstOrNull ??
              ''
        : _text(row['name'] ?? row['title']),
    artist: artists is List
        ? artists
              .map((a) => _text(_map(a)['name']))
              .where((a) => a.isNotEmpty)
              .join(' / ')
        : '',
    album: _text(row['albumname'] ?? album['name']),
    durationSeconds: qq
        ? _int(row['interval'])
        : _int(row['duration'] ?? row['dt']) ~/ 1000,
  );
}

Map<String, dynamic> _decode(String body, SongCommentPlatform platform) {
  final root = _map(jsonDecode(body));
  if (_int(root['code']) != (platform == SongCommentPlatform.qq ? 0 : 200) ||
      !root.containsKey('code')) {
    throw const FormatException('Comment service unavailable');
  }
  return root;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : {};
int _int(Object? value) => int.tryParse('$value') ?? 0;
String _text(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();
String _normalize(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]', unicode: true),
  '',
);
Set<String> _artists(String text) => text
    .split(RegExp(r'\s*[/、,&;；]\s*'))
    .map(_normalize)
    .where((s) => s.isNotEmpty)
    .toSet();
SongCommentPlatform? _platform(String value) => switch (value.toLowerCase()) {
  'qq' || 'tencent' => SongCommentPlatform.qq,
  'netease' || 'wyy' => SongCommentPlatform.netease,
  _ => null,
};
bool _validId(String id, SongCommentPlatform platform) =>
    RegExp(r'^\d{1,20}$').hasMatch(id) ||
    (platform == SongCommentPlatform.qq &&
        RegExp(r'^[a-zA-Z0-9]{14}$').hasMatch(id));
