import '../data/lan_library_models.dart';
import 'duo_scaffold.dart';
import 'app_page_route.dart';
import 'app_theme.dart';
import 'listening_stats_page.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import 'app_localizations.dart';
import 'app_update_page.dart';
import 'design/glass_surface.dart';
import 'desktop_ui.dart';
import '../application/diagnostics_upload_controller.dart';
import 'design/app_icons.dart';

/// Desktop settings keep the categories visible while changing their content.
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key, required this.controller});
  final MusicController controller;
  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  int _index = 0;
  final _visited = {0};
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final strings = AppStringsScope.of(context);
    final titles = strings.isZh
        ? ['通用', '外观', '语言', '音源', '下载品质', '并发设置', '局域网']
        : [
            'General',
            'Appearance',
            'Language',
            'Sources',
            'Quality',
            'Concurrency',
            'LAN',
          ];
    const icons = [
      AppIcons.tune,
      AppIcons.paint,
      AppIcons.language,
      AppIcons.cloud,
      AppIcons.quality,
      AppIcons.sync,
      AppIcons.lan,
    ];
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 2, 32, 18),
          child: Text(
            strings.settings,
            style: MusicType.masthead(context, size: 34),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 196,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 20),
                  children: [
                    for (var i = 0; i < titles.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: DesktopRow(
                          selected: i == _index,
                          height: 34,
                          onTap: () => setState(() {
                            _index = i;
                            _visited.add(i);
                          }),
                          child: Row(
                            children: [
                              Icon(icons[i], size: 17, color: colors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  titles[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: i == _index
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 24, 20),
                  child: GlassSurface(
                    level: GlassLevel.thin,
                    borderRadius: BorderRadius.circular(18),
                    child: IndexedStack(
                      index: _index,
                      children: [
                        for (var i = 0; i < titles.length; i++)
                          if (!_visited.contains(i))
                            const SizedBox.shrink()
                          else
                            switch (i) {
                              0 => Scaffold(
                                appBar: AppBar(title: Text(titles[0])),
                                body: ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    DiagnosticsUploadSetting(
                                      controller: c.diagnostics,
                                    ),
                                    _PlaybackCacheSetting(controller: c),
                                    ListTile(
                                      leading: const Icon(
                                        AppIcons.insights,
                                      ),
                                      title: Text(
                                        strings.isZh
                                            ? '清空听歌统计'
                                            : 'Clear listening history',
                                      ),
                                      subtitle: Text(
                                        strings.isZh
                                            ? '只清空统计，保留歌曲和歌单'
                                            : 'Keep songs and playlists',
                                      ),
                                      onTap: () => confirmClearListeningStats(
                                        context,
                                        c,
                                      ),
                                    ),
                                    ListTile(
                                      leading: const Icon(AppIcons.downloaded),
                                      title: Text(
                                        strings.isZh
                                            ? '已下载歌曲'
                                            : 'Downloaded songs',
                                      ),
                                      subtitle: Text(
                                        '${c.manuallyDownloadedSongCount}',
                                      ),
                                    ),
                                    SwitchListTile(
                                      secondary: const Icon(AppIcons.speed),
                                      title: Text(
                                        strings.isZh
                                            ? '性能悬浮窗'
                                            : 'Performance overlay',
                                      ),
                                      value: c.performanceOverlayEnabled,
                                      onChanged:
                                          c.savePerformanceOverlayEnabled,
                                    ),
                                  ],
                                ),
                              ),
                              1 => ThemeSettingsPage(controller: c),
                              2 => LanguageSettingsPage(controller: c),
                              3 => SourceSettingsPage(controller: c),
                              4 => _DownloadQualityPage(controller: c),
                              5 => _ConcurrencySettingsPage(controller: c),
                              _ => LanLibrarySettingsPage(controller: c),
                            },
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DuoScaffold(
          appBar: AppBar(
            titleTextStyle: MusicType.masthead(context, size: 30),
            title: Text(strings.settings),
          ),
          body: SafeArea(
            // The list runs on under the floating bottom bars.
            bottom: false,
            child: ListView(
              padding: MusicUi.scrollInsets(context),
              children: [
                _SettingsGroup(
                  title: strings.isZh ? '通用' : 'General',
                  children: [
                    if (controller.appUpdates.supported)
                      AppUpdateSetting(updates: controller.appUpdates),
                    DiagnosticsUploadSetting(
                      controller: controller.diagnostics,
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.language),
                      title: Text(strings.language),
                      subtitle: Text(
                        controller.language == AppLanguage.zh
                            ? strings.chinese
                            : strings.english,
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'language-settings',
                          ),
                          builder: (_) =>
                              LanguageSettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.contrast),
                      title: Text(strings.theme),
                      subtitle: Text(
                        strings.themeName(controller.themePreference),
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'appearance-settings',
                          ),
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
                      leading: const Icon(AppIcons.source),
                      title: Text(strings.musicSource),
                      subtitle: Text(_sourceTitle(strings, controller.source)),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'source-settings',
                          ),
                          builder: (_) =>
                              SourceSettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key('default-download-quality'),
                      leading: const Icon(AppIcons.quality),
                      title: Text(
                        strings.isZh ? '默认下载品质' : 'Default download quality',
                      ),
                      subtitle: Text(
                        _qualityTitle(
                          strings.isZh,
                          controller.defaultDownloadQuality,
                        ),
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'download-quality',
                          ),
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
                      leading: const Icon(AppIcons.insights),
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
                      leading: const Icon(AppIcons.downloaded),
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
                    SwitchListTile(
                      key: const Key('performance-overlay-setting'),
                      secondary: const Icon(AppIcons.speed),
                      title: Text(
                        strings.isZh ? '性能悬浮窗' : 'Performance overlay',
                      ),
                      subtitle: Text(
                        strings.isZh
                            ? '实时 FPS、内存、CPU，并记录性能日志'
                            : 'Live FPS, memory, CPU and performance logs',
                      ),
                      value: controller.performanceOverlayEnabled,
                      onChanged: controller.savePerformanceOverlayEnabled,
                    ),
                    ListTile(
                      key: const Key('concurrency-settings'),
                      leading: const Icon(AppIcons.tune),
                      title: Text(strings.isZh ? '并发设置' : 'Concurrency'),
                      subtitle: Text(
                        strings.isZh
                            ? '截图搜歌 ${controller.screenshotSearchConcurrency} 首 · 歌单下载 ${controller.playlistDownloadConcurrency} 首'
                            : 'Screenshot search ${controller.screenshotSearchConcurrency} · Playlist downloads ${controller.playlistDownloadConcurrency}',
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'concurrency-settings',
                          ),
                          builder: (_) =>
                              _ConcurrencySettingsPage(controller: controller),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.lan),
                      title: Text(strings.lanLibrary),
                      subtitle: Text(controller.lanLibraryUrl),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => Navigator.of(context).push<void>(
                        AppPageRoute(
                          settings: const RouteSettings(
                            name: 'lan-library-settings',
                          ),
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
    return DuoScaffold(
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
      builder: (context, _) => DuoScaffold(
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

  // The settings tab stays alive behind the others; read the size again each
  // time it comes back to the front.
  bool _front = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // flutter_ohos does not have TickerMode.valuesOf yet.
    // ignore: deprecated_member_use
    final front = TickerMode.of(context);
    if (front && !_front) {
      // A rebuild follows this callback; no setState needed.
      _bytes = widget.controller.playbackCacheBytes();
    }
    _front = front;
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
      // A rebuild follows this callback; no setState needed.
      _bytes = widget.controller.playbackCacheBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    return FutureBuilder<int>(
      future: _bytes,
      builder: (context, snapshot) => ListTile(
        key: const Key('playback-cache-size'),
        leading: const Icon(AppIcons.storage),
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
          leading: const Icon(AppIcons.imageSearch),
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
          leading: const Icon(AppIcons.download),
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
        return DuoScaffold(
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
                    hintText: defaultLanLibraryUrl,
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
                      icon: const Icon(AppIcons.save),
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
                          : const Icon(AppIcons.network),
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
        return DuoScaffold(
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
        return DuoScaffold(
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
                  for (final theme in AppThemePreference.values)
                    RadioListTile<AppThemePreference>(
                      value: theme,
                      title: Text(strings.themeName(theme)),
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
        return DuoScaffold(
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
                  for (final source in controller.selectableSources)
                    RadioListTile<MusicDataSource>(
                      value: source,
                      title: Text(_sourceTitle(strings, source)),
                      subtitle: Text(_sourceDescription(strings, source)),
                    ),
                  for (final policy in controller.sourceCatalog.orderedPolicies)
                    if (!controller.selectableSources.contains(policy.source))
                      ListTile(
                        leading: Icon(
                          policy.fallbackOnly
                              ? AppIcons.sparkles
                              : AppIcons.lock,
                        ),
                        title: Text(_sourceTitle(strings, policy.source)),
                        subtitle: Text(
                          policy.fallbackOnly
                              ? (strings.isZh
                                    ? '有每日限额，仅在常规来源都没有可用结果时自动尝试，不支持手动选择。'
                                    : 'Daily allowance applies. Automatic fallback only when regular sources are unavailable; not selectable manually.')
                              : (strings.isZh
                                    ? '需要授权后才能使用。'
                                    : 'Authorization is required before use.'),
                        ),
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

String _sourceDescription(AppStrings strings, MusicDataSource source) =>
    switch (source) {
      MusicDataSource.flac => strings.flacSourceDescription,
      MusicDataSource.buguyy => strings.buguyyDescription,
      _ =>
        strings.isZh
            ? '用于搜索、歌单匹配及未缓存歌曲。'
            : 'For search, playlist matching and uncached songs.',
    };

String _sourceTitle(AppStrings strings, MusicDataSource source) {
  return switch (source) {
    MusicDataSource.auto => strings.autoSource,
    MusicDataSource.buguyy => strings.buguyy,
    MusicDataSource.flac => strings.flacSource,
    MusicDataSource.twentyFourBit => strings.twentyFourBitLabel,
    MusicDataSource.lan => 'LAN',
  };
}

class DiagnosticsUploadSetting extends StatefulWidget {
  const DiagnosticsUploadSetting({super.key, required this.controller});
  final DiagnosticsUploadController controller;
  @override
  State<DiagnosticsUploadSetting> createState() =>
      _DiagnosticsUploadSettingState();
}

class _DiagnosticsUploadSettingState extends State<DiagnosticsUploadSetting> {
  @override
  void initState() {
    super.initState();
    widget.controller.probe();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final upload = widget.controller;
        if (!upload.available) return const SizedBox.shrink();
        return ListTile(
          key: const Key('upload-diagnostics'),
          leading: const Icon(AppIcons.upload),
          title: Text(strings.isZh ? '上传日志' : 'Upload logs'),
          subtitle: Text(
            upload.uploading
                ? (strings.isZh ? '正在上传…' : 'Uploading…')
                : upload.reportId != null
                ? (strings.isZh ? '上传成功' : 'Upload complete')
                : (strings.isZh
                      ? '核心操作日志与每日听歌统计'
                      : 'Operations and daily listening statistics'),
          ),
          trailing: upload.uploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AppIcons.chevronRight),
          onTap: upload.uploading
              ? null
              : () async {
                  await upload.upload();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        upload.reportId != null
                            ? (strings.isZh ? '日志已上传' : 'Logs uploaded')
                            : upload.error ??
                                  (strings.isZh ? '日志上传失败' : 'Upload failed'),
                      ),
                    ),
                  );
                },
        );
      },
    );
  }
}
