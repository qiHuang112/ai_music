import 'dart:async';
import 'dart:io';

import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/application/download_use_case.dart';
import 'package:ai_music/src/application/music_ui_message.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'download forwards source policy and requested quality to health resolver',
    () async {
      final resolver = _HealthResolver();
      final useCase = _useCase(resolver, _CacheStore());
      await useCase.downloadCandidate(
        _candidate,
        sourceMode: MusicDataSource.auto,
        quality: MusicQualityLevel.medium,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(resolver.modes, [MusicDataSource.auto]);
      expect(resolver.qualities, [MusicQualityLevel.medium]);
      await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(resolver.modes.last, MusicDataSource.buguyy);
      expect(resolver.qualities.last, MusicQualityLevel.high);
    },
  );

  test(
    'resolution failure is not counted a second time as media failure',
    () async {
      final resolver = _HealthResolver()
        ..resolveFailure = const HttpException('HTTP 503');
      final cache = _CacheStore();
      final useCase = _useCase(resolver, cache);
      final result = await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(result.failure, same(resolver.resolveFailure));
      expect(cache.calls, 0);
      expect(resolver.failures, isEmpty);
      expect(resolver.successes, isEmpty);
    },
  );

  test(
    'audio download failure is reported once against its resolved source',
    () async {
      const error = HttpException('download HTTP 503');
      final resolver = _HealthResolver();
      final useCase = _useCase(resolver, _CacheStore()..failure = error);
      final result = await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(result.failure, same(error));
      expect(resolver.failures, [(MusicDataSource.flac, error)]);
      expect(resolver.successes, isEmpty);
    },
  );

  for (final completesSuccessfully in [true, false]) {
    test(
      'cancelled download ignores late ${completesSuccessfully ? 'success' : 'network failure'}',
      () async {
        final resolver = _HealthResolver();
        final gate = Completer<void>();
        final cache = _CacheStore()
          ..gate = gate
          ..failure = completesSuccessfully
              ? null
              : const HttpException('HTTP 503');
        final queue = DownloadQueueController();
        final useCase = _useCase(resolver, cache, queue: queue);
        final pending = useCase.downloadCandidate(
          _candidate,
          onStatus: (_) {},
          onChanged: () {},
        );
        await cache.started.future;
        useCase.cancelDownload(queue.taskIdForCandidate(_candidate));
        gate.complete();
        final result = await pending;
        expect(result.statusMessage?.code, MusicUiMessageCode.downloadCanceled);
        expect(result.failure, isNull);
        expect(resolver.failures, isEmpty);
        expect(resolver.successes, isEmpty);
        expect(queue.recentTasks.single.status, DownloadTaskStatus.canceled);
      },
    );
  }

  test(
    'download cancellation exception is not reported as provider failure',
    () async {
      final resolver = _HealthResolver();
      final useCase = _useCase(
        resolver,
        _CacheStore()..failure = const DownloadCancelledException(),
      );
      final result = await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(result.statusMessage?.code, MusicUiMessageCode.downloadCanceled);
      expect(resolver.failures, isEmpty);
    },
  );

  test(
    'only completed network download resets media failures, not local reuse',
    () async {
      final resolver = _HealthResolver();
      final cache = _CacheStore();
      final useCase = _useCase(resolver, cache);
      await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(resolver.successes, [MusicDataSource.flac]);
      cache.fromCache = true;
      await useCase.downloadCandidate(
        _candidate,
        onStatus: (_) {},
        onChanged: () {},
      );
      expect(resolver.successes, [MusicDataSource.flac]);
      expect(resolver.failures, isEmpty);
    },
  );
}

DownloadUseCase _useCase(
  _HealthResolver resolver,
  _CacheStore cache, {
  DownloadQueueController? queue,
}) => DownloadUseCase(
  resolver: resolver,
  cacheStore: cache,
  queue: queue ?? DownloadQueueController(),
);

const _candidate = MusicSearchCandidate(
  query: 'Song',
  source: MusicDataSource.buguyy,
  platform: 'buguyy',
  keyword: 'Song',
  page: 1,
  id: 'song',
  name: 'Song',
  artist: 'Artist',
  album: '',
  duration: 200,
  link: '',
  coverUrl: '',
  qualities: [MusicQuality(format: 'mp3')],
  score: 100,
  raw: {},
);

const _resolved = ResolvedMusic(
  query: 'Song',
  source: MusicDataSource.flac,
  platform: 'kuwo',
  id: 'song-flac',
  name: 'Song',
  artist: 'Artist',
  album: '',
  url: 'https://example.test/song.mp3',
  quality: MusicQuality(format: 'mp3'),
);

class _HealthResolver implements MusicResolver, AutoSourceHealthResolver {
  Object? resolveFailure;
  final modes = <MusicDataSource>[];
  final qualities = <MusicQualityLevel?>[];
  final failures = <(MusicDataSource, Object)>[];
  final successes = <MusicDataSource>[];

  @override
  Future<ResolvedMusic> resolveForSourceMode(
    MusicSearchCandidate candidate,
    MusicDataSource mode, {
    MusicQualityLevel? quality,
  }) async {
    modes.add(mode);
    qualities.add(quality);
    if (resolveFailure != null) throw resolveFailure!;
    return _resolved;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async =>
      throw StateError('Expected policy-aware resolution');

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => [];

  @override
  List<MusicDataSource> get availableAutoSources => [
    MusicDataSource.flac,
    MusicDataSource.buguyy,
  ];

  @override
  bool isSourceAvailableForAuto(MusicDataSource source) => true;

  @override
  String? sourceDegradationReason(MusicDataSource source) => null;

  @override
  void reportSourceFailure(MusicDataSource source, Object error) =>
      failures.add((source, error));

  @override
  void reportSourceSuccess(MusicDataSource source) => successes.add(source);
}

class _CacheStore extends CachedTrackStore {
  Object? failure;
  bool fromCache = false;
  int calls = 0;
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<CachedTrack> downloadOrReuse(
    ResolvedMusic result, {
    void Function(CachedDownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (failure != null) throw failure!;
    return CachedTrack(
      cacheId: 'song-cache',
      music: result,
      filePath: '/tmp/song.mp3',
      sizeBytes: 4096,
      fromCache: fromCache,
    );
  }
}
