import 'dart:io';

import '../platform/app_storage.dart';
import 'json_file_store.dart';

enum SearchHistoryKind { song, playlist }

/// Local, mode-specific submitted search terms. Mutations are serialized so
/// rapid searches or deletes cannot overwrite a newer snapshot.
class SearchHistoryStore {
  SearchHistoryStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;

  static const maxEntries = 30;
  final Future<Directory> Function() _rootProvider;
  final _history = <SearchHistoryKind, List<String>>{
    SearchHistoryKind.song: [],
    SearchHistoryKind.playlist: [],
  };
  Future<void>? _loading;
  Future<void> _tail = Future.value();

  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/search_history.json');

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    Object? json;
    try {
      json = await const JsonFileStore().read(await _file());
    } on JsonFileStoreException {
      return;
    }
    if (json is! Map) return;
    for (final kind in SearchHistoryKind.values) {
      final saved = json[kind.name];
      if (saved is! List) continue;
      final entries = _history[kind]!;
      for (final item in saved) {
        if (item is! String) continue;
        final term = item.trim();
        if (term.isEmpty ||
            entries.any((entry) => entry.toLowerCase() == term.toLowerCase())) {
          continue;
        }
        entries.add(term);
        if (entries.length == maxEntries) break;
      }
    }
  }

  List<String> entries(SearchHistoryKind kind) =>
      List.unmodifiable(_history[kind]!);

  Future<void> record(SearchHistoryKind kind, String query) {
    final term = query.trim();
    if (term.isEmpty) return Future.value();
    return _mutate(() {
      final entries = _history[kind]!;
      entries.removeWhere((entry) => entry.toLowerCase() == term.toLowerCase());
      entries.insert(0, term);
      if (entries.length > maxEntries) {
        entries.removeRange(maxEntries, entries.length);
      }
    });
  }

  Future<void> remove(SearchHistoryKind kind, String query) => _mutate(() {
    _history[kind]!.removeWhere((entry) => entry == query);
  });

  Future<void> _mutate(void Function() action) {
    final work = _tail.then((_) async {
      await load();
      action();
      await const JsonFileStore().write(await _file(), {
        for (final kind in SearchHistoryKind.values) kind.name: _history[kind],
      });
    });
    _tail = work.then<void>((_) {}, onError: (_) {});
    return work;
  }
}
