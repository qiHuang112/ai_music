import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/app_storage.dart';

/// Local rolling operation history. Logging never blocks a user operation.
class OperationLog {
  OperationLog({
    Future<Directory> Function()? rootProvider,
    this.maxFileBytes = 2 * 1024 * 1024,
  }) : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;
  static OperationLog? instance;
  static void event(
    String operation, [
    Map<String, Object?> details = const {},
  ]) => instance?.record(operation, details);
  final Future<Directory> Function() _rootProvider;
  final int maxFileBytes;
  final String session = DateTime.now().microsecondsSinceEpoch.toString();
  Future<void> _tail = Future.value();
  Object? _writeError;

  static Object? redact(Object? value, [String key = '']) {
    if (RegExp(
      'cookie|token|secret|password|authorization|credential|headers|proxy',
      caseSensitive: false,
    ).hasMatch(key)) {
      return '[redacted]';
    }
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key.toString(): redact(e.value, e.key.toString()),
      };
    }
    if (value is List) return value.take(50).map((v) => redact(v)).toList();
    if (value is String) {
      var text = value
          .replaceAllMapped(RegExp(r'https?://[^\s"<>]+'), (m) {
            final uri = Uri.tryParse(m[0]!);
            return uri == null
                ? '[url]'
                : '${uri.scheme}://${uri.host}/[redacted]';
          })
          .replaceAll(
            RegExp(r'(?:Bearer|Basic)\s+\S+', caseSensitive: false),
            '[redacted]',
          );
      if (text.length > 4096) text = '${text.substring(0, 4096)}…';
      return text;
    }
    if (value == null || value is num || value is bool) return value;
    return redact(value.toString(), key);
  }

  void record(String operation, [Map<String, Object?> details = const {}]) {
    final entry = {
      'at': DateTime.now().toIso8601String(),
      'session': session,
      'operation': operation,
      'details': redact(details),
    };
    _tail = _tail
        .then((_) async {
          final dir = Directory(
            '${(await _rootProvider()).path}/operation_logs',
          );
          await dir.create(recursive: true);
          final file = File('${dir.path}/operations.jsonl');
          if (await file.exists() && await file.length() >= maxFileBytes) {
            final oldest = File('${dir.path}/operations.2.jsonl');
            if (await oldest.exists()) await oldest.delete();
            final previous = File('${dir.path}/operations.1.jsonl');
            if (await previous.exists()) await previous.rename(oldest.path);
            await file.rename(previous.path);
          }
          await file.writeAsString(
            '${jsonEncode(entry)}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object e) {
          _writeError = e;
        });
  }

  Future<void> flush() => _tail;

  Future<List<Object?>> export() {
    final result = Completer<List<Object?>>();
    _tail = _tail.then((_) async {
      try {
        if (_writeError != null) throw StateError('操作日志写入失败');
        final dir = Directory('${(await _rootProvider()).path}/operation_logs');
        final entries = <Object?>[];
        for (final name in [
          'operations.2.jsonl',
          'operations.1.jsonl',
          'operations.jsonl',
        ]) {
          final file = File('${dir.path}/$name');
          if (await file.exists()) {
            for (final line in await file.readAsLines()) {
              if (line.isNotEmpty) entries.add(jsonDecode(line));
            }
          }
        }
        result.complete(entries);
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }
}
