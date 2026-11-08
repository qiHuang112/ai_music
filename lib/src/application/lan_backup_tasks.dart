import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/lan_backup_client.dart';
import 'lan_backup_use_case.dart';

/// Runs LAN backup uploads and restores for the whole app, so leaving the
/// backup page does not stop them. Pages only show and start tasks; the
/// task, its progress and its last result live here until the app exits.
class LanBackupTasks extends ChangeNotifier {
  LanBackupTasks({
    required this.client,
    required LanBackupUseCase Function(LanBackupClient client) useCase,
  }) : _useCaseFactory = useCase;

  final LanBackupClient client;
  final LanBackupUseCase Function(LanBackupClient client) _useCaseFactory;
  late final LanBackupUseCase useCase = _useCaseFactory(client);

  bool _disposed = false;

  bool get uploading => _uploading;
  bool _uploading = false;
  LanBackupProgress? get uploadProgress => _uploadProgress;
  LanBackupProgress? _uploadProgress;
  String? get uploadMessage => _uploadMessage;
  String? _uploadMessage;

  /// The device whose backup is being restored, or null when idle.
  String? get restoringDeviceId => _restoringDeviceId;
  String? _restoringDeviceId;
  LanBackupProgress? get restoreProgress => _restoreProgress;
  LanBackupProgress? _restoreProgress;

  /// The last restore's outcome per device, kept until the next restore.
  String? restoreMessage(String deviceId) => _restoreMessages[deviceId];
  final _restoreMessages = <String, String>{};

  bool get busy => _uploading || _restoringDeviceId != null;

  /// Starts an upload unless one is running. Completes when it ends; the
  /// outcome is in [uploadMessage].
  Future<void> upload(LanBackupIdentity identity) {
    if (_uploading) return _uploadRun ?? Future.value();
    _uploading = true;
    _uploadMessage = null;
    _uploadProgress = null;
    _notify();
    return _uploadRun = _runUpload(identity);
  }

  Future<void>? _uploadRun;

  Future<void> _runUpload(LanBackupIdentity identity) async {
    try {
      final result = await useCase.upload(
        identity,
        onProgress: (p) {
          _uploadProgress = p;
          _notify();
        },
      );
      _uploadMessage =
          '已上传：${result.playlists} 个歌单、${result.favorites} 首收藏，'
          '共 ${result.tracks} 首歌（新传 ${result.uploadedFiles} 个文件，'
          '${formatBackupSize(result.uploadedBytes)}）';
    } on Object catch (error) {
      _uploadMessage = '上传失败：${backupErrorMessage(error)}。'
          '已传完的歌曲不会重传，再点一次即可继续';
    } finally {
      _uploading = false;
      _uploadProgress = null;
      _uploadRun = null;
      _notify();
    }
  }

  /// Starts restoring [selection] from [deviceId]'s backup unless a restore
  /// is already running. Returns the outcome message, or null if refused.
  Future<String?> restore({
    required String base,
    required String deviceId,
    required LanBackupManifest manifest,
    required LanBackupSelection selection,
    Future<void> Function()? afterRestore,
  }) async {
    if (_restoringDeviceId != null) return null;
    _restoringDeviceId = deviceId;
    _restoreProgress = null;
    _restoreMessages.remove(deviceId);
    _notify();
    String message;
    try {
      final result = await useCase.restore(
        base,
        manifest,
        selection,
        onProgress: (p) {
          _restoreProgress = p;
          _notify();
        },
      );
      await afterRestore?.call();
      final restored = result.songs - result.failed.length;
      message = result.failed.isEmpty
          ? '已恢复 ${result.songs} 首（下载 ${result.downloaded} 首），已并入本机歌单和收藏'
          : '已恢复 $restored 首，${result.failed.length} 首下载失败：'
                '${result.failed.take(3).join('、')}。再点一次只会补下失败的歌';
    } on Object catch (error) {
      message = '恢复失败：${backupErrorMessage(error)}。'
          '已恢复的歌不会重下，再点一次即可继续';
    }
    _restoreMessages[deviceId] = message;
    _restoringDeviceId = null;
    _restoreProgress = null;
    _notify();
    return message;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}

String formatBackupSize(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

String backupErrorMessage(Object error) => switch (error) {
  LanBackupException(:final message) => message,
  _ => '$error'.split('\n').first,
};
