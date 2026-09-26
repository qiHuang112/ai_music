import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_resolver.dart';
import '../data/music_settings.dart';
import 'app_localizations.dart';

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
              children: [
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
                      builder: (_) => ThemeSettingsPage(controller: controller),
                    ),
                  ),
                ),
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
                _ScreenshotSearchConcurrencySetting(controller: controller),
                SwitchListTile(
                  key: const Key('downloadPlaylistsOnWifiSwitch'),
                  secondary: const Icon(Icons.wifi),
                  title: Text(strings.downloadPlaylistsOnWifi),
                  subtitle: Text(strings.downloadPlaylistsOnWifiDescription),
                  value: controller.downloadPlaylistsOnWifi,
                  onChanged: controller.saveDownloadPlaylistsOnWifi,
                ),
                _PlaylistDownloadConcurrencySetting(controller: controller),
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
          ),
        );
      },
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
              padding: const EdgeInsets.all(16),
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
                    border: const OutlineInputBorder(),
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
