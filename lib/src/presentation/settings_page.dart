import 'app_theme.dart';
import 'listening_stats_page.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import 'app_localizations.dart';
import 'app_update_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(strings.settings)),
          body: SafeArea(
            child: ListView(
              padding: MusicUi.pageInsets,
              children: [
                _SettingsGroup(
                  title: strings.isZh ? '通用' : 'General',
                  children: [
                    if (controller.appUpdates.supported)
                      AppUpdateSetting(updates: controller.appUpdates),
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: Text(strings.language),
                      subtitle: Text(
                        controller.language == AppLanguage.zh
                            ? strings.chinese
                            : strings.english,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              LanguageSettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.contrast),
                      title: Text(strings.theme),
                      subtitle: Text(
                        controller.themePreference == AppThemePreference.light
                            ? strings.lightTheme
                            : strings.darkTheme,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              ThemeSettingsPage(controller: controller),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsGroup(
                  title: strings.isZh ? '音乐与下载' : 'Music & downloads',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.hub),
                      title: Text(strings.musicSource),
                      subtitle: Text(_sourceTitle(strings, controller.source)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              SourceSettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key('default-download-quality'),
                      leading: const Icon(Icons.high_quality),
                      title: Text(
                        strings.isZh ? '默认下载品质' : 'Default download quality',
                      ),
                      subtitle: Text(
                        _qualityTitle(
                          strings.isZh,
                          controller.defaultDownloadQuality,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              _DownloadQualityPage(controller: controller),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsGroup(
                  title: strings.isZh ? '存储' : 'Storage',
                  children: [
                    _PlaybackCacheSetting(controller: controller),
                    ListTile(
                      key: const Key('clear-listening-stats'),
                      leading: const Icon(Icons.insights_outlined),
                      title: Text(
                        strings.isZh ? '清空听歌统计' : 'Clear listening history',
                      ),
                      subtitle: Text(
                        strings.isZh
                            ? '只清空统计，保留歌曲和歌单'
                            : 'Reset statistics; keep songs and playlists',
                      ),
                      onTap: () =>
                          confirmClearListeningStats(context, controller),
                    ),
                    ListTile(
                      key: const Key('manual-download-count'),
                      leading: const Icon(Icons.download_done),
                      title: Text(strings.isZh ? '已下载歌曲' : 'Downloaded songs'),
                      subtitle: Text(
                        strings.isZh
                            ? '${controller.manuallyDownloadedSongCount} 首'
                            : '${controller.manuallyDownloadedSongCount} songs',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsGroup(
                  title: strings.isZh ? '高级' : 'Advanced',
                  children: [
                    ListTile(
                      key: const Key('concurrency-settings'),
                      leading: const Icon(Icons.tune),
                      title: Text(strings.isZh ? '并发设置' : 'Concurrency'),
                      subtitle: Text(
                        strings.isZh
                            ? '截图搜歌 ${controller.screenshotSearchConcurrency} 首 · 歌单下载 ${controller.playlistDownloadConcurrency} 首'
                            : 'Screenshot search ${controller.screenshotSearchConcurrency} · Playlist downloads ${controller.playlistDownloadConcurrency}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              _ConcurrencySettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.wifi_tethering),
                      title: Text(strings.lanLibrary),
                      subtitle: Text(controller.lanLibraryUrl),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              LanLibrarySettingsPage(controller: controller),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MusicUi.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme.merge(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minVerticalPadding: 10,
        iconColor: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                const Divider(height: 1, indent: 52, endIndent: 12),
              children[index],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ConcurrencySettingsPage extends StatelessWidget {
  const _ConcurrencySettingsPage({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '并发设置' : 'Concurrency')),
      body: SafeArea(
        child: ListView(
          padding: MusicUi.pageInsets,
          children: [
            _SettingsGroup(
              title: zh ? '任务并发' : 'Parallel tasks',
              children: [
                _ScreenshotSearchConcurrencySetting(controller: controller),
                _PlaylistDownloadConcurrencySetting(controller: controller),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _qualityTitle(bool zh, MusicQualityLevel quality) => switch (quality) {
  MusicQualityLevel.high => zh ? '高品质（无损优先）' : 'High (lossless preferred)',
  MusicQualityLevel.medium =>
    zh ? '中品质（MP3 320K 优先）' : 'Medium (MP3 320K preferred)',
  MusicQualityLevel.low => zh ? '低品质（MP3 128K 优先）' : 'Low (MP3 128K preferred)',
};

class _DownloadQualityPage extends StatelessWidget {
  const _DownloadQualityPage({required this.controller});
  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(zh ? '默认下载品质' : 'Default download quality')),
        body: SafeArea(
          child: RadioGroup<MusicQualityLevel>(
            groupValue: controller.defaultDownloadQuality,
            onChanged: (value) {
              if (value != null) controller.saveDefaultDownloadQuality(value);
            },
            child: ListView(
              children: [
                for (final level in MusicQualityLevel.values)
                  RadioListTile<MusicQualityLevel>(
                    key: ValueKey('download-quality-${level.storageValue}'),
                    value: level,
                    title: Text(_qualityTitle(zh, level)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(MusicUi.pagePadding),
                  child: Text(
                    zh
                        ? '新收藏的歌曲、主动下载单首或整张歌单使用此品质；音源缺少该品质时使用可用版本。播放缓存始终优先用低品质，不会自动升级。'
                        : 'New favorites and manual song and playlist downloads use this quality when available. Playback cache starts low and is not upgraded automatically.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackCacheSetting extends StatefulWidget {
  const _PlaybackCacheSetting({required this.controller});
  final MusicController controller;

  @override
  State<_PlaybackCacheSetting> createState() => _PlaybackCacheSettingState();
}

class _PlaybackCacheSettingState extends State<_PlaybackCacheSetting> {
  late Future<int> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.controller.playbackCacheBytes();
  }

  Future<void> _clear() async {
    final zh = AppStringsScope.of(context).isZh;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh ? '清除播放缓存？' : 'Clear playback cache?'),
        content: Text(
          zh
              ? '会停止当前播放并清除边下边播的音频及未完成片段。主动下载的歌曲、歌单和收藏不会删除。'
              : 'This stops playback and removes streamed audio and unfinished parts. Manual downloads, playlists, and favorites stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(zh ? '清除' : 'Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.clearPlaybackCache();
    if (mounted) {
      setState(() => _bytes = widget.controller.playbackCacheBytes());
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return FutureBuilder<int>(
      future: _bytes,
      builder: (context, snapshot) => ListTile(
        key: const Key('playback-cache-size'),
        leading: const Icon(Icons.storage),
        title: Text(zh ? '播放缓存' : 'Playback cache'),
        subtitle: Text(
          snapshot.hasData
              ? '${(snapshot.data! / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '…',
        ),
        trailing: TextButton(
          onPressed: _clear,
          child: Text(zh ? '清除' : 'Clear'),
        ),
      ),
    );
  }
}

class _ScreenshotSearchConcurrencySetting extends StatefulWidget {
  const _ScreenshotSearchConcurrencySetting({required this.controller});

  final MusicController controller;

  @override
  State<_ScreenshotSearchConcurrencySetting> createState() =>
      _ScreenshotSearchConcurrencySettingState();
}

class _ScreenshotSearchConcurrencySettingState
    extends State<_ScreenshotSearchConcurrencySetting> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.controller.screenshotSearchConcurrency;
  }

  @override
  void didUpdateWidget(
    covariant _ScreenshotSearchConcurrencySetting oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _value = widget.controller.screenshotSearchConcurrency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.image_search),
          title: Text(strings.screenshotSearchConcurrency),
          subtitle: Text(
            strings.screenshotSearchConcurrencyDescription(_value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24, bottom: 8),
          child: Slider(
            key: const Key('screenshotSearchConcurrencySlider'),
            value: _value.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_value',
            onChanged: (value) => setState(() => _value = value.round()),
            onChangeEnd: (value) {
              widget.controller.saveScreenshotSearchConcurrency(value.round());
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistDownloadConcurrencySetting extends StatefulWidget {
  const _PlaylistDownloadConcurrencySetting({required this.controller});

  final MusicController controller;

  @override
  State<_PlaylistDownloadConcurrencySetting> createState() =>
      _PlaylistDownloadConcurrencySettingState();
}

class _PlaylistDownloadConcurrencySettingState
    extends State<_PlaylistDownloadConcurrencySetting> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.controller.playlistDownloadConcurrency;
  }

  @override
  void didUpdateWidget(
    covariant _PlaylistDownloadConcurrencySetting oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _value = widget.controller.playlistDownloadConcurrency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(strings.playlistDownloadConcurrency),
          subtitle: Text(
            strings.playlistDownloadConcurrencyDescription(_value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24, bottom: 8),
          child: Slider(
            key: const Key('playlistDownloadConcurrencySlider'),
            value: _value.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_value',
            onChanged: (value) => setState(() => _value = value.round()),
            onChangeEnd: (value) => widget.controller
                .savePlaylistDownloadConcurrency(value.round()),
          ),
        ),
      ],
    );
  }
}

class LanLibrarySettingsPage extends StatefulWidget {
  const LanLibrarySettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<LanLibrarySettingsPage> createState() => _LanLibrarySettingsPageState();
}

class _LanLibrarySettingsPageState extends State<LanLibrarySettingsPage> {
  late final TextEditingController _addressController;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(
      text: widget.controller.lanLibraryUrl,
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.controller.saveLanLibraryUrl(_addressController.text);
      _addressController.text = widget.controller.lanLibraryUrl;
      if (mounted) {
        setState(() => _inputError = null);
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _inputError = error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(title: Text(strings.lanLibrary)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(MusicUi.pagePadding),
              children: [
                Text(strings.lanLibraryDescription),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('lanLibraryUrlField'),
                  controller: _addressController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.lanLibraryAddress,
                    hintText: 'http://192.168.31.57:8787',
                    errorText: _inputError,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(strings.saveLanAddress),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.isTestingLanConnection
                          ? null
                          : () => controller.testLanConnection(
                              _addressController.text,
                            ),
                      icon: controller.isTestingLanConnection
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: Text(strings.testLanConnection),
                    ),
                  ],
                ),
                if (controller.lanConnectionStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(controller.lanConnectionStatus!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(strings.language)),
          body: SafeArea(
            child: RadioGroup<AppLanguage>(
              groupValue: controller.language,
              onChanged: (language) {
                if (language != null) {
                  controller.saveLanguage(language);
                }
              },
              child: ListView(
                children: [
                  RadioListTile<AppLanguage>(
                    value: AppLanguage.zh,
                    title: Text(strings.chinese),
                  ),
                  RadioListTile<AppLanguage>(
                    value: AppLanguage.en,
                    title: Text(strings.english),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(strings.theme)),
          body: SafeArea(
            child: RadioGroup<AppThemePreference>(
              groupValue: controller.themePreference,
              onChanged: (theme) {
                if (theme != null) {
                  controller.saveTheme(theme);
                }
              },
              child: ListView(
                children: [
                  RadioListTile<AppThemePreference>(
                    value: AppThemePreference.light,
                    title: Text(strings.lightTheme),
                  ),
                  RadioListTile<AppThemePreference>(
                    value: AppThemePreference.dark,
                    title: Text(strings.darkTheme),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SourceSettingsPage extends StatelessWidget {
  const SourceSettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(strings.musicSource)),
          body: SafeArea(
            child: RadioGroup<MusicDataSource>(
              groupValue: controller.source,
              onChanged: (source) {
                if (source != null) {
                  controller.saveSource(source);
                }
              },
              child: ListView(
                children: [
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.auto,
                    title: Text(strings.autoSource),
                    subtitle: Text(strings.autoSourceDescription),
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.buguyy,
                    title: Text(strings.buguyy),
                    subtitle: Text(strings.buguyyDescription),
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.flac,
                    title: Text(strings.flacSource),
                    subtitle: Text(strings.flacSourceDescription),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _sourceTitle(AppStrings strings, MusicDataSource source) {
  return switch (source) {
    MusicDataSource.auto => strings.autoSource,
    MusicDataSource.buguyy => strings.buguyy,
    MusicDataSource.flac => strings.flacSource,
    MusicDataSource.lan => 'LAN',
  };
}
