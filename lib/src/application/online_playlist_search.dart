import 'package:flutter/foundation.dart';

import '../data/online_playlists.dart';

class OnlinePlaylistSearch extends ChangeNotifier {
  OnlinePlaylistSearch(this.repository);
  final OnlinePlaylistRepository repository;
  final _items = <OnlinePlaylistSource, List<OnlinePlaylist>>{};
  final _pages = <OnlinePlaylistSource, int>{};
  final _more = <OnlinePlaylistSource, bool>{};
  final errors = <OnlinePlaylistSource>{};
  final loading = <OnlinePlaylistSource>{};
  String query = '';
  int _generation = 0;
  bool _disposed = false;

  bool get isLoading => loading.isNotEmpty;
  bool get hasMore => _more.values.any((value) => value);
  List<OnlinePlaylist> get items {
    final ne = _items[OnlinePlaylistSource.netease] ?? [];
    final qq = _items[OnlinePlaylistSource.qq] ?? [];
    return [
      for (var i = 0; i < ne.length || i < qq.length; i++) ...[
        if (i < ne.length) ne[i],
        if (i < qq.length) qq[i],
      ],
    ];
  }

  void clear() {
    _generation++;
    query = '';
    _items.clear();
    _pages.clear();
    _more.clear();
    errors.clear();
    loading.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> search(String value) async {
    clear();
    query = value.trim();
    if (query.isEmpty) return;
    await Future.wait([
      for (final source in OnlinePlaylistSource.values) _load(source),
    ]);
  }

  Future<void> loadMore() async {
    await Future.wait([
      for (final source in OnlinePlaylistSource.values)
        if (_more[source] == true && !errors.contains(source)) _load(source),
    ]);
  }

  Future<void> retry(OnlinePlaylistSource source) => _load(source);

  Future<void> _load(OnlinePlaylistSource source) async {
    if (_disposed || query.isEmpty || loading.contains(source)) return;
    final generation = _generation;
    final page = (_pages[source] ?? 0) + 1;
    loading.add(source);
    errors.remove(source);
    notifyListeners();
    try {
      final result = await repository.search(source, query, page: page);
      if (_disposed || generation != _generation) return;
      final existing = _items.putIfAbsent(source, () => []);
      final keys = existing.map((item) => item.key).toSet();
      final additions = result.items
          .where((item) => keys.add(item.key))
          .toList();
      existing.addAll(additions);
      _pages[source] = page;
      // Guard against a service repeatedly returning its first page.
      _more[source] = result.hasMore && additions.isNotEmpty;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      errors.add(source);
    } finally {
      if (!_disposed && generation == _generation) {
        loading.remove(source);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
