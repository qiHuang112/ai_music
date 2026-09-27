import 'dart:io';

import 'package:ai_music/src/data/search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late SearchHistoryStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-music-search-history-');
    store = SearchHistoryStore(rootProvider: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'saves separate histories, moves repeats to front, and deletes',
    () async {
      await store.record(SearchHistoryKind.song, '  稻香  ');
      await store.record(SearchHistoryKind.playlist, '儿童歌曲');
      await store.record(SearchHistoryKind.song, '晴天');
      await store.record(SearchHistoryKind.song, '稻香');
      await store.record(SearchHistoryKind.song, '   ');

      final reopened = SearchHistoryStore(rootProvider: () async => root);
      await reopened.load();
      expect(reopened.entries(SearchHistoryKind.song), ['稻香', '晴天']);
      expect(reopened.entries(SearchHistoryKind.playlist), ['儿童歌曲']);

      await reopened.remove(SearchHistoryKind.song, '稻香');
      final afterDelete = SearchHistoryStore(rootProvider: () async => root);
      await afterDelete.load();
      expect(afterDelete.entries(SearchHistoryKind.song), ['晴天']);
      expect(afterDelete.entries(SearchHistoryKind.playlist), ['儿童歌曲']);
    },
  );

  test('keeps only the most recent 30 submissions', () async {
    for (var i = 0; i < 31; i++) {
      await store.record(SearchHistoryKind.song, 'term $i');
    }
    expect(store.entries(SearchHistoryKind.song), hasLength(30));
    expect(store.entries(SearchHistoryKind.song).first, 'term 30');
    expect(store.entries(SearchHistoryKind.song), isNot(contains('term 0')));
  });
}
