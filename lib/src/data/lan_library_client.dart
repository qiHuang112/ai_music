import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lan_library_models.dart';

class LanLibraryException implements Exception {
  const LanLibraryException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class LanLibraryHealth {
  const LanLibraryHealth({
    required this.schemaVersion,
    required this.trackCount,
  });

  final int schemaVersion;
  final int trackCount;
}

abstract class LanLibraryGateway {
  Future<LanLibraryHealth> testConnection(String baseUrl);

  Future<LanLibraryManifest> fetchLibrary(String baseUrl);

  Uri resolveAssetUri(String baseUrl, LanAsset asset);

  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target);
}

class LanLibraryClient implements LanLibraryGateway {
  LanLibraryClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient(),
      _ownsClient = httpClient == null;

  final HttpClient _httpClient;
  final bool _ownsClient;

  @override
  Future<LanLibraryHealth> testConnection(String baseUrl) async {
    final baseUri = normalizeLanLibraryBaseUri(baseUrl);
    final decoded = await _getJson(baseUri.resolve('/api/v1/health'));
    final status = decoded['status']?.toString();
    final schema = _nonNegativeInt(decoded['schemaVersion']);
    final count = _nonNegativeInt(decoded['trackCount']);
    if (status != 'ok' || schema != 1 || count == null) {
      throw const LanLibraryException('局域网音乐服务返回了无效的健康状态');
    }
    return LanLibraryHealth(schemaVersion: schema!, trackCount: count);
  }

  @override
  Future<LanLibraryManifest> fetchLibrary(String baseUrl) async {
    final baseUri = normalizeLanLibraryBaseUri(baseUrl);
    final decoded = await _getJson(baseUri.resolve('/api/v1/library'));
    try {
      return LanLibraryManifest.fromJson(decoded);
    } on FormatException catch (error) {
      throw LanLibraryException('局域网音乐清单格式无效：${error.message}', cause: error);
    }
  }

  @override
  Uri resolveAssetUri(String baseUrl, LanAsset asset) {
    final baseUri = normalizeLanLibraryBaseUri(baseUrl);
    final resolved = baseUri.resolveUri(asset.url);
    if (resolved.scheme != baseUri.scheme ||
        resolved.host != baseUri.host ||
        resolved.port != baseUri.port ||
        !resolved.path.startsWith('/api/v1/files/')) {
      throw const LanLibraryException('清单资源地址离开了已配置的局域网服务');
    }
    return resolved;
  }

  @override
  Future<int> downloadAsset(String baseUrl, LanAsset asset, File target) async {
    final uri = resolveAssetUri(baseUrl, asset);
    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LanLibraryException('下载局域网资源失败：HTTP ${response.statusCode}');
      }
      if (response.contentLength > 0 &&
          response.contentLength != asset.sizeBytes) {
        throw const LanLibraryException('局域网资源响应大小与清单不一致');
      }
      final sink = target.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (bytes + chunk.length > asset.sizeBytes) {
            throw const LanLibraryException('局域网资源响应超过清单声明的大小');
          }
          bytes += chunk.length;
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (bytes != asset.sizeBytes) {
        throw const LanLibraryException('局域网资源响应大小与清单不一致');
      }
      return bytes;
    } on LanLibraryException {
      await _deletePartialDownload(target);
      rethrow;
    } on Object catch (error) {
      await _deletePartialDownload(target);
      throw LanLibraryException('下载局域网资源失败：$error', cause: error);
    }
  }

  void close() {
    if (_ownsClient) {
      _httpClient.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LanLibraryException('局域网音乐服务 HTTP ${response.statusCode}');
      }
      if (response.contentLength > _maximumJsonResponseBytes) {
        throw const LanLibraryException('局域网音乐服务返回的 JSON 过大');
      }
      final body = await _readLimitedResponse(
        response,
        _maximumJsonResponseBytes,
      );
      final text = utf8.decode(body);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const LanLibraryException('局域网音乐服务没有返回 JSON 对象');
      }
      return decoded.cast<String, dynamic>();
    } on LanLibraryException {
      rethrow;
    } on FormatException catch (error) {
      throw LanLibraryException('局域网音乐服务返回的 JSON 无效', cause: error);
    } on Object catch (error) {
      throw LanLibraryException('无法连接局域网音乐服务：$error', cause: error);
    }
  }
}

const _maximumJsonResponseBytes = 2 * 1024 * 1024;

Future<List<int>> _readLimitedResponse(
  HttpClientResponse response,
  int maximumBytes,
) async {
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in response.timeout(const Duration(seconds: 30))) {
    length += chunk.length;
    if (length > maximumBytes) {
      throw const LanLibraryException('局域网音乐服务返回的 JSON 过大');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> _deletePartialDownload(File target) async {
  try {
    if (await target.exists()) {
      await target.delete();
    }
  } on FileSystemException {
    // The cache store also performs best-effort temporary-file cleanup.
  }
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed >= 0 ? parsed : null;
}
