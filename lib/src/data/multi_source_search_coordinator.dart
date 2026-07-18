import 'dart:async';

import 'resolver_models.dart';
import 'resolver_utils.dart';

typedef SourcePageSearch =
    Stream<MusicSearchProgress> Function(String query, {required int page});
typedef MultiSourceSearchLogger = void Function(String message);

final class MultiSourceSearchProvider {
  const MultiSourceSearchProvider({
    required this.source,
    required this.searchPage,
  });

  final MusicDataSource source;
  final SourcePageSearch searchPage;
}

final class MultiSourceSearchFailure implements Exception {
  const MultiSourceSearchFailure(this.errors);

  final Map<MusicDataSource, Object> errors;

  @override
  String toString() => errors.entries
      .map((entry) => '${entry.key.storageValue}: ${entry.value}')
      .join('; ');
}

final class MultiSourceSearchCoordinator {
  MultiSourceSearchCoordinator({
    required List<MultiSourceSearchProvider> providers,
    DateTime Function()? now,
    MultiSourceSearchLogger? logger,
    this.circuitDuration = const Duration(minutes: 2),
  }) : _providers = List.unmodifiable(providers),
       _now = now ?? DateTime.now,
       _logger = logger;

  final List<MultiSourceSearchProvider> _providers;
  final DateTime Function() _now;
  final MultiSourceSearchLogger? _logger;
  final Duration circuitDuration;
  final Map<MusicDataSource, DateTime> _retryAfter = {};
  final Map<MusicDataSource, bool> _hasNext = {};
  final Set<String> _seen = {};
  String _query = '';
  int _generation = 0;

  Stream<MusicSearchProgress> searchPage(
    String query, {
    required int page,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty || page < 1) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page < 1 ? 1 : page,
      );
      return;
    }

    if (_query != trimmed || page == 1) {
      _query = trimmed;
      _generation += 1;
      _seen.clear();
      _hasNext
        ..clear()
        ..addEntries(
          _providers.map((provider) => MapEntry(provider.source, true)),
        );
    }
    final generation = _generation;

    final active = <MultiSourceSearchProvider>[];
    for (final provider in _providers) {
      final retryAfter = _retryAfter[provider.source];
      final circuitOpen = retryAfter != null && _now().isBefore(retryAfter);
      if (circuitOpen) {
        _logger?.call(
          '[AI Music][resolver] ${provider.source.storageValue} '
          'circuit-skip retryAfter=${retryAfter.toIso8601String()}',
        );
        _hasNext[provider.source] = false;
        continue;
      }
      if (page == 1 || _hasNext[provider.source] != false) {
        active.add(provider);
      }
    }
    if (active.isEmpty) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        hasNextPage: _hasNext.values.any((value) => value),
      );
      return;
    }

    final events = StreamController<_ProviderEvent>();
    final subscriptions = <StreamSubscription<MusicSearchProgress>>[];
    final completed = <MusicDataSource>{};
    final errors = <MusicDataSource, Object>{};
    final pageCandidates = <MusicSearchCandidate>[];
    var emitted = false;
    var lastEmittedCandidateCount = 0;

    for (final provider in active) {
      late final StreamSubscription<MusicSearchProgress> subscription;
      subscription = provider
          .searchPage(trimmed, page: page)
          .listen(
            (progress) {
              if (!events.isClosed) {
                events.add(_ProviderEvent.progress(provider.source, progress));
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!events.isClosed) {
                events.add(_ProviderEvent.error(provider.source, error));
              }
            },
            onDone: () {
              if (!events.isClosed) {
                events.add(_ProviderEvent.done(provider.source));
              }
            },
          );
      subscriptions.add(subscription);
    }

    try {
      await for (final event in events.stream) {
        if (_generation != generation) {
          break;
        }

        if (event.kind == _ProviderEventKind.done) {
          completed.add(event.source);
        } else if (event.kind == _ProviderEventKind.error) {
          final error = event.error!;
          errors[event.source] = error;
          _hasNext[event.source] = false;
          _recordCircuitFailure(event.source, error);
        } else {
          final progress = event.progress!;
          _hasNext[event.source] = progress.hasNextPage;
          final error = progress.error;
          if (error != null) {
            errors[event.source] = error;
            _hasNext[event.source] = false;
            _recordCircuitFailure(event.source, error);
          } else if (progress.isComplete) {
            _retryAfter.remove(event.source);
          }

          for (final candidate in progress.candidates) {
            if (!candidate.isClientReady) {
              continue;
            }
            if (_seen.add(multiSourceCandidateKey(candidate))) {
              pageCandidates.add(candidate);
            }
          }
        }

        final allComplete = completed.length == active.length;
        final newCandidateCount =
            pageCandidates.length - lastEmittedCandidateCount;
        final shouldEmit =
            allComplete ||
            (pageCandidates.length >= 2 &&
                (!emitted || newCandidateCount >= 2));
        if (shouldEmit) {
          emitted = true;
          lastEmittedCandidateCount = pageCandidates.length;
          yield MusicSearchProgress(
            candidates: List.unmodifiable(pageCandidates),
            isComplete: allComplete,
            page: page,
            hasNextPage: _hasNext.values.any((value) => value),
            error:
                allComplete &&
                    pageCandidates.isEmpty &&
                    errors.length == active.length
                ? MultiSourceSearchFailure(Map.unmodifiable(errors))
                : null,
          );
        }
        if (allComplete) {
          break;
        }
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      if (!events.isClosed) {
        await events.close();
      }
    }

    if (!emitted && _generation == generation) {
      yield MusicSearchProgress(
        candidates: const [],
        isComplete: true,
        page: page,
        hasNextPage: _hasNext.values.any((value) => value),
      );
    }
  }

  void _recordCircuitFailure(MusicDataSource source, Object error) {
    final failureCode = error is SourceDownloadException
        ? error.failureCode
        : error.runtimeType.toString();
    _logger?.call(
      '[AI Music][resolver] ${source.storageValue} '
      'failure code=$failureCode error=$error',
    );
    if (_opensCircuit(error)) {
      final retryAfter = _now().add(circuitDuration);
      _retryAfter[source] = retryAfter;
      _logger?.call(
        '[AI Music][resolver] ${source.storageValue} '
        'circuit-open retryAfter=${retryAfter.toIso8601String()}',
      );
    }
  }
}

enum _ProviderEventKind { progress, error, done }

final class _ProviderEvent {
  const _ProviderEvent.progress(this.source, this.progress)
    : kind = _ProviderEventKind.progress,
      error = null;

  const _ProviderEvent.error(this.source, this.error)
    : kind = _ProviderEventKind.error,
      progress = null;

  const _ProviderEvent.done(this.source)
    : kind = _ProviderEventKind.done,
      progress = null,
      error = null;

  final MusicDataSource source;
  final _ProviderEventKind kind;
  final MusicSearchProgress? progress;
  final Object? error;
}

bool _opensCircuit(Object error) {
  return isSourceCircuitBreakerError(error);
}

String multiSourceCandidateKey(MusicSearchCandidate candidate) {
  final title = _normalizeIdentityText(candidate.name);
  final artist = _normalizeIdentityText(candidate.artist);
  final fallback = title.isEmpty
      ? _normalizeIdentityText(candidate.keyword)
      : title;
  if (fallback.isEmpty && artist.isEmpty) {
    return '${candidate.source.storageValue}\u0000${candidate.id}';
  }
  return '$fallback\u0000$artist';
}

String _normalizeIdentityText(String value) {
  final decoded = value.replaceAllMapped(
    RegExp(r'\\+u([0-9a-fA-F]{4})'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
  return decoded
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\u00a0&＆/,，、·•・]+'), '')
      .trim();
}
