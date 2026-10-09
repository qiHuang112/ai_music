import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'buguyy_resolver.dart';
import 'resolver_models.dart';

enum AutoSourceOperation { search, resolve, media }

/// Lives with the app's resolver, never persisted. Once opened, a circuit stays
/// open until a new app process creates its resolver, including late successes.
class AutoSourceHealth {
  AutoSourceHealth({this.failureThreshold = 3, this.maxConcurrentPerSource = 2})
    : assert(failureThreshold > 0),
      assert(maxConcurrentPerSource > 0);

  final int failureThreshold;
  final int maxConcurrentPerSource;
  final _states = <MusicDataSource, _SourceState>{
    MusicDataSource.flac: _SourceState(),
    MusicDataSource.buguyy: _SourceState(),
  };

  List<MusicDataSource> get availableSources =>
      List.unmodifiable(_states.keys.where(isAvailable));

  bool isAvailable(MusicDataSource source) =>
      _states[source] != null && !_states[source]!.disabled;

  String? degradationReason(MusicDataSource source) {
    if (_states[source]?.disabled != true) return null;
    return '${source.label} 连续 $failureThreshold 次请求失败，本次运行已暂停自动请求此来源';
  }

  void recordSuccess(
    MusicDataSource source, {
    AutoSourceOperation operation = AutoSourceOperation.search,
  }) {
    final state = _states[source];
    if (state == null || state.disabled) return;
    state.failures[operation] = 0;
  }

  void recordFailure(
    MusicDataSource source,
    Object error, {
    AutoSourceOperation operation = AutoSourceOperation.search,
  }) {
    final state = _states[source];
    if (state == null || state.disabled || !isSourceServiceFailure(error)) {
      return;
    }
    final failures = (state.failures[operation] ?? 0) + 1;
    state.failures[operation] = failures;
    if (failures < failureThreshold) return;
    state.disabled = true;
    // Wake queued work so it can fail over immediately without waiting for the
    // last outstanding request to finish its network timeout.
    while (state.waiters.isNotEmpty) {
      state.waiters.removeFirst().complete();
    }
  }

  Future<T> run<T>(
    MusicDataSource source,
    Future<T> Function() action, {
    required bool automatic,
    bool Function()? isCancelled,
    AutoSourceOperation operation = AutoSourceOperation.search,
  }) async {
    final state = _states[source];
    if (state == null) throw ArgumentError.value(source, 'source');
    if (automatic) {
      while (true) {
        if (isCancelled?.call() == true) {
          if (state.active < maxConcurrentPerSource &&
              state.waiters.isNotEmpty) {
            state.waiters.removeFirst().complete();
          }
          throw StateError('Source request cancelled');
        }
        if (state.disabled) {
          throw AutoSourceUnavailableException(
            source,
            degradationReason(source)!,
          );
        }
        if (state.active < maxConcurrentPerSource) break;
        final waiter = Completer<void>();
        state.waiters.add(waiter);
        await waiter.future;
      }
      state.active += 1;
    }
    try {
      final result = await action();
      if (isCancelled?.call() != true) {
        recordSuccess(source, operation: operation);
      }
      return result;
    } catch (error) {
      if (isCancelled?.call() != true) {
        recordFailure(source, error, operation: operation);
      }
      rethrow;
    } finally {
      if (automatic) {
        state.active -= 1;
        if (state.waiters.isNotEmpty) state.waiters.removeFirst().complete();
      }
    }
  }
}

/// Missing tracks, unsupported formats and cancellation are not evidence of an
/// unavailable provider. Count transport/protocol/server failures only.
bool isSourceServiceFailure(Object error) {
  if (error is AutoSourceUnavailableException ||
      error is UnsupportedEncryptedAudioException) {
    return false;
  }
  final message = error.toString().toLowerCase();
  if (message.contains('cancel') || message.contains('取消')) return false;
  if (error is BuguyyConnectionException ||
      error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException) {
    return true;
  }
  final httpStatus = RegExp(
    r'\b(?:http|status(?:code)?|returned)\s*[:=]?\s*(\d{3})\b',
  ).firstMatch(message);
  if (httpStatus != null) {
    final code = int.parse(httpStatus.group(1)!);
    return code == 401 ||
        code == 403 ||
        code == 408 ||
        code == 429 ||
        code >= 500;
  }
  if (error is HttpException) return true;
  return message.contains('non-json response') ||
      message.contains('safeline verify failed') ||
      message.contains('connection reset') ||
      message.contains('connection closed') ||
      message.contains('network error') ||
      message.contains('timed out') ||
      message.contains('timeout') ||
      message.contains('服务不可用') ||
      message.contains('请求过于频繁');
}

class _SourceState {
  final failures = <AutoSourceOperation, int>{};
  int active = 0;
  bool disabled = false;
  final waiters = Queue<Completer<void>>();
}
