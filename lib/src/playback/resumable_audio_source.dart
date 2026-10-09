// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import '../data/music_cache.dart';

/// Serves remote bytes immediately while keeping one contiguous prefix on disk.
/// A later source with a refreshed URL can continue from the prefix via Range.
class ResumableAudioSource extends StreamAudioSource {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  ResumableAudioSource({
    required this.url,
    required this.partFile,
    required this.completeFile,
    required this.onComplete,
    required this.onStopped,
    required this.onStarted,
    this.onLength,
    this.onProgress,
    this.onFailure,
    this.onSuccess,
    required super.tag,
  });

  final Uri url;
  final File partFile;
  final File completeFile;
  final Future<void> Function(File file) onComplete;
  final void Function() onStopped;
  final void Function() onStarted;
  final Future<void> Function(int? total)? onLength;
  final void Function(CachedDownloadProgress progress)? onProgress;
  final void Function(Object error)? onFailure;
  final void Function()? onSuccess;
  bool _writing = false;
  final _clients = <HttpClient>{};
  final _cancelledClients = <HttpClient>{};
  Future<void>? _finishing;

  void cancelRequests() {
    for (final client in _clients.toList()) {
      _cancelledClients.add(client);
      client.close(force: true);
    }
  }

  Future<void> waitForCache() async => await _finishing;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (await completeFile.exists()) {
      final size = await completeFile.length();
      return _fileResponse(completeFile, size, start, end);
    }
    final prefix = await partFile.exists() ? await partFile.length() : 0;
    final from = max(0, start ?? 0);
    if (end != null && end <= prefix) {
      return _fileResponse(partFile, prefix, start, end);
    }

    onStarted();

    final requestedOffset = from <= prefix ? prefix : from;
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);
    _clients.add(client);
    HttpClientResponse response;
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=$requestedOffset-${end == null ? '' : end - 1}',
      );
      response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Audio returned ${response.statusCode}', uri: url);
      }
      final type = response.headers.contentType?.mimeType ?? '';
      if (type == 'text/html' ||
          type == 'application/json' ||
          type == 'text/plain') {
        throw HttpException('Audio source returned $type', uri: url);
      }
    } catch (error) {
      if (!_cancelledClients.contains(client)) onFailure?.call(error);
      client.close(force: true);
      _clients.remove(client);
      _cancelledClients.remove(client);
      onStopped();
      rethrow;
    }

    final ranged = response.statusCode == HttpStatus.partialContent;
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    final parsed = range == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(range);
    if (ranged && parsed == null) {
      final error = HttpException(
        'Audio returned an invalid byte range',
        uri: url,
      );
      if (!_cancelledClients.contains(client)) onFailure?.call(error);
      client.close(force: true);
      _clients.remove(client);
      _cancelledClients.remove(client);
      onStopped();
      throw error;
    }
    final actualOffset = ranged
        ? int.tryParse(parsed?.group(1) ?? '') ?? requestedOffset
        : 0;
    if (ranged && actualOffset != requestedOffset) {
      final error = HttpException(
        'Audio returned an unexpected byte range',
        uri: url,
      );
      if (!_cancelledClients.contains(client)) onFailure?.call(error);
      client.close(force: true);
      _clients.remove(client);
      _cancelledClients.remove(client);
      onStopped();
      throw error;
    }
    final total = ranged
        ? int.tryParse(parsed?.group(3) ?? '')
        : response.contentLength < 0
        ? null
        : response.contentLength;
    final effectiveFrom = ranged ? from : 0;
    final cachedEnd = ranged ? min(prefix, actualOffset) : 0;
    final write =
        !_writing && (ranged ? actualOffset == prefix : effectiveFrom == 0);
    if (write) _writing = true;
    final remoteType = response.headers.contentType?.mimeType ?? '';
    final contentType =
        remoteType.isEmpty ||
            remoteType == 'application/octet-stream' ||
            remoteType == 'binary/octet-stream'
        ? _contentType(completeFile.path)
        : remoteType;

    Stream<List<int>> bytes() async* {
      RandomAccessFile? writer;
      var received = 0;
      var finished = false;
      try {
        if (write) {
          await partFile.parent.create(recursive: true);
          if (!ranged) await partFile.writeAsBytes(const []);
          writer = await partFile.open(mode: FileMode.append);
          try {
            await onLength?.call(total);
          } catch (_) {
            /* Progress persistence must not stop audio. */
          }
          onProgress?.call(
            CachedDownloadProgress(
              bytes: ranged ? prefix : 0,
              totalBytes: total,
            ),
          );
        }
        if (cachedEnd > effectiveFrom) {
          yield* partFile.openRead(effectiveFrom, cachedEnd);
        }
        final network = response
            .timeout(const Duration(seconds: 20))
            .handleError((Object error, StackTrace stack) {
              if (!_cancelledClients.contains(client)) onFailure?.call(error);
              Error.throwWithStackTrace(error, stack);
            });
        await for (final chunk in network) {
          final remaining = end == null
              ? chunk.length
              : max(0, end - (actualOffset + received));
          final usable = min(chunk.length, remaining);
          if (usable == 0) break;
          final bytes = usable == chunk.length
              ? chunk
              : chunk.sublist(0, usable);
          if (writer != null) await writer.writeFrom(bytes);
          received += usable;
          if (writer != null) {
            onProgress?.call(
              CachedDownloadProgress(
                bytes: actualOffset + received,
                totalBytes: total,
              ),
            );
          }
          yield bytes;
          if (usable < chunk.length) break;
        }
        if (writer != null) {
          await writer.flush();
          final written = await partFile.length();
          final endedAt = actualOffset + received;
          finished = total == null
              ? !ranged && end == null && written == endedAt
              : written == total && written == endedAt;
        }
      } finally {
        await writer?.close();
        client.close(force: true);
        _clients.remove(client);
        final cancelled = _cancelledClients.remove(client);
        if (write) _writing = false;
        if (finished) {
          if (!cancelled) onSuccess?.call();
          try {
            await partFile.rename(completeFile.path);
            _finishing = onComplete(completeFile);
            unawaited(_finishing!.catchError((Object _) {}));
          } catch (_) {
            onStopped();
          }
        } else {
          onStopped();
        }
      }
    }

    return StreamAudioResponse(
      rangeRequestsSupported: ranged,
      sourceLength: total,
      contentLength: total == null
          ? null
          : end == null
          ? total - effectiveFrom
          : min(end, total) - effectiveFrom,
      offset: effectiveFrom,
      stream: bytes(),
      contentType: contentType,
    );
  }

  StreamAudioResponse _fileResponse(File file, int size, int? start, int? end) {
    final from = (start ?? 0).clamp(0, size);
    final to = (end ?? size).clamp(from, size);
    return StreamAudioResponse(
      sourceLength: size,
      contentLength: to - from,
      offset: from,
      stream: file.openRead(from, to),
      contentType: _contentType(file.path),
    );
  }
}

String _contentType(String path) {
  final lower = path.toLowerCase().replaceFirst(RegExp(r'\.part$'), '');
  if (lower.endsWith('.flac')) return 'audio/flac';
  if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'audio/mp4';
  if (lower.endsWith('.aac')) return 'audio/aac';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  return 'audio/mpeg';
}

/// Defers URL resolution until the player asks for audio for this queue item.
class DeferredStreamingAudioSource extends StreamAudioSource {
  DeferredStreamingAudioSource({
    required this.prepare,
    this.preparationRevision,
    this.initialSource,
    required super.tag,
  }) {
    if (initialSource != null) {
      _preparedRevision = preparationRevision?.call();
      _pending = Future.value(initialSource!);
    }
  }
  final Future<StreamAudioSource> Function() prepare;
  final int Function()? preparationRevision;
  final StreamAudioSource? initialSource;
  Future<StreamAudioSource>? _pending;
  int? _preparedRevision;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final revision = preparationRevision?.call();
    if (_preparedRevision != revision) _pending = null;
    _preparedRevision = revision;
    final pending = _pending ??= prepare();
    try {
      final source = await pending;
      if (preparationRevision?.call() != revision) {
        if (identical(_pending, pending)) _pending = null;
        return request(start, end);
      }
      return await source.request(start, end);
    } catch (_) {
      if (identical(_pending, pending)) _pending = null;
      rethrow;
    }
  }
}
