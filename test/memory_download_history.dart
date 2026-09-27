import 'package:ai_music/src/data/download_history_store.dart';

class MemoryDownloadHistory extends DownloadHistoryStore {
  List<Map<String, dynamic>> records = [];
  @override
  Future<List<Map<String, dynamic>>> read() async => List.of(records);
  @override
  Future<void> write(List<Map<String, Object?>> tasks) async {
    records = [for (final task in tasks) Map<String, dynamic>.of(task)];
  }
}
