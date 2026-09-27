import 'dart:io';
import '../platform/app_storage.dart';
import 'json_file_store.dart';

class DownloadHistoryStore {
  DownloadHistoryStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;
  final Future<Directory> Function() _rootProvider;
  Future<void> _tail = Future.value();
  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/download_history.json');
  Future<List<Map<String, dynamic>>> read() async {
    Object? data;
    try {
      data = await const JsonFileStore().read(await _file());
    } on JsonFileStoreException {
      return [];
    }
    if (data is! List) return [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) item,
    ];
  }

  Future<void> write(List<Map<String, Object?>> tasks) {
    final work = _tail.then(
      (_) async => const JsonFileStore().write(await _file(), tasks),
    );
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }
}
