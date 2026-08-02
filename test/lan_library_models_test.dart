import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeLanLibraryBaseUri', () {
    test('accepts private and loopback cleartext hosts', () {
      expect(
        normalizeLanLibraryBaseUri('http://192.168.31.57:8787/').toString(),
        'http://192.168.31.57:8787',
      );
      expect(
        normalizeLanLibraryBaseUri('http://127.0.0.1:8787').host,
        '127.0.0.1',
      );
      expect(
        normalizeLanLibraryBaseUri('http://10.20.30.40:8787').host,
        '10.20.30.40',
      );
      expect(
        normalizeLanLibraryBaseUri('http://172.16.4.9:8787').host,
        '172.16.4.9',
      );
      expect(
        normalizeLanLibraryBaseUri('http://localhost:8787').host,
        'localhost',
      );
    });

    test('accepts HTTPS but rejects public cleartext and ambiguous URLs', () {
      expect(
        normalizeLanLibraryBaseUri('https://music.example.test/library').path,
        '/library',
      );
      expect(
        () => normalizeLanLibraryBaseUri('http://8.8.8.8:8787'),
        throwsFormatException,
      );
      expect(
        () => normalizeLanLibraryBaseUri('http://example.com:8787'),
        throwsFormatException,
      );
      expect(
        () => normalizeLanLibraryBaseUri('http://user:secret@192.168.1.2:8787'),
        throwsFormatException,
      );
      expect(
        () => normalizeLanLibraryBaseUri('http://192.168.1.2:8787?root=other'),
        throwsFormatException,
      );
    });
  });

  group('LanLibraryManifest', () {
    test('parses schema version 1 and optional sidecars', () {
      final manifest = LanLibraryManifest.fromJson(_manifestJson());

      expect(manifest.schemaVersion, 1);
      expect(manifest.libraryId, 'library-test');
      expect(manifest.tracks, hasLength(1));
      final track = manifest.tracks.single;
      expect(track.id, 'lamaze-slow-breathing');
      expect(track.title, '慢呼放松');
      expect(track.audio.format, 'mp3');
      expect(track.audio.sizeBytes, 64000);
      expect(track.lyrics?.format, 'lrc');
      expect(track.artwork?.mimeType, 'image/png');
    });

    test('rejects unsupported schema duplicate ids and invalid assets', () {
      expect(
        () =>
            LanLibraryManifest.fromJson(_manifestJson()..['schemaVersion'] = 2),
        throwsFormatException,
      );

      final duplicate = _manifestJson();
      final tracks = duplicate['tracks']! as List<Object?>;
      tracks.add(Map<String, Object?>.from(tracks.single! as Map));
      expect(
        () => LanLibraryManifest.fromJson(duplicate),
        throwsFormatException,
      );

      final badHash = _manifestJson();
      final track = (badHash['tracks']! as List).single as Map;
      (track['audio'] as Map)['sha256'] = 'not-a-sha';
      expect(() => LanLibraryManifest.fromJson(badHash), throwsFormatException);

      final badFormat = _manifestJson();
      final badTrack = (badFormat['tracks']! as List).single as Map;
      (badTrack['audio'] as Map)['format'] = 'wav';
      expect(
        () => LanLibraryManifest.fromJson(badFormat),
        throwsFormatException,
      );

      final traversal = _manifestJson();
      final traversalTrack = (traversal['tracks']! as List).single as Map;
      (traversalTrack['audio'] as Map)['url'] =
          '/api/v1/files/Lamaze/%2e%2e/secret.mp3';
      expect(
        () => LanLibraryManifest.fromJson(traversal),
        throwsFormatException,
      );

      final oversized = _manifestJson();
      final oversizedTrack = (oversized['tracks']! as List).single as Map;
      (oversizedTrack['audio'] as Map)['sizeBytes'] =
          2 * 1024 * 1024 * 1024 + 1;
      expect(
        () => LanLibraryManifest.fromJson(oversized),
        throwsFormatException,
      );
    });
  });
}

Map<String, Object?> _manifestJson() {
  return {
    'schemaVersion': 1,
    'libraryId': 'library-test',
    'generatedAt': '2026-08-02T00:00:00Z',
    'tracks': <Object?>[
      {
        'id': 'lamaze-slow-breathing',
        'title': '慢呼放松',
        'artist': 'AI Home',
        'album': '拉玛泽呼吸引导',
        'audio': {
          'url': '/api/v1/files/Lamaze/01.mp3',
          'sizeBytes': 64000,
          'sha256': 'a' * 64,
          'format': 'mp3',
        },
        'lyrics': {
          'url': '/api/v1/files/Lamaze/01.lrc',
          'sizeBytes': 1200,
          'sha256': 'b' * 64,
          'format': 'lrc',
        },
        'artwork': {
          'url': '/api/v1/files/Lamaze/cover.png',
          'sizeBytes': 8192,
          'sha256': 'c' * 64,
          'mimeType': 'image/png',
        },
      },
    ],
  };
}
