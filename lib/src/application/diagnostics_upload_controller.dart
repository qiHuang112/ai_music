import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../data/listening_stats_store.dart';
import '../data/operation_log.dart';
import 'app_update_controller.dart';

class DiagnosticsClient {
  DiagnosticsClient({Uri? base, HttpClient Function()? clientFactory})
    : base = base ?? Uri.parse(defaultUpdateUrl),
      _clientFactory = clientFactory ?? HttpClient.new;
  final Uri base;
  final HttpClient Function() _clientFactory;
  Future<Map<String, dynamic>> _request(
    String method, {
    List<int>? bytes,
  }) async {
    final client = _clientFactory();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client
          .openUrl(method, base.resolve('/api/v1/diagnostics'))
          .timeout(const Duration(seconds: 2));
      request.followRedirects = false;
      if (bytes != null) {
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(
        Duration(seconds: method == 'GET' ? 2 : 30),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw HttpException('日志服务 HTTP ${response.statusCode}');
      }
      final data = await response
          .fold<List<int>>([], (all, chunk) {
            if (all.length + chunk.length > 64 * 1024) {
              throw const FormatException('日志服务响应过大');
            }
            return all..addAll(chunk);
          })
          .timeout(const Duration(seconds: 5));
      return (jsonDecode(utf8.decode(data)) as Map).cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> probe() async {
    try {
      final response = await _request('GET');
      return response['service'] == 'ai-music-diagnostics' &&
          response['schemaVersion'] == 1;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> upload(Map<String, Object?> payload) async {
    final bytes = utf8.encode(jsonEncode(payload));
    if (bytes.length > 32 * 1024 * 1024) throw StateError('日志超过服务接收大小');
    final receipt = await _request('POST', bytes: bytes);
    if (receipt['reportId'] != payload['reportId'] ||
        receipt['saved'] != true ||
        receipt['sha256'] != sha256.convert(bytes).toString()) {
      throw StateError('日志服务未确认保存');
    }
    return receipt;
  }
}

class DiagnosticsUploadController extends ChangeNotifier {
  DiagnosticsUploadController({
    required this.stats,
    required this.captureListening,
    required this.version,
    DiagnosticsClient? client,
    OperationLog? operations,
  }) : client = client ?? DiagnosticsClient(),
       operations = operations ?? OperationLog.instance ?? OperationLog();
  final ListeningStatsStore stats;
  final void Function() captureListening;
  final Future<InstalledAppVersion?> Function() version;
  final DiagnosticsClient client;
  final OperationLog operations;
  bool available = false, uploading = false, _disposed = false;
  String? error, reportId;
  int _probeRevision = 0;
  Future<void> probe() async {
    final revision = ++_probeRevision;
    available = false;
    if (!_disposed) notifyListeners();
    final found = await client.probe();
    if (_disposed || revision != _probeRevision) return;
    available = found;
    notifyListeners();
  }

  Future<void> upload() async {
    if (!available || uploading || _disposed) return;
    uploading = true;
    error = null;
    reportId = null;
    notifyListeners();
    try {
      if (!await client.probe()) {
        available = false;
        throw StateError('局域网日志服务不可用');
      }
      captureListening();
      final statsJson = await stats.exportJsonFiles();
      final app = await version();
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      operations.record('diagnostics.upload', {'reportId': id});
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'reportId': id,
        'createdAt': DateTime.now().toIso8601String(),
        'app': {
          'packageName': app?.packageName ?? 'com.qi.ai.music',
          'versionName': app?.name,
          'versionCode': app?.code,
          'channel': app?.channel,
          'os': Platform.operatingSystem,
        },
        'operations': await operations.export(),
        'listeningStats': statsJson,
      };
      await client.upload(payload);
      reportId = id;
      operations.record('diagnostics.upload.saved', {'reportId': id});
    } catch (e) {
      error = '日志上传失败，请确认局域网连接后重试';
      operations.record('diagnostics.upload.failed', {'error': e.toString()});
    } finally {
      uploading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _probeRevision++;
    super.dispose();
  }
}
