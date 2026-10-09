import 'dart:async';

import 'package:ai_music/src/application/online_playlist_importer.dart';
import 'package:ai_music/src/application/screenshot_matcher.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/online_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final oldFails in [false, true]) {
    test(
      'source switch discards late ${oldFails ? 'error' : 'choice'} and retries before publishing row',
      () async {
        var source = MusicDataSource.buguyy;
        final resolver = _ControlledResolver();
        final importer = _importer(resolver, () => source);
        final saved = <int, OnlinePlaylistMatch>{};
        final work = importer.match(
          _songs(2),
          concurrency: 1,
          isCanceled: () => false,
          onResult: (index, match) => saved[index] = match,
        );
        await resolver.waitForCalls(1);
        expect(resolver.requests.first.source, MusicDataSource.buguyy);
        source = MusicDataSource.flac;
        if (oldFails) {
          resolver.requests.first.result.completeError(
            StateError('old source offline'),
          );
        } else {
          resolver.requests.first.complete();
        }
        await resolver.waitForCalls(2);
        expect(saved, isEmpty);
        expect(resolver.requests[1].query, 'song-0');
        expect(resolver.requests[1].source, MusicDataSource.flac);
        resolver.requests[1].complete();
        await resolver.waitForCalls(3);
        expect(saved.keys, [0]);
        expect(saved[0]!.result!.recommended!.source, MusicDataSource.flac);
        expect(resolver.requests[2].query, 'song-1');
        expect(resolver.requests[2].source, MusicDataSource.flac);
        resolver.requests[2].complete();
        await work;
        expect(saved.keys, [0, 1]);
        expect(saved.values.every((match) => !match.serviceFailed), isTrue);
        expect(
          saved.values.map((match) => match.result!.recommended!.source),
          everyElement(MusicDataSource.flac),
        );
      },
    );
  }

  test(
    'three stale parallel failures do not pause matching on the new source',
    () async {
      var source = MusicDataSource.buguyy;
      final resolver = _ControlledResolver();
      final saved = <int, OnlinePlaylistMatch>{};
      final work = _importer(resolver, () => source).match(
        _songs(6),
        concurrency: 3,
        isCanceled: () => false,
        onResult: (index, match) => saved[index] = match,
      );
      await resolver.waitForCalls(3);
      source = MusicDataSource.flac;
      for (final request in resolver.requests.toList()) {
        request.result.completeError(StateError('old source offline'));
      }
      await resolver.waitForCalls(6);
      expect(saved, isEmpty);
      expect(
        resolver.requests.skip(3).map((request) => request.source),
        everyElement(MusicDataSource.flac),
      );
      for (final request in resolver.requests.skip(3).toList()) {
        request.complete();
      }
      await resolver.waitForCalls(9);
      for (final request in resolver.requests.skip(6).toList()) {
        request.complete();
      }
      await work;
      expect(saved, hasLength(6));
      expect(saved.values.every((match) => !match.serviceFailed), isTrue);
      expect(
        saved.values.map((match) => match.result!.recommended!.source),
        everyElement(MusicDataSource.flac),
      );
    },
  );

  for (final retryStarted in [false, true]) {
    test(
      'cancellation ignores late error ${retryStarted ? 'during new-source retry' : 'before source retry'}',
      () async {
        var source = MusicDataSource.buguyy;
        var canceled = false;
        final resolver = _ControlledResolver();
        final saved = <OnlinePlaylistMatch>[];
        final work = _importer(resolver, () => source).match(
          _songs(2),
          concurrency: 1,
          isCanceled: () => canceled,
          onResult: (_, match) => saved.add(match),
        );
        await resolver.waitForCalls(1);
        source = MusicDataSource.flac;
        if (retryStarted) {
          resolver.requests.first.complete();
          await resolver.waitForCalls(2);
        }
        canceled = true;
        resolver.requests.last.result.completeError(StateError('late offline'));
        await work;
        expect(saved, isEmpty);
        expect(resolver.requests, hasLength(retryStarted ? 2 : 1));
      },
    );
  }
}

OnlinePlaylistImporter _importer(
  _ControlledResolver resolver,
  MusicDataSource Function() source,
) => OnlinePlaylistImporter(
  ScreenshotMatcher(
    resolver: resolver,
    requestStartSpacing: Duration.zero,
    sourceProvider: source,
  ),
);

List<OnlinePlaylistSong> _songs(int count) => [
  for (var i = 0; i < count; i++)
    OnlinePlaylistSong(id: '$i', title: 'song-$i', artist: 'Artist'),
];

class _ControlledResolver implements MusicResolver {
  final requests = <_Request>[];
  Completer<void>? _nextRequest;

  Future<void> waitForCalls(int count) async {
    while (requests.length < count) {
      _nextRequest ??= Completer<void>();
      await _nextRequest!.future.timeout(const Duration(seconds: 1));
    }
  }

  @override
  Future<List<MusicSearchCandidate>> search(
    String query,
    MusicDataSource source,
  ) {
    final request = _Request(query, source);
    requests.add(request);
    _nextRequest?.complete();
    _nextRequest = null;
    return request.result.future;
  }

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) async =>
      throw UnimplementedError();
}

class _Request {
  _Request(this.query, this.source);
  final String query;
  final MusicDataSource source;
  final result = Completer<List<MusicSearchCandidate>>();

  void complete() => result.complete([
    MusicSearchCandidate(
      query: query,
      source: source,
      platform: source.storageValue,
      keyword: query,
      page: 1,
      id: '${source.storageValue}-$query',
      name: query,
      artist: 'Artist',
      album: '',
      duration: 200,
      link: '',
      coverUrl: '',
      qualities: const [MusicQuality(format: 'mp3')],
      score: 100,
      raw: const {},
    ),
  ]);
}
