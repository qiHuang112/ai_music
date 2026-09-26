import 'dart:io';

import 'package:ai_music/src/playback/on_demand_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serves exact local byte ranges after one preparation', () async {
    final root = await Directory.systemTemp.createTemp('on_demand_audio_');
    final file = File('${root.path}/song.mp3');
    await file.writeAsBytes(List<int>.generate(100, (index) => index));
    var preparations = 0;
    final source = OnDemandAudioSource(
      tag: 'song',
      prepare: () async {
        preparations += 1;
        return file;
      },
    );
    try {
      final first = await source.request(10, 20);
      expect(first.sourceLength, 100);
      expect(first.contentLength, 10);
      expect(first.offset, 10);
      expect(
        await first.stream.expand((bytes) => bytes).toList(),
        List<int>.generate(10, (index) => index + 10),
      );
      final second = await source.request(20, 25);
      expect(await second.stream.expand((bytes) => bytes).toList(), [
        20,
        21,
        22,
        23,
        24,
      ]);
      expect(preparations, 1);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('uses the cached audio format as the proxy content type', () async {
    final root = await Directory.systemTemp.createTemp('audio_content_type_');
    try {
      for (final (extension, expected) in [
        ('wav', 'audio/wav'),
        ('aac', 'audio/aac'),
        ('ape', 'audio/ape'),
      ]) {
        final file = File('${root.path}/song.$extension');
        await file.writeAsBytes([1, 2, 3]);
        final source = OnDemandAudioSource(
          tag: 'song',
          prepare: () async => file,
        );
        expect((await source.request()).contentType, expected);
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
}
