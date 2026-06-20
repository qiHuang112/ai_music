import 'package:dio/dio.dart';

import '../../../core/errors/music_app_exception.dart';
import '../../library/domain/track.dart';

class LanMusicSourceClient {
  LanMusicSourceClient(this._dio);

  final Dio _dio;

  Future<List<Track>> fetchTracks(Uri manifestUri) async {
    final Response<Map<String, Object?>> response;
    try {
      response = await _dio.getUri<Map<String, Object?>>(manifestUri);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_asMusicAppException(error), stackTrace);
    }
    final data = response.data;
    if (data == null) {
      throw const MusicAppException(
        MusicAppFailureKind.badResponse,
        '本地音源服务返回了空曲库数据。',
      );
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

  MusicAppException _asMusicAppException(Object error) {
    if (error is MusicAppException) {
      return error;
    }
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout => const MusicAppException(
          MusicAppFailureKind.connectionTimeout,
          '连接本地音源超时，请确认手机和电脑在同一局域网。',
        ),
        DioExceptionType.receiveTimeout => const MusicAppException(
          MusicAppFailureKind.receiveTimeout,
          '获取曲库超时，请确认本地音源服务仍在运行后重试。',
        ),
        DioExceptionType.sendTimeout => const MusicAppException(
          MusicAppFailureKind.sendTimeout,
          '请求本地音源超时，请稍后重试。',
        ),
        DioExceptionType.connectionError => const MusicAppException(
          MusicAppFailureKind.connectionFailed,
          '无法连接本地音源服务，请确认 8787 服务正在运行。',
        ),
        DioExceptionType.badResponse => MusicAppException(
          MusicAppFailureKind.badResponse,
          '本地音源服务返回异常：HTTP ${error.response?.statusCode ?? 'unknown'}。',
          statusCode: error.response?.statusCode,
        ),
        DioExceptionType.cancel => const MusicAppException(
          MusicAppFailureKind.cancelled,
          '请求已取消。',
        ),
        DioExceptionType.badCertificate => const MusicAppException(
          MusicAppFailureKind.badCertificate,
          '本地音源证书异常。',
        ),
        DioExceptionType.unknown => const MusicAppException(
          MusicAppFailureKind.unknown,
          '本地音源请求失败，请稍后重试。',
        ),
      };
    }
    return MusicAppException(MusicAppFailureKind.unknown, error.toString());
  }
}
