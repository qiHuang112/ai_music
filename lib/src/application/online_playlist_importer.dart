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
        try {
          final result = await matcher.match(
            ScreenshotSongDraft(
              imageId: 'online-playlist',
              row: index + 1,
              title: song.title,
              artist: song.artist,
              version: '',
              rawText: '${song.title} ${song.artist}',
            ),
            failOnSourceErrorWhenEmpty: true,
          );
          if (isCanceled()) return;
          recordOutcome(index, true);
          onResult(index, OnlinePlaylistMatch(result: result));
        } catch (_) {
          if (isCanceled()) return;
          recordOutcome(index, false);
          onResult(index, const OnlinePlaylistMatch(serviceFailed: true));
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < songs.length && i < concurrency.clamp(1, 10); i++)
        worker(),
    ]);
  }
}
