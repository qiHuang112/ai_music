import '../data/online_playlists.dart';
import 'screenshot_matcher.dart';
import 'screenshot_song_parser.dart';

class OnlinePlaylistMatch {
  const OnlinePlaylistMatch({this.result, this.serviceFailed = false});
  final ScreenshotMatchResult? result;
  final bool serviceFailed;
}

class OnlinePlaylistImporter {
  const OnlinePlaylistImporter(this.matcher);
  final ScreenshotMatcher matcher;

  Future<void> match(
    List<OnlinePlaylistSong> songs, {
    int concurrency = 3,
    required bool Function() isCanceled,
    required void Function(int index, OnlinePlaylistMatch match) onResult,
  }) async {
    var next = 0;
    var consecutiveErrors = 0;
    var nextOutcome = 0;
    var paused = false;
    final outcomes = List<bool?>.filled(songs.length, null);
    void recordOutcome(int index, bool succeeded) {
      outcomes[index] = succeeded;
      // Completion order is unrelated to adjacency in the source playlist.
      while (nextOutcome < outcomes.length && outcomes[nextOutcome] != null) {
        consecutiveErrors = outcomes[nextOutcome]! ? 0 : consecutiveErrors + 1;
        nextOutcome++;
        if (consecutiveErrors >= 3) {
          paused = true;
          break;
        }
      }
    }

    Future<void> worker() async {
      while (next < songs.length && !isCanceled() && !paused) {
        final index = next++;
        final song = songs[index];
        while (!isCanceled()) {
          final source = matcher.sourceProvider?.call() ?? matcher.source;
          try {
            final result = await matcher.match(
              ScreenshotSongDraft(
                imageId: 'online-playlist',
                row: index + 1,
                title: song.title,
                artist: song.artist,
                durationSeconds: song.durationSeconds,
                version: '',
                rawText: '${song.title} ${song.artist}',
              ),
              failOnSourceErrorWhenEmpty: true,
              source: source,
            );
            if (isCanceled()) return;
            // Source settings may change while this row's network request is
            // pending. Do not persist its stale choice or count its old error;
            // retry this same row with the latest source instead.
            if (source != (matcher.sourceProvider?.call() ?? matcher.source)) {
              continue;
            }
            recordOutcome(index, true);
            onResult(index, OnlinePlaylistMatch(result: result));
          } catch (_) {
            if (isCanceled()) return;
            if (source != (matcher.sourceProvider?.call() ?? matcher.source)) {
              continue;
            }
            recordOutcome(index, false);
            onResult(index, const OnlinePlaylistMatch(serviceFailed: true));
          }
          break;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < songs.length && i < concurrency.clamp(1, 10); i++)
        worker(),
    ]);
  }
}
