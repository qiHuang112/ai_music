import 'dart:convert';
import 'dart:io';

import 'package:ai_music/src/data/json_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('write replaces existing JSON without deleting first', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_json_store_');
    final file = File('${root.path}${Platform.pathSeparator}store.json');
    const store = JsonFileStore();

    try {
      await file.writeAsString(jsonEncode({'version': 1}));
      await store.write(file, {'version': 2});

      expect(jsonDecode(await file.readAsString()), {'version': 2});
      expect(
        root.listSync().where((entity) => entity.path.contains('.tmp-')),
        isEmpty,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('read backs up damaged JSON and exposes the backup path', () async {
    final root = await Directory.systemTemp.createTemp('ai_music_json_bad_');
    final file = File('${root.path}${Platform.pathSeparator}store.json');
    const store = JsonFileStore();

    try {
      await file.writeAsString('{bad json');

      await expectLater(
        store.read(file),
        throwsA(
          isA<JsonFileStoreException>().having(
            (error) => error.backupPath,
            'backupPath',
            isNotNull,
          ),
        ),
      );

      expect(await file.exists(), isFalse);
      expect(
        root.listSync().whereType<File>().where(
          (candidate) => candidate.path.contains('.corrupt-'),
        ),
        hasLength(1),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
