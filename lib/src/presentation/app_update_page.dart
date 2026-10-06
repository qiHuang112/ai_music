import 'app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../application/app_update_controller.dart';
import 'app_localizations.dart';

String updateDateLabel(DateTime date) {
  final local = date.toLocal();
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
}

class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key, required this.updates, required this.child});
  final AppUpdateController updates;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) => Badge(
      key: const Key('app-update-badge'),
      isLabelVisible: updates.hasUpdate,
      backgroundColor: Theme.of(context).colorScheme.error,
      smallSize: 7,
      child: child,
    ),
  );
}

class AppUpdateSetting extends StatefulWidget {
  const AppUpdateSetting({super.key, required this.updates});
  final AppUpdateController updates;
  @override
  State<AppUpdateSetting> createState() => _AppUpdateSettingState();
}

class _AppUpdateSettingState extends State<AppUpdateSetting> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.updates.check());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.updates,
    builder: (context, _) {
      final current = widget.updates.current;
      final zh = AppStringsScope.of(context).isZh;
      return ListTile(
        key: const Key('check-app-update'),
        leading: UpdateBadge(
          updates: widget.updates,
          child: const Icon(Icons.system_update),
        ),
        title: Text(zh ? '检测更新' : 'Check for updates'),
        subtitle: Text(
          current == null
              ? (zh ? '读取版本中…' : 'Reading version…')
              : '${current.label}${current.channel == 'debug' ? ' · debug' : ''}\n${zh ? '更新时间' : 'Updated'} ${updateDateLabel(current.builtAt)}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => AppUpdatePage(updates: widget.updates),
          ),
        ),
      );
    },
  );
}

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key, required this.updates});
  final AppUpdateController updates;
  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.updates.check());
  }

  Future<void> _editServer() async {
    final zh = AppStringsScope.of(context).isZh;
    final field = TextEditingController(text: widget.updates.serverUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh ? '更新服务地址' : 'Update server'),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: defaultUpdateUrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(zh ? '保存' : 'Save'),
          ),
        ],
      ),
    );
    // The dialog field remains attached during its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    field.dispose();
    if (value == null) return;
    try {
      await widget.updates.saveServer(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : (zh ? '保存失败，请重试' : 'Could not save. Retry.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.updates,
    builder: (context, _) {
      final updates = widget.updates;
      final zh = AppStringsScope.of(context).isZh;
      final current = updates.current;
      final latest = updates.latest;
      return Scaffold(
        appBar: AppBar(title: Text(zh ? '检测更新' : 'App updates')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.system_update, size: 56),
              const SizedBox(height: 16),
              Text(
                current?.label ?? '…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${zh ? '更新时间' : 'Updated'} ${updateDateLabel(current.builtAt)}',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
              if (current != null && !updates.releaseChannel)
                Text(
                  zh
                      ? '当前为 ${current.channel} 版本，应用内更新仅提供 release 包。调试版继续通过电脑安装。'
                      : 'This ${current.channel} build does not install release updates.',
                ),
              if (updates.checking) const LinearProgressIndicator(),
              if (updates.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(updates.error!, key: const Key('update-error')),
                ),
              if (updates.hasUpdate && latest != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(MusicUi.pagePadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${zh ? '新版本' : 'New version'} ${latest.name} (${latest.code})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${updateDateLabel(latest.publishedAt)} · ${(latest.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                        ),
                        if (latest.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(latest.notes),
                          ),
                        const SizedBox(height: 16),
                        if (updates.downloading) ...[
                          LinearProgressIndicator(value: updates.progress),
                          const SizedBox(height: 8),
                          Text(
                            '${(updates.received / (1024 * 1024)).toStringAsFixed(1)} / ${(latest.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                          ),
                          TextButton(
                            onPressed: updates.cancelDownload,
                            child: Text(zh ? '取消下载' : 'Cancel download'),
                          ),
                        ] else
                          FilledButton.icon(
                            key: const Key('install-app-update'),
                            onPressed: updates.installing
                                ? null
                                : updates.downloadAndInstall,
                            icon: const Icon(Icons.download),
                            label: Text(
                              updates.downloadedApk == null
                                  ? (zh ? '更新' : 'Update')
                                  : (zh ? '安装' : 'Install'),
                            ),
                          ),
                        if (updates.installNotice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(updates.installNotice!),
                          ),
                      ],
                    ),
                  ),
                ),
              if (updates.checked &&
                  !updates.hasUpdate &&
                  updates.error == null)
                Text(zh ? '已是最新版本' : 'Up to date', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('manual-check-update'),
                onPressed:
                    !updates.releaseChannel ||
                        updates.checking ||
                        updates.downloading ||
                        updates.installing
                    ? null
                    : () => updates.check(force: true),
                icon: const Icon(Icons.refresh),
                label: Text(zh ? '检测更新' : 'Check for updates'),
              ),
              const SizedBox(height: 24),
              ListTile(
                title: Text(zh ? '更新服务' : 'Update server'),
                subtitle: Text(updates.serverUrl),
                trailing: const Icon(Icons.edit_outlined),
                onTap:
                    updates.checking ||
                        updates.downloading ||
                        updates.installing
                    ? null
                    : _editServer,
              ),
            ],
          ),
        ),
      );
    },
  );
}
