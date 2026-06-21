import 'resolver_models.dart';
import 'resolver_utils.dart';

MusicSearchCandidate candidateFromItem({
  required String query,
  required MusicDataSource source,
  required String platform,
  required String keyword,
  required int page,
  required Map<String, dynamic> item,
  required double score,
}) {
  final qualities = (item['minfo'] is List ? item['minfo'] as List : [])
      .map(MusicQuality.fromJson)
      .where((quality) => quality.format.trim().isNotEmpty)
      .toList(growable: false);
  return MusicSearchCandidate(
    query: query,
    source: source,
    platform: platform,
    keyword: keyword,
    page: page,
    id: item['id']?.toString() ?? '',
    name: item['name']?.toString() ?? '',
    artist: item['artist']?.toString() ?? '',
    album: item['album_name']?.toString() ?? '',
    duration: intFrom(item['duration']),
    link: item['link']?.toString() ?? '',
    coverUrl: item['picurl']?.toString() ?? '',
    qualities: qualities,
    score: score,
    raw: item,
  );
}

Map<String, dynamic> normalizeBuguyySong(Map<String, dynamic> item) {
  return {
    'id': item['id'],
    'name': item['title'] ?? item['name'] ?? '',
    'artist': item['singer'] ?? item['artist'] ?? '',
    'album_name': '',
    'duration': 0,
    'link': '',
    'picurl': item['picurl'] ?? item['cover'] ?? '',
    'about': item['about'] ?? '',
    'minfo': const [
      {'format': 'mp3', 'bitrate': '', 'size': ''},
    ],
    'raw': item,
  };
}
