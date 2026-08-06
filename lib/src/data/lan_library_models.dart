const defaultLanLibraryUrl = 'http://192.168.31.57:8787';

Uri normalizeLanLibraryBaseUri(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('请输入完整的局域网音乐库地址');
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const FormatException('局域网音乐库地址只支持 HTTP 或 HTTPS');
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException('局域网音乐库地址不能包含账号、查询参数或片段');
  }
  if (scheme == 'http' && !_isPrivateOrLoopbackHost(uri.host)) {
    throw const FormatException('明文 HTTP 只允许回环或私网 IP 地址');
  }

  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') {
    path = '';
  }
  return uri.replace(scheme: scheme, path: path, query: null, fragment: null);
}

bool _isPrivateOrLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '::1') {
    return true;
  }
  if (normalized.contains(':')) {
    return normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe8') ||
        normalized.startsWith('fe9') ||
        normalized.startsWith('fea') ||
        normalized.startsWith('feb');
  }
  final parts = normalized.split('.');
  if (parts.length != 4) {
    return false;
  }
  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  return first == 10 ||
      first == 127 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168) ||
      (first == 169 && second == 254);
}

class LanLibraryManifest {
  const LanLibraryManifest({
    required this.schemaVersion,
    required this.libraryId,
    required this.generatedAt,
    required this.tracks,
  });

  factory LanLibraryManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _positiveInt(json['schemaVersion'], 'schemaVersion');
    if (schemaVersion != 1) {
      throw FormatException('不支持的局域网清单版本：$schemaVersion');
    }
    final libraryId = _requiredString(json['libraryId'], 'libraryId');
    final generatedAtText = _requiredString(json['generatedAt'], 'generatedAt');
    final generatedAt = DateTime.tryParse(generatedAtText);
    if (generatedAt == null) {
      throw const FormatException('generatedAt 必须是 ISO-8601 时间');
    }
    final rows = json['tracks'];
    if (rows is! List) {
      throw const FormatException('tracks 必须是数组');
    }
    final ids = <String>{};
    final tracks = <LanTrackEntry>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('tracks 中的项目必须是对象');
      }
      final track = LanTrackEntry.fromJson(row.cast<String, dynamic>());
      if (!ids.add(track.id)) {
        throw FormatException('清单中存在重复曲目 ID：${track.id}');
      }
      tracks.add(track);
    }
    return LanLibraryManifest(
      schemaVersion: schemaVersion,
      libraryId: libraryId,
      generatedAt: generatedAt,
      tracks: List.unmodifiable(tracks),
    );
  }

  final int schemaVersion;
  final String libraryId;
  final DateTime generatedAt;
  final List<LanTrackEntry> tracks;
}

String normalizeLanFolderPath(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) {
    return '';
  }
  if (raw.length > 1024 ||
      raw.startsWith('/') ||
      raw.contains(r'\') ||
      raw.contains('\u0000')) {
    throw const FormatException('track.folderPath 必须是安全的相对 POSIX 路径');
  }
  _validateLanFolderSegments(raw);

  final decodedForValidation = raw
      .replaceAll(RegExp('%2e', caseSensitive: false), '.')
      .replaceAll(RegExp('%2f', caseSensitive: false), '/')
      .replaceAll(RegExp('%5c', caseSensitive: false), r'\')
      .replaceAll(RegExp('%00', caseSensitive: false), '\u0000');
  if (decodedForValidation != raw) {
    if (decodedForValidation.startsWith('/') ||
        decodedForValidation.contains(r'\') ||
        decodedForValidation.contains('\u0000')) {
      throw const FormatException('track.folderPath 包含不安全的编码路径');
    }
    _validateLanFolderSegments(decodedForValidation);
  }
  return raw;
}

void _validateLanFolderSegments(String value) {
  final segments = value.split('/');
  if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('track.folderPath 不能包含空目录或目录穿越');
  }
}

class LanTrackEntry {
  const LanTrackEntry({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.folderPath,
    required this.audio,
    this.lyrics,
    this.artwork,
  });

  factory LanTrackEntry.fromJson(Map<String, dynamic> json) {
    return LanTrackEntry(
      id: _requiredString(json['id'], 'track.id'),
      title: _requiredString(json['title'], 'track.title'),
      artist: _requiredString(json['artist'], 'track.artist'),
      album: json['album']?.toString().trim() ?? '',
      folderPath: normalizeLanFolderPath(json['folderPath']),
      audio: LanAsset.fromJson(
        _requiredMap(json['audio'], 'track.audio'),
        kind: LanAssetKind.audio,
      ),
      lyrics: json['lyrics'] == null
          ? null
          : LanAsset.fromJson(
              _requiredMap(json['lyrics'], 'track.lyrics'),
              kind: LanAssetKind.lyrics,
            ),
      artwork: json['artwork'] == null
          ? null
          : LanAsset.fromJson(
              _requiredMap(json['artwork'], 'track.artwork'),
              kind: LanAssetKind.artwork,
            ),
    );
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final String folderPath;
  final LanAsset audio;
  final LanAsset? lyrics;
  final LanAsset? artwork;
}

enum LanAssetKind { audio, lyrics, artwork }

const _maximumLanAudioBytes = 2 * 1024 * 1024 * 1024;
const _maximumLanLyricsBytes = 4 * 1024 * 1024;
const _maximumLanArtworkBytes = 20 * 1024 * 1024;

class LanAsset {
  const LanAsset({
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    this.format = '',
    this.mimeType = '',
  });

  factory LanAsset.fromJson(
    Map<String, dynamic> json, {
    required LanAssetKind kind,
  }) {
    final url = _assetUri(json['url']);
    final sizeBytes = _positiveInt(json['sizeBytes'], 'asset.sizeBytes');
    final sha256 = _requiredString(
      json['sha256'],
      'asset.sha256',
    ).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('asset.sha256 必须是 64 位十六进制 SHA-256');
    }
    final format = json['format']?.toString().trim().toLowerCase() ?? '';
    final mimeType = json['mimeType']?.toString().trim().toLowerCase() ?? '';
    switch (kind) {
      case LanAssetKind.audio:
        if (!const {'mp3', 'flac'}.contains(format)) {
          throw FormatException('不支持的音频格式：$format');
        }
        if (sizeBytes > _maximumLanAudioBytes) {
          throw const FormatException('局域网音频文件超过 2 GiB 限制');
        }
      case LanAssetKind.lyrics:
        if (format != 'lrc') {
          throw FormatException('不支持的歌词格式：$format');
        }
        if (sizeBytes > _maximumLanLyricsBytes) {
          throw const FormatException('局域网歌词文件超过 4 MiB 限制');
        }
      case LanAssetKind.artwork:
        if (!const {'image/png', 'image/jpeg'}.contains(mimeType)) {
          throw FormatException('不支持的封面格式：$mimeType');
        }
        if (sizeBytes > _maximumLanArtworkBytes) {
          throw const FormatException('局域网封面文件超过 20 MiB 限制');
        }
    }
    return LanAsset(
      url: url,
      sizeBytes: sizeBytes,
      sha256: sha256,
      format: format,
      mimeType: mimeType,
    );
  }

  final Uri url;
  final int sizeBytes;
  final String sha256;
  final String format;
  final String mimeType;
}

Uri _assetUri(Object? value) {
  final raw = _requiredString(value, 'asset.url');
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.startsWith('/api/v1/files/')) {
    throw const FormatException('asset.url 必须是 /api/v1/files/ 下的相对资源地址');
  }
  String decodedPath;
  try {
    decodedPath = Uri.decodeComponent(raw);
  } on FormatException {
    throw const FormatException('asset.url 包含无效的百分号编码');
  }
  if (decodedPath
      .split(RegExp(r'[/\\]'))
      .any((segment) => segment == '.' || segment == '..')) {
    throw const FormatException('asset.url 不能包含目录穿越');
  }
  return uri;
}

Map<String, dynamic> _requiredMap(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('$name 必须是对象');
  }
  return value.cast<String, dynamic>();
}

String _requiredString(Object? value, String name) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    throw FormatException('$name 不能为空');
  }
  return text;
}

int _positiveInt(Object? value, String name) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name 必须是正整数');
  }
  return parsed;
}
