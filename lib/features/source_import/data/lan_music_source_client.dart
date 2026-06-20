import 'package:dio/dio.dart';

import '../../library/domain/track.dart';

class LanMusicSourceClient {
  LanMusicSourceClient(this._dio);

  final Dio _dio;

  Future<List<Track>> fetchTracks(Uri manifestUri) async {
    final response = await _dio.getUri<Map<String, Object?>>(manifestUri);
    final data = response.data;
    if (data == null) {
      throw StateError('Music source returned an empty response.');
    }

    final items = data['tracks'] as List<Object?>? ?? const [];
    return items
        .whereType<Map<String, Object?>>()
        .map(
          (item) => Track(
            id: item['id'] as String,
            title: item['title'] as String? ?? 'Untitled',
            artist: item['artist'] as String? ?? 'Unknown',
            album: item['album'] as String? ?? 'Local Music',
            fileName: item['fileName'] as String? ?? 'unknown',
            extension: item['extension'] as String? ?? '',
            size: (item['size'] as num?)?.toInt() ?? 0,
            sourceUrl: item['sourceUrl'] as String,
          ),
        )
        .toList(growable: false);
  }
}
