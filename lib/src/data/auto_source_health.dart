import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'buguyy_resolver.dart';
import 'resolver_models.dart';
import 'music_source_policy.dart';
import 'provider_request_scheduler.dart';

enum AutoSourceOperation { search, resolve, media }

/// Lives with the app's resolver, never persisted. Once opened, a circuit stays
/// open until a new app process creates its resolver, including late successes.
class AutoSourceHealth {
  AutoSourceHealth({
    this.failureThreshold = 3,
    this.maxConcurrentPerSource = 2,
    this.catalog = MusicSourceCatalog.standard,
    bool Function(MusicDataSource)? isAuthorized,
  }) : assert(failureThreshold > 0),
       assert(maxConcurrentPerSource > 0),
       _isAuthorized = isAuthorized ?? ((_) => false),
       _states = {
         for (final policy in catalog.policies) policy.source: _SourceState(),
       };

  final int failureThreshold;
  final int maxConcurrentPerSource;
  final MusicSourceCatalog catalog;
  final bool Function(MusicDataSource) _isAuthorized;
  final Map<MusicDataSource, _SourceState> _states;

  MusicSourceAvailability availability(MusicDataSource source) {
    final policy = catalog.policyFor(source);
    if (policy == null) return MusicSourceAvailability.unknown;
    if (!policy.canRequest(authorized: _isAuthorized(source))) {
      return MusicSourceAvailability.authorizationRequired;
    }
    final state = _states[source]!;
    if (state.checking) return MusicSourceAvailability.checking;
    if (state.quotaExhausted) return MusicSourceAvailability.quotaExhausted;
    if (state.lastFailure != null) return MusicSourceAvailability.unavailable;
    return state.succeeded
        ? MusicSourceAvailability.available
        : MusicSourceAvailability.unknown;
  }

  void reset(MusicDataSource source, {bool checking = false}) {
    final state = _states[source];
    if (state == null) return;
    state.generation++;
    state.disabled = false;
    state.reason = null;
    state.lastFailure = null;
    state.quotaExhausted = false;
    state.succeeded = false;
    state.checking = checking;
    state.failures.clear();
    while (state.waiters.isNotEmpty) {
      state.waiters.removeFirst().complete();
    }
  }

  void finishCheck(MusicDataSource source) {
    _states[source]?.checking = false;
  }

  List<MusicDataSource> get availableSources => List.unmodifiable(
    catalog.autoSources(isAuthorized: _isAuthorized).where(isAvailable),
  );

  bool isAvailable(MusicDataSource source) =>
      _states[source] != null &&
      catalog
          .policyFor(source)!
          .canRequest(authorized: _isAuthorized(source)) &&
      !_states[source]!.disabled;

  String? degradationReason(MusicDataSource source) {
    if (_states[source]?.disabled != true) return null;
    return _states[source]!.reason ??
        '${source.label} 连续 $failureThreshold 次请求失败，本次运行已暂停自动请求此来源';
  }

  void recordSuccess(
    MusicDataSource source, {
    AutoSourceOperation operation = AutoSourceOperation.search,
  }) {
    final state = _states[source];
    if (state == null || state.disabled) return;
    state.succeeded = true;
    state.checking = false;
    state.lastFailure = null;
    state.quotaExhausted = false;
    state.failures[operation] = 0;
  }

  void recordFailure(
    MusicDataSource source,
    Object error, {
    AutoSourceOperation operation = AutoSourceOperation.search,
  }) {
    final state = _states[source];
    if (state == null || state.disabled) {
      return;
    }
    if (error is SourceAccessException && error.source == source) {
      state.lastFailure = error;
      state.quotaExhausted = RegExp(
        '限额|额度|quota|allowance|daily limit',
        caseSensitive: false,
      ).hasMatch(error.message);
      state.checking = false;
      state.reason = '$error；本次运行已暂停自动请求此来源';
    } else {
      if (!isSourceServiceFailure(error)) return;
      state.lastFailure = error;
      state.checking = false;
      final failures = (state.failures[operation] ?? 0) + 1;
      state.failures[operation] = failures;
      if (failures < failureThreshold) return;
    }
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
    final generation = state.generation;
    if (!catalog
        .policyFor(source)!
        .canRequest(authorized: _isAuthorized(source))) {
      throw StateError('${source.label}需要授权后才能请求');
    }
    final limit = Zone.current[providerBackgroundKey] == true
        ? catalog
              .policyFor(source)!
              .maxBackgroundOperations
              .clamp(1, maxConcurrentPerSource)
        : maxConcurrentPerSource;
    if (automatic) {
      while (true) {
        if (generation != state.generation) {
          throw StateError('Source request cancelled after network change');
        }
        if (isCancelled?.call() == true) {
          if (state.active < maxConcurrentPerSource &&
              state.waiters.isNotEmpty) {
            state.waiters.removeFirst().complete();
          }
          throw StateError('Source request cancelled');
        }
        if (!isAvailable(source)) {
          throw AutoSourceUnavailableException(
            source,
            degradationReason(source) ?? '${source.label}需要授权后才能请求',
          );
        }
        if (state.active < limit) break;
        final waiter = Completer<void>();
        state.waiters.add(waiter);
        await waiter.future;
      }
      state.active += 1;
    }
    try {
      final result = await runZoned(
        action,
        zoneValues: {providerAutomaticKey: automatic},
      );
      if (isCancelled?.call() != true && generation == state.generation) {
        recordSuccess(source, operation: operation);
      }
      return result;
    } catch (error) {
      if (isCancelled?.call() != true && generation == state.generation) {
        recordFailure(source, error, operation: operation);
      }
      rethrow;
    } finally {
      if (automatic) {
        state.active -= 1;
        while (state.waiters.isNotEmpty) {
          state.waiters.removeFirst().complete();
        }
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
  String? reason;
  int generation = 0;
  bool checking = false;
  bool succeeded = false;
  bool quotaExhausted = false;
  Object? lastFailure;
  final waiters = Queue<Completer<void>>();
}
