import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'resolver_models.dart';
import 'music_source_policy.dart';

const providerBackgroundKey = #providerBackground;
const providerCancellationKey = #providerCancellation;
const providerAutomaticKey = #providerAutomatic;

Future<T> runBackgroundProviderWork<T>(Future<T> Function() action) =>
    runZoned(action, zoneValues: {providerBackgroundKey: true});

class ProviderRateLimitException implements Exception {
  const ProviderRateLimitException(this.retryAt);
  final DateTime retryAt;
  @override
  String toString() => 'HTTP 429：音源请求过于频繁，请稍后重试';
}

/// Providers opt into independent lanes through the shared source catalog.
/// Unconfigured hosts pass through; foreground work precedes background work.
class ProviderRequestScheduler {
  ProviderRequestScheduler({
    this.catalog = MusicSourceCatalog.standard,
    this.spacing,
    this.sourceSpacing = const {},
    this.cooldown,
    this.maxConcurrent,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final shared = ProviderRequestScheduler();
  final MusicSourceCatalog catalog;
  final Duration? spacing;
  final Map<MusicDataSource, Duration> sourceSpacing;
  final Duration? cooldown;
  final int? maxConcurrent;
  final DateTime Function() _now;
  final _lanes = <String, _RequestLane>{};

  void resetForNetworkChange() {
    for (final lane in _lanes.values) {
      lane.generation++;
      lane.retryAt = null;
      _drain(lane);
    }
  }

  Future<ResolverHttpResponse> run(
    Uri uri,
    Future<ResolverHttpResponse> Function() action,
  ) {
    final policy = catalog.policyForHost(uri.host);
    final limits = policy?.requestLimits;
    if (policy == null || limits == null) return action();
    final lane = _lanes.putIfAbsent(
      policy.source.storageValue,
      () => _RequestLane(
        sourceSpacing[policy.source] ?? spacing ?? limits.spacing,
        maxConcurrent ?? limits.maxConcurrent,
        limits.maxBackgroundConcurrent,
        cooldown ?? limits.cooldown,
      ),
    );
    final task = _RequestTask(
      action,
      Zone.current[providerBackgroundKey] == true,
      Zone.current[providerCancellationKey] as bool Function()?,
    );
    lane.pending.add(task);
    _drain(lane);
    return task.done.future;
  }

  void _drain(_RequestLane lane) {
    lane.timer?.cancel();
    lane.timer = null;
    for (final task in lane.pending.toList()) {
      if (task.cancelled?.call() == true) {
        lane.pending.remove(task);
        task.done.completeError(StateError('Source request cancelled'));
      }
    }
    if (lane.retryAt case final retryAt? when retryAt.isAfter(_now())) {
      for (final task in lane.pending) {
        task.done.completeError(ProviderRateLimitException(retryAt));
      }
      lane.pending.clear();
      return;
    }
    if (lane.pending.isEmpty || lane.active >= lane.maxConcurrent) return;
    final foreground = lane.pending
        .where((task) => !task.background)
        .firstOrNull;
    final task =
        foreground ??
        (lane.backgroundActive < lane.maxBackgroundConcurrent
            ? lane.pending.first
            : null);
    if (task == null) return;
    final wait = lane.nextStart?.difference(_now()) ?? Duration.zero;
    if (wait > Duration.zero) {
      lane.timer = Timer(wait, () => _drain(lane));
      return;
    }
    lane.pending.remove(task);
    lane.active++;
    if (task.background) lane.backgroundActive++;
    lane.nextStart = _now().add(lane.spacing);
    final generation = lane.generation;
    unawaited(() async {
      try {
        final response = await task.zone.run(task.action);
        if (_payloadRateLimited(response.body) ||
            response.statusCode == 429 ||
            (response.statusCode == 503 &&
                response.headers.containsKey('retry-after'))) {
          var pause = lane.cooldown;
          final value = response.headers['retry-after'];
          final seconds = int.tryParse(value ?? '');
          if (seconds != null) {
            pause = Duration(seconds: seconds.clamp(1, 120));
          } else if (value != null) {
            try {
              final remaining = HttpDate.parse(value).difference(_now());
              if (remaining > pause) pause = remaining;
            } catch (_) {}
          }
          if (pause > const Duration(minutes: 2)) {
            pause = const Duration(minutes: 2);
          }
          final retryAt = _now().add(pause);
          if (generation == lane.generation) lane.retryAt = retryAt;
          throw ProviderRateLimitException(retryAt);
        }
        task.done.complete(response);
      } catch (error, stack) {
        task.done.completeError(error, stack);
      } finally {
        lane.active--;
        if (task.background) lane.backgroundActive--;
        _drain(lane);
      }
    }());
    _drain(lane);
  }
}

class _RequestLane {
  _RequestLane(
    this.spacing,
    this.maxConcurrent,
    this.maxBackgroundConcurrent,
    this.cooldown,
  );
  final Duration spacing;
  final int maxConcurrent;
  final int maxBackgroundConcurrent;
  final Duration cooldown;
  int active = 0;
  int generation = 0;
  int backgroundActive = 0;
  DateTime? nextStart;
  DateTime? retryAt;
  Timer? timer;
  final pending = <_RequestTask>[];
}

class _RequestTask {
  _RequestTask(this.action, this.background, this.cancelled);
  final Future<ResolverHttpResponse> Function() action;
  final zone = Zone.current;
  final bool background;
  final bool Function()? cancelled;
  final done = Completer<ResolverHttpResponse>();
}

bool _payloadRateLimited(String body) {
  try {
    final payload = jsonDecode(body);
    if (payload is! Map) return false;
    if (payload['code'].toString() == '429') return true;
    final message = (payload['msg'] ?? payload['message'] ?? '')
        .toString()
        .toLowerCase();
    return message.contains('请求过于频繁') ||
        message.contains('too many requests') ||
        message.contains('rate limit');
  } catch (_) {
    return false;
  }
}
