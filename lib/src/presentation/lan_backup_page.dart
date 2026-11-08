import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_update_controller.dart' show defaultUpdateUrl;
import '../application/lan_backup_tasks.dart';
import '../application/lan_backup_use_case.dart';
import '../application/music_controller.dart';
import '../data/lan_backup_client.dart';
import 'app_localizations.dart';
import 'app_page_route.dart';
import 'design/adaptive_layout.dart';
import 'design/app_icons.dart';
import 'duo_scaffold.dart';

/// Upload this device's playlists, favorites and their songs to the LAN, and
/// restore what you pick from any device's backup.
class LanBackupPage extends StatefulWidget {
  const LanBackupPage({super.key, required this.controller});
  final MusicController controller;

  @override
  State<LanBackupPage> createState() => _LanBackupPageState();
}

class _LanBackupPageState extends State<LanBackupPage> {
  final _identities = LanBackupIdentityStore(defaultServerUrl: defaultUpdateUrl);
  late final LanBackupTasks _tasks = widget.controller.lanBackup;
  LanBackupClient get _client => _tasks.client;

  LanBackupIdentity? _identity;
  List<LanBackupDevice>? _devices;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _tasks.addListener(_onTasks);
    _identities.load().then((identity) {
      if (!mounted) return;
      setState(() => _identity = identity);
      _refresh();
    });
  }

  bool _wasUploading = false;

  void _onTasks() {
    if (!mounted) return;
    final finished = _wasUploading && !_tasks.uploading;
    _wasUploading = _tasks.uploading;
    setState(() {});
    if (finished) _refresh();
  }

  @override
  void dispose() {
    _tasks.removeListener(_onTasks);
    super.dispose();
  }

  Future<void> _refresh() async {
    final identity = _identity;
    if (identity == null) return;
    setState(() => _listError = null);
    try {
      final devices = await _client.devices(identity.serverUrl);
      if (mounted) setState(() => _devices = devices);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _devices = const [];
          _listError = _message(error);
        });
      }
    }
  }

  void _upload() {
    final identity = _identity;
    if (identity == null || _tasks.uploading) return;
    _wasUploading = true;
    unawaited(_tasks.upload(identity));
  }

  Future<void> _edit({required bool name}) async {
    final identity = _identity;
    if (identity == null) return;
    final field = TextEditingController(
      text: name ? identity.deviceName : identity.serverUrl,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name ? '本机名称' : '局域网服务地址'),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: name ? TextInputType.text : TextInputType.url,
          decoration: InputDecoration(
            helperText: name ? '在其他设备的备份列表里显示' : '例如 $defaultUpdateUrl',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    final next = name
        ? identity.copyWith(deviceName: value)
        : identity.copyWith(serverUrl: value);
    await _identities.save(next);
    if (!mounted) return;
    setState(() => _identity = next);
    if (!name) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    final devices = _devices;
    final theme = Theme.of(context);
    final uploading = _tasks.uploading;
    return DuoScaffold(
      appBar: AppBar(
        title: const Text('局域网备份'),
        actions: [
          IconButton(
            tooltip: AppStringsScope.of(context).refresh,
            onPressed: _refresh,
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => ListView(
            padding: MusicLayout.centered(
              // Clear the system bars so the last device can scroll into view.
              EdgeInsets.fromLTRB(
                16,
                8,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              box.maxWidth,
            ),
            children: [
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: const Icon(AppIcons.devices),
                      title: const Text('本机名称'),
                      subtitle: Text(identity?.deviceName ?? '…'),
                      trailing: const Icon(AppIcons.edit),
                      onTap: () => _edit(name: true),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.server),
                      title: const Text('局域网服务'),
                      subtitle: Text(identity?.serverUrl ?? '…'),
                      trailing: const Icon(AppIcons.edit),
                      onTap: () => _edit(name: false),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '上传本机的歌单、我的收藏和其中已下载的歌曲。同一首歌有多份缓存时，只上传播放时会用的那份（音质最好）。再次上传会覆盖本机上一次的备份。上传在后台进行，离开本页也不会中断；中途断开后再点上传，已传完的歌曲不会重传。',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          if (_tasks.uploadProgress case final p?) ...[
                            LinearProgressIndicator(
                              value: p.total == 0 ? null : p.done / p.total,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${p.stage} ${p.done}/${p.total}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const Key('lan-backup-upload'),
                              onPressed: identity == null || uploading
                                  ? null
                                  : _upload,
                              icon: const Icon(AppIcons.upload),
                              label: Text(uploading ? '正在上传…' : '上传到局域网'),
                            ),
                          ),
                          if (_tasks.uploadMessage case final message?) ...[
                            const SizedBox(height: 8),
                            Text(message, style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('局域网上的备份', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (devices == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_listError case final error?)
                ListTile(
                  leading: const Icon(AppIcons.warning),
                  title: const Text('连不上局域网服务'),
                  subtitle: Text(error),
                )
              else if (devices.isEmpty)
                const ListTile(
                  title: Text('还没有设备上传过备份'),
                  subtitle: Text('在任意设备上点“上传到局域网”后，这里就能选择恢复。'),
                )
              else
                for (final device in devices)
                  Card(
                    child: ListTile(
                      key: ValueKey('lan-backup-device-${device.deviceId}'),
                      leading: const Icon(AppIcons.devices),
                      title: Text(
                        device.deviceId == identity?.deviceId
                            ? '${device.deviceName}（本机）'
                            : device.deviceName,
                      ),
                      subtitle: Text(
                        '${_tasks.restoringDeviceId == device.deviceId ? '正在恢复…\n' : ''}'
                        '${device.playlistCount} 个歌单 · ${device.favoriteCount} 首收藏 · '
                        '${device.trackCount} 首歌 · ${_size(device.totalBytes)}'
                        '${device.receivedAt == null ? '' : '\n上传于 ${_time(device.receivedAt!)}'}',
                      ),
                      isThreeLine: device.receivedAt != null,
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'lan-backup-restore',
                          ),
                          builder: (_) => LanBackupRestorePage(
                            controller: widget.controller,
                            base: identity!.serverUrl,
                            device: device,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick songs from one device's backup: the favorites and, per playlist,
/// which songs to restore. A playlist with nothing picked is not created.
class LanBackupRestorePage extends StatefulWidget {
  const LanBackupRestorePage({
    super.key,
    required this.controller,
    required this.base,
    required this.device,
  });

  final MusicController controller;
  final String base;
  final LanBackupDevice device;

  @override
  State<LanBackupRestorePage> createState() => _LanBackupRestorePageState();
}

class _LanBackupRestorePageState extends State<LanBackupRestorePage> {
  LanBackupManifest? _manifest;
  LanBackupSelection? _selection;
  String? _error;
  late final LanBackupTasks _tasks = widget.controller.lanBackup;

  @override
  void initState() {
    super.initState();
    _tasks.addListener(_onTasks);
    _load();
  }

  void _onTasks() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tasks.removeListener(_onTasks);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final manifest = LanBackupManifest.parse(
        await _tasks.client.manifest(widget.base, widget.device.deviceId),
      );
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _selection = LanBackupSelection.all(manifest);
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _restore() async {
    final manifest = _manifest, selection = _selection;
    if (manifest == null || selection == null || _tasks.restoringDeviceId != null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.controller;
    // Runs on the app-level task: leaving this page does not stop it, and
    // the result still shows wherever the user is.
    final message = await _tasks.restore(
      base: widget.base,
      deviceId: widget.device.deviceId,
      manifest: manifest,
      selection: selection,
      afterRestore: controller.loadCache,
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest, selection = _selection;
    final picked = selection?.allTrackIds.length ?? 0;
    final restoringHere = _tasks.restoringDeviceId == widget.device.deviceId;
    final restoringElsewhere =
        _tasks.restoringDeviceId != null && !restoringHere;
    final progress = restoringHere ? _tasks.restoreProgress : null;
    final lastMessage = _tasks.restoreMessage(widget.device.deviceId);
    return DuoScaffold(
      appBar: AppBar(title: Text(widget.device.deviceName)),
      bottomNavigationBar: manifest == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: AdaptiveBody(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (progress case final p?) ...[
                      LinearProgressIndicator(
                        value: p.total == 0 ? null : p.done / p.total,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.done}/${p.total} ${p.stage}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      key: const Key('lan-backup-restore'),
                      onPressed: picked == 0 || _tasks.restoringDeviceId != null
                          ? null
                          : _restore,
                      icon: const Icon(AppIcons.cloudDownload),
                      label: Text(
                        restoringHere
                            ? '正在恢复…（可离开本页）'
                            : restoringElsewhere
                            ? '正在恢复其他设备的备份…'
                            : '恢复所选（$picked 首）',
                      ),
                    ),
                    if (lastMessage != null && !restoringHere) ...[
                      const SizedBox(height: 6),
                      Text(
                        lastMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: _error != null
            ? Center(child: Text(_error!))
            : manifest == null || selection == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, box) => ListView(
                  padding: MusicLayout.centered(
                    EdgeInsets.fromLTRB(
                      8,
                      8,
                      8,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    box.maxWidth,
                  ),
                  children: [
                    if (manifest.favorites.isNotEmpty)
                      _PickGroup(
                        key: const ValueKey('lan-backup-favorites'),
                        title: '我的收藏',
                        manifest: manifest,
                        trackIds: manifest.favorites,
                        picked: selection.favorites,
                        onChanged: () => setState(() {}),
                      ),
                    for (final (i, playlist) in manifest.playlists.indexed)
                      _PickGroup(
                        key: ValueKey('lan-backup-playlist-$i'),
                        title: playlist.name,
                        manifest: manifest,
                        trackIds: playlist.trackIds,
                        picked: selection.playlists.putIfAbsent(i, () => {}),
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A collapsible group (the favorites or one playlist) with a tri-state box
/// for all of it and a box per song.
class _PickGroup extends StatelessWidget {
  const _PickGroup({
    super.key,
    required this.title,
    required this.manifest,
    required this.trackIds,
    required this.picked,
    required this.onChanged,
  });

  final String title;
  final LanBackupManifest manifest;
  final List<String> trackIds;
  final Set<String> picked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final count = trackIds.where(picked.contains).length;
    final all = count == trackIds.length;
    return Card(
      child: ExpansionTile(
        leading: Checkbox(
          tristate: true,
          value: all ? true : (count == 0 ? false : null),
          onChanged: (_) {
            if (all) {
              picked.removeAll(trackIds);
            } else {
              picked.addAll(trackIds);
            }
            onChanged();
          },
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          count == 0 ? '不恢复' : '已选 $count / ${trackIds.length} 首',
        ),
        children: [
          for (final id in trackIds)
            if (manifest.tracks[id] case final track?)
              CheckboxListTile(
                dense: true,
                value: picked.contains(id),
                onChanged: (on) {
                  if (on ?? false) {
                    picked.add(id);
                  } else {
                    picked.remove(id);
                  }
                  onChanged();
                },
                title: Text(
                  track.title.isEmpty ? id : track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (track.artist.isNotEmpty) track.artist,
                    track.hasAudio ? _size(track.size) : '未下载，仅恢复歌曲信息',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }
}

String _size(int bytes) => formatBackupSize(bytes);

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _message(Object error) => backupErrorMessage(error);
