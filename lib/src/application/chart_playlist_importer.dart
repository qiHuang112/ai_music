import '../data/music_charts.dart';
import '../data/music_resolver.dart';
import 'screenshot_matcher.dart';
import 'screenshot_song_parser.dart';

class ChartImportResult {
  const ChartImportResult({
    required this.candidates,
    required this.failed,
    required this.unprocessed,
    this.serviceError,
    this.canceled = false,
  });

  final List<MusicSearchCandidate> candidates;

  /// Selected rows with no trustworthy title-and-artist match.
  final int failed;
  final int unprocessed;
  final Object? serviceError;
  final bool canceled;
}

/// Reuses screenshot matching while keeping the chart's ranking order.
class ChartPlaylistImporter {
  const ChartPlaylistImporter(this.matcher);

  final ScreenshotMatcher matcher;

  Future<ChartImportResult> match(
    List<MusicChartEntry> entries, {
    int concurrency = 3,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    final matches = List<MusicSearchCandidate?>.filled(entries.length, null);
    var next = 0;
    var completed = 0;
    var unmatched = 0;
    Object? serviceError;

    bool canceled() => isCanceled?.call() ?? false;

    Future<void> worker() async {
      while (next < entries.length && serviceError == null && !canceled()) {
        final index = next++;
        final entry = entries[index];
        try {
          final result = await matcher.match(
            ScreenshotSongDraft(
              imageId: 'chart',
              row: entry.rank,
              title: entry.title,
              artist: entry.artist,
              version: '',
              rawText: '${entry.title} ${entry.artist}',
            ),
            failOnSourceErrorWhenEmpty: true,
          );
          if (canceled()) continue;
          for (final candidate in result.candidates) {
            if (_trustworthyMatch(entry, candidate)) {
              matches[index] = candidate;
              break;
            }
          }
          if (matches[index] == null) unmatched += 1;
        } catch (error) {
          serviceError ??= error;
        } finally {
          completed += 1;
          onProgress?.call(completed, entries.length);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < entries.length && i < concurrency.clamp(1, 10); i++)
        worker(),
    ]);
    final candidates = [for (final match in matches) ?match];
    return ChartImportResult(
      candidates: candidates,
      failed: unmatched,
      unprocessed: entries.length - completed,
      serviceError: serviceError,
      canceled: canceled(),
    );
  }
}

bool _trustworthyMatch(MusicChartEntry entry, MusicSearchCandidate candidate) {
  final chartTitle = _normalized(entry.title);
  final candidateTitle = _normalized(candidate.name);
  if (chartTitle.isEmpty || chartTitle != candidateTitle) return false;

  final chartArtists = _artists(entry.artist);
  final candidateArtists = _artists(candidate.artist);
  if (chartArtists.isEmpty || candidateArtists.isEmpty) return false;
  if (chartArtists.length != candidateArtists.length) return false;
  for (var i = 0; i < chartArtists.length; i += 1) {
    if (chartArtists[i] != candidateArtists[i]) return false;
  }
  return true;
}

String _normalized(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]', unicode: true),
  '',
);

List<String> _artists(String value) {
  final separated = value.replaceAll(
    RegExp(r'\s+(?:feat\.?|ft\.?)\s+', caseSensitive: false),
    '/',
  );
  return separated
      .split(RegExp(r'[/／、,，&＆]'))
      .map(_normalized)
      .where((artist) => artist.isNotEmpty)
      .toList()
    ..sort();
}
