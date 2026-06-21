import 'dart:convert';
import 'dart:io';

class JsonFileStoreException implements Exception {
  const JsonFileStoreException(this.message, {this.backupPath});

  final String message;
  final String? backupPath;

  @override
  String toString() {
    final backup = backupPath == null ? '' : ' Backup: $backupPath';
    return '$message.$backup';
  }
}

class JsonFileStore {
  const JsonFileStore();

  Future<Object?> read(File file, {bool backupCorrupt = true}) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      return jsonDecode(await file.readAsString());
    } catch (error) {
      final backup = backupCorrupt ? await backupCorruptFile(file) : null;
      throw JsonFileStoreException(
        'JSON file is damaged: $error',
        backupPath: backup?.path,
      );
    }
  }

  Future<void> write(File file, Object? value) async {
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(jsonEncode(value), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  Future<File> backupCorruptFile(File file) async {
    final backup = File(
      '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (await file.exists()) {
      await file.rename(backup.path);
    }
    return backup;
  }
}
