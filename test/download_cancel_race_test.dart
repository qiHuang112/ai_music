import 'dart:async';
import 'dart:io';
import 'package:ai_music/src/application/download_queue_controller.dart';
import 'package:ai_music/src/application/download_use_case.dart';
import 'package:ai_music/src/application/music_ui_message.dart';
import 'package:ai_music/src/data/download_history_store.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cancelFirst in [true, false]) {
    test(
      'late resolver error ${cancelFirst ? 'preserves cancellation' : 'remains a genuine failure'} across midnight and history reload',
      () async {
        final root = await Directory.systemTemp.createTemp('cancel-race-');
        addTearDown(() => root.delete(recursive: true));
        final store = DownloadHistoryStore(rootProvider: () async => root);
        final writes = <Future<void>>[];
        var now = DateTime(2026, 9, 27, 23, 59);
        final queue = DownloadQueueController(now: () => now);
        queue.onHistoryChanged = () => writes.add(
          store.write([for (final task in queue.recentTasks) task.toJson()]),
        );
        final resolver = _ControlledResolver();
        final useCase = DownloadUseCase(
          resolver: resolver,
          cacheStore: CachedTrackStore(),
          queue: queue,
        );
        const candidate = MusicSearchCandidate(
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
        final id = queue.taskIdForCandidate(candidate);
        final pending = useCase.downloadCandidate(
          candidate,
          onStatus: (_) {},
          onChanged: () {},
        );
        await resolver.started.future;
        if (cancelFirst) useCase.cancelDownload(id);
        now = DateTime(2026, 9, 28, 0, 1);
        resolver.result.completeError(
          const SocketException('connection closed'),
        );
        final result = await pending;
        final expected = cancelFirst
            ? DownloadTaskStatus.canceled
            : DownloadTaskStatus.failed;
        expect(queue.recentTasks.single.status, expected);
        expect(
          queue.recentTasks.single.finishedAt,
          cancelFirst ? DateTime(2026, 9, 27, 23, 59) : now,
        );
        expect(queue.hasActiveToken(id), false);
        expect(result.cached, isNull);
        if (cancelFirst) {
          expect(
            result.statusMessage?.code,
            MusicUiMessageCode.downloadCanceled,
          );
          expect(result.failure, isNull);
          expect(result.errorDetail, isNull);
          expect(queue.recentTasks.single.error, isEmpty);
        } else {
          expect(result.failure, isA<SocketException>());
          expect(result.errorDetail, contains('connection closed'));
        }
        expect(writes, hasLength(1));
        await Future.wait(writes);
        final restored = DownloadQueueController();
        restored.restoreHistory([
          for (final json in await store.read()) DownloadTask.fromJson(json)!,
        ]);
        expect(restored.recentTasks.single.status, expected);
        expect(
          restored.recentTasks.single.finishedAt,
          queue.recentTasks.single.finishedAt,
        );
        expect(
          restored.recentTasks
              .where((t) => t.status == DownloadTaskStatus.failed)
              .length,
          cancelFirst ? 0 : 1,
        );
        expect(
          restored.recentTasks
              .where((t) => t.status == DownloadTaskStatus.canceled)
              .length,
          cancelFirst ? 1 : 0,
        );
      },
    );
  }
}

class _ControlledResolver implements MusicResolver {
  final started = Completer<void>();
  final result = Completer<ResolvedMusic>();
  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) {
    started.complete();
    return result.future;
  }

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) async => [];
}
