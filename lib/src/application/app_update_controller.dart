import '../domain/app_brand.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../data/json_file_store.dart';
import '../platform/app_storage.dart';

const defaultUpdateUrl = 'https://github.com/qiHuang112/ai_music';
const legacyUpdateUrl = 'http://192.168.31.167:8788';

bool _isGitHubUpdateServer(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.port == 443 &&
    uri.path == '/qiHuang112/ai_music/';

bool _isGitHubAsset(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    !uri.hasFragment &&
    const {
      'github.com',
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
    }.contains(uri.host);

Future<HttpClientResponse> _openUpdateRequest(
  HttpClient client,
  Uri uri,
  Uri server,
  Duration timeout,
) async {
  for (var redirects = 0; ; redirects++) {
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (!const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
      return response;
    }
    final location = response.headers.value(HttpHeaders.locationHeader);
    final next = location == null ? null : uri.resolve(location);
    if (!_isGitHubUpdateServer(server) ||
        redirects >= 5 ||
        next == null ||
        !_isGitHubAsset(next)) {
      throw const HttpException('更新服务重定向无效');
    }
    await response.drain<void>().timeout(timeout);
    uri = next;
  }
}

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.name,
    required this.code,
    required this.builtAt,
    required this.channel,
    this.abis = const ['arm64-v8a'],
  });
  final String name;
  final int code;
  final DateTime builtAt;
  final String channel;
  final List<String> abis;
  String get label => '$name ($code)';
}

class AppRelease {
  const AppRelease({
    required this.name,
    required this.code,
    required this.publishedAt,
    required this.url,
    required this.sha256Hex,
    required this.size,
    required this.notes,
  });
  final String name;
  final int code;
  final DateTime publishedAt;
  final Uri url;
  final String sha256Hex;
  final int size;
  final String notes;
  static AppRelease parse(
    Map<String, dynamic> json,
    Uri server,
    InstalledAppVersion current,
  ) {
    final code = json['versionCode'];
    final size = json['sizeBytes'];
    final name = json['versionName'];
    final hash = json['sha256'];
    final date = DateTime.tryParse(json['publishedAt']?.toString() ?? '');
    final path = json['url']?.toString() ?? '';
    final uri = server.resolve(path);
    if (json['packageName'] != 'com.qi.ai.music' ||
        json['channel'] != 'release' ||
        !current.abis.contains(json['abi']) ||
        code is! int ||
        code < 1 ||
        size is! int ||
        size < 1 ||
        size > 500 * 1024 * 1024 ||
        name is! String ||
        name.isEmpty ||
        hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        date == null ||
        path.isEmpty ||
        (_isGitHubUpdateServer(server)
            ? (uri.origin != server.origin ||
                  !uri.path.startsWith(
                    '/qiHuang112/ai_music/releases/download/',
                  ))
            : uri.origin != server.origin) ||
        !uri.path.endsWith('.apk') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('更新包信息不完整或与设备不兼容');
    }
    return AppRelease(
      name: name,
      code: code,
      publishedAt: date,
      url: uri,
      sha256Hex: hash.toLowerCase(),
      size: size,
      notes: json['notes']?.toString() ?? '',
    );
  }
}

abstract class AndroidUpdateBridge {
  Future<InstalledAppVersion> info();

  /// Returns false after opening the system install-permission settings.
  Future<bool> install(File apk, int versionCode);
}

class NativeAndroidUpdateBridge implements AndroidUpdateBridge {
  static const _channel = MethodChannel('ai_music/app_update');
  @override
  Future<InstalledAppVersion> info() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('info');
    if (data == null) throw StateError('无法读取当前版本');
    return InstalledAppVersion(
      name: data['versionName'] as String,
      code: data['versionCode'] as int,
      builtAt: DateTime.fromMillisecondsSinceEpoch(data['builtAt'] as int),
      channel: data['channel'] as String,
      abis: (data['abis'] as List).cast<String>(),
    );
  }

  @override
  Future<bool> install(File apk, int versionCode) async =>
      await _channel.invokeMethod<bool>('install', {
        'path': apk.path,
        'versionCode': versionCode,
      }) ??
      false;
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    AndroidUpdateBridge? bridge,
    bool? supported,
    Future<Directory> Function()? cacheRoot,
    Future<File> Function()? configFile,
    HttpClient Function()? clientFactory,
  }) : supported = supported ?? Platform.isAndroid,
       _bridge = bridge ?? NativeAndroidUpdateBridge(),
       _cacheRoot = cacheRoot ?? getTemporaryDirectory,
       _configFile = configFile ?? _defaultConfig,
       _clientFactory = clientFactory ?? HttpClient.new;
  final bool supported;
  final AndroidUpdateBridge _bridge;
  final Future<Directory> Function() _cacheRoot;
  final Future<File> Function() _configFile;
  final HttpClient Function() _clientFactory;
  InstalledAppVersion? current;
  AppRelease? latest;
  String serverUrl = defaultUpdateUrl;
  String? error;
  String? installNotice;
  bool checking = false;
  bool downloading = false;
  bool installing = false;
  bool checked = false;
  int received = 0;
  File? downloadedApk;
  DateTime? _lastCheck;
  Future<void>? _initialization;
  HttpClient? _downloadClient;
  int _generation = 0;
  bool _disposed = false;
  bool get releaseChannel => current?.channel == 'release';
  bool get hasUpdate =>
      !checking &&
      releaseChannel &&
      latest != null &&
      latest!.code > current!.code;
  double? get progress =>
      latest == null ? null : (received / latest!.size).clamp(0, 1);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static Future<File> _defaultConfig() async =>
      File('${(await getAiMusicSupportDirectory()).path}/android_update.json');
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!supported) return;
    try {
      current = await _bridge.info();
      final file = await _configFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map && json['serverUrl'] is String) {
          final saved = normalizeServer(json['serverUrl'] as String);
          // Migrate the previous built-in LAN address; preserve custom servers.
          serverUrl = saved == normalizeServer(legacyUpdateUrl)
              ? defaultUpdateUrl
              : saved.toString();
        }
      }
    } catch (_) {
      error = '无法读取版本或更新设置，请重新打开应用';
    }
    _changed();
  }

  static Uri normalizeServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (!['', '/'].contains(uri.path) &&
            !_isGitHubUpdateServer(
              uri.replace(
                path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
              ),
            ))) {
      throw const FormatException('请输入 GitHub 更新地址或局域网服务地址');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Future<void> saveServer(String value) async {
    if (downloading || installing || checking) throw StateError('请先完成或取消当前更新');
    final uri = normalizeServer(value);
    await const JsonFileStore().write(await _configFile(), {
      'serverUrl': uri.toString(),
    });
    _generation++;
    serverUrl = uri.toString();
    latest = null;
    checked = false;
    downloadedApk = null;
    _lastCheck = null;
    _changed();
    await check(force: true);
  }

  Future<void> check({bool force = false}) async {
    await initialize();
    if (!releaseChannel || checking || downloading || installing || _disposed) {
      return;
    }
    if (!force &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 2)) {
      return;
    }
    _lastCheck = DateTime.now();
    final generation = _generation;
    checking = true;
    checked = false;
    error = null;
    _changed();
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final server = normalizeServer(serverUrl);
      final response = await _openUpdateRequest(
        client,
        server.resolve(
          _isGitHubUpdateServer(server)
              ? 'releases/latest/download/latest.json'
              : '/api/v1/update/android',
        ),
        server,
        const Duration(seconds: 8),
      );
      if (response.statusCode == 204) {
        if (generation == _generation) {
          _invalidateRelease();
          checked = true;
        }
        return;
      }
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) throw const FormatException('更新信息过大');
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) throw const FormatException('更新信息无效');
      final release = AppRelease.parse(json, server, current!);
      if (generation == _generation) {
        if (latest?.sha256Hex != release.sha256Hex) downloadedApk = null;
        latest = release;
        checked = true;
      }
    } on FormatException catch (e) {
      if (generation == _generation) {
        _invalidateRelease();
        error = e.message;
      }
    } catch (_) {
      if (generation == _generation) {
        _invalidateRelease();
        error = '无法连接更新服务，请检查网络后重试';
      }
    } finally {
      client.close(force: true);
      checking = false;
      _changed();
    }
  }

  void _invalidateRelease() {
    latest = null;
    downloadedApk = null;
    installNotice = null;
    received = 0;
    checked = false;
  }

  void cancelDownload() {
    _generation++;
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  Future<void> downloadAndInstall() async {
    if (!hasUpdate || downloading || installing || _disposed) return;
    if (downloadedApk != null && await downloadedApk!.exists()) {
      await installDownloaded();
      return;
    }
    // A recheck may have invalidated the release while checking the local file.
    if (!hasUpdate || downloading || installing || _disposed) return;
    final release = latest!;
    final generation = ++_generation;
    downloading = true;
    received = 0;
    error = null;
    installNotice = null;
    _changed();
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 8);
    _downloadClient = client;
    File? part;
    try {
      final dir = Directory('${(await _cacheRoot()).path}/ai_music_updates');
      await dir.create(recursive: true);
      final destination = File(
        '${dir.path}/${release.code}-${release.sha256Hex.substring(0, 12)}.apk',
      );
      part = File('${destination.path}.part');
      final response = await _openUpdateRequest(
        client,
        release.url,
        normalizeServer(serverUrl),
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final sink = part.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (generation != _generation || _disposed) {
            throw const HttpException('Canceled');
          }
          received += chunk.length;
          if (received > release.size) throw const FormatException('更新包大小不符');
          sink.add(chunk);
          _changed();
        }
      } finally {
        await sink.close();
      }
      final hash = (await sha256.bind(part.openRead()).first).toString();
      if (received != release.size || hash != release.sha256Hex) {
        throw const FormatException('更新包校验失败，请重新下载');
      }
      if (generation != _generation || _disposed) return;
      downloadedApk = await part.rename(destination.path);
      part = null;
      // Only completed, verified packages may reach the Android installer.
    } catch (e) {
      if (generation == _generation) {
        error = e is FormatException ? e.message : '更新包下载失败，请重试';
      }
    } finally {
      client.close(force: true);
      _downloadClient = null;
      if (part != null && await part.exists()) await part.delete();
      downloading = false;
      _changed();
    }
    if (generation == _generation && downloadedApk != null && !_disposed) {
      await installDownloaded();
    }
  }

  Future<void> installDownloaded() async {
    final file = downloadedApk;
    if (file == null || latest == null || installing || !hasUpdate) return;
    installing = true;
    error = null;
    _changed();
    try {
      final opened = await _bridge.install(file, latest!.code);
      installNotice = opened
          ? '请在系统界面确认安装，完成后重新打开应用'
          : '请允许 ${AppBrand.name} 安装应用，返回后点击“安装”';
    } on PlatformException catch (e) {
      error = e.message ?? '无法安装更新包';
    } catch (_) {
      error = '无法安装更新包，请重试';
    } finally {
      installing = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelDownload();
    super.dispose();
  }
}
