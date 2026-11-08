import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'json_file_store.dart';
import '../platform/app_storage.dart';

/// Talks to the LAN service's per-device backup endpoints
/// (`tool/lan_backups.py`).
class LanBackupException implements Exception {
  const LanBackupException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'LanBackupException($statusCode): $message';
}

/// One device's backup as the server lists it.
class LanBackupDevice {
  const LanBackupDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.receivedAt,
    required this.playlistCount,
    required this.favoriteCount,
    required this.trackCount,
    required this.totalBytes,
  });

  final String deviceId, deviceName, platform;
  final DateTime? receivedAt;
  final int playlistCount, favoriteCount, trackCount, totalBytes;

  static LanBackupDevice? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['deviceId']?.toString() ?? '';
    if (id.isEmpty) return null;
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    return LanBackupDevice(
      deviceId: id,
      deviceName: value['deviceName']?.toString() ?? id,
      platform: value['platform']?.toString() ?? '',
      receivedAt: DateTime.tryParse(value['receivedAt']?.toString() ?? ''),
      playlistCount: number('playlistCount'),
      favoriteCount: number('favoriteCount'),
      trackCount: number('trackCount'),
      totalBytes: number('totalBytes'),
    );
  }
}

class LanBackupClient {
  LanBackupClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient();

  final HttpClient _http;

  Uri _uri(String base, String path) =>
      Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/v1/backup$path');

  Future<List<LanBackupDevice>> devices(String base) async {
    final document = await _json('GET', _uri(base, '/devices'));
    final rows = document is Map ? document['devices'] : null;
    return [
      for (final row in rows is List ? rows : const []) ?LanBackupDevice.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> manifest(String base, String deviceId) async {
    final document = await _json(
      'GET',
      _uri(base, '/devices/${Uri.encodeComponent(deviceId)}'),
    );
    if (document is! Map) {
      throw const LanBackupException('Invalid backup manifest');
    }
    return document.cast<String, dynamic>();
  }

  Future<Set<String>> missing(String base, Iterable<String> hashes) async {
    final all = hashes.toSet().toList();
    final result = <String>{};
    // The server takes at most 20000 hashes per request.
    for (var i = 0; i < all.length; i += 5000) {
      final document = await _json(
        'POST',
        _uri(base, '/blobs/missing'),
        body: {'sha256': all.sublist(i, min(i + 5000, all.length))},
      );
      final rows = document is Map ? document['missing'] : null;
      result.addAll([for (final row in rows is List ? rows : const []) '$row']);
    }
    return result;
  }

  Future<void> putBlob(String base, String sha256, File file) async {
    final request = await _http
        .openUrl('PUT', _uri(base, '/blobs/$sha256'))
        .timeout(const Duration(seconds: 15));
    request.headers.contentType = ContentType.binary;
    request.contentLength = await file.length();
    await request.addStream(file.openRead());
    await _finish(request, const Duration(minutes: 5));
  }

  Future<void> putManifest(
    String base,
    String deviceId,
    Map<String, Object?> manifest,
  ) async {
    await _json(
      'PUT',
      _uri(base, '/devices/${Uri.encodeComponent(deviceId)}'),
      body: manifest,
    );
  }

  /// Downloads a file and checks it against its hash before it is kept.
  Future<void> downloadBlob(String base, String sha256, File target) async {
    final request = await _http
        .openUrl('GET', _uri(base, '/blobs/$sha256'))
        .timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw LanBackupException(
        'Download failed',
        statusCode: response.statusCode,
      );
    }
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.download');
    final sink = temporary.openWrite();
    final digest = _DigestSink();
    final hasher = sha256Hasher.startChunkedConversion(digest);
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        hasher.add(chunk);
        sink.add(chunk);
      }
      hasher.close();
      await sink.close();
      if (digest.value.toString() != sha256) {
        throw const LanBackupException('Downloaded file does not match');
      }
      await temporary.rename(target.path);
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<Object?> _json(String method, Uri uri, {Object? body}) async {
    final request = await _http
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 15));
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final text = await _finish(request, const Duration(seconds: 60));
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<String> _finish(HttpClientRequest request, Duration timeout) async {
    final response = await request.close().timeout(timeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LanBackupException(
        _reason(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    return text;
  }

  static String _reason(int status) => switch (status) {
    403 => '只接受局域网内的设备',
    404 => '局域网服务上没有这份备份',
    409 => '有歌曲文件还没上传完',
    413 => '内容太大',
    503 => '局域网服务暂时不可用（可能磁盘空间不足）',
    _ => '局域网服务返回 $status',
  };

  void close() => _http.close(force: true);
}

/// SHA-256 of a file, streamed.
Future<String> fileSha256(File file) async {
  final digest = await sha256Hasher.bind(file.openRead()).first;
  return digest.toString();
}

final sha256Hasher = sha256;

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// This device's stable backup ID and its editable display name.
class LanBackupIdentity {
  const LanBackupIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.serverUrl,
  });

  final String deviceId, deviceName, serverUrl;

  LanBackupIdentity copyWith({String? deviceName, String? serverUrl}) =>
      LanBackupIdentity(
        deviceId: deviceId,
        deviceName: deviceName ?? this.deviceName,
        serverUrl: serverUrl ?? this.serverUrl,
      );

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'serverUrl': serverUrl,
  };
}

class LanBackupIdentityStore {
  LanBackupIdentityStore({
    Future<Directory> Function()? rootProvider,
    required this.defaultServerUrl,
    this.defaultName,
  }) : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;

  final Future<Directory> Function() _rootProvider;
  final String defaultServerUrl;
  final String Function(String shortId)? defaultName;
  final _store = const JsonFileStore();

  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/lan_backup_device.json');

  Future<LanBackupIdentity> load() async {
    final file = await _file();
    try {
      final value = await _store.read(file, backupCorrupt: true);
      if (value is Map && value['deviceId'] is String) {
        return LanBackupIdentity(
          deviceId: value['deviceId'] as String,
          deviceName: value['deviceName']?.toString() ?? '',
          serverUrl: value['serverUrl']?.toString() ?? defaultServerUrl,
        );
      }
    } on Object {
      // A fresh identity below; the corrupt file was backed up.
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final shortId = id.substring(0, 4).toUpperCase();
    final identity = LanBackupIdentity(
      deviceId: 'device-$id',
      deviceName: defaultName?.call(shortId) ?? _platformName(shortId),
      serverUrl: defaultServerUrl,
    );
    await save(identity);
    return identity;
  }

  Future<void> save(LanBackupIdentity identity) async =>
      _store.write(await _file(), identity.toJson());

  static String _platformName(String shortId) {
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iPhone'
        : Platform.isMacOS
        ? 'Mac'
        : Platform.operatingSystem;
    return '$platform·$shortId';
  }
}
