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
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.source2t58,
                    title: Text(strings.source2t58),
                    subtitle: Text(strings.source2t58Description),
                    enabled: false,
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.source22a5,
                    title: Text(strings.source22a5),
                    subtitle: Text(strings.source22a5Description),
                    enabled: false,
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.gequhai,
                    title: Text(strings.gequhaiSource),
                    subtitle: Text(strings.gequhaiDescription),
                    enabled: false,
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.gequbao,
                    title: Text(strings.gequbaoSource),
                    subtitle: Text(strings.gequbaoDescription),
                    enabled: false,
                  ),
                  RadioListTile<MusicDataSource>(
                    value: MusicDataSource.kuwoFullAudio,
                    title: Text(strings.kuwoFullAudioSource),
                    subtitle: Text(strings.kuwoFullAudioDescription),
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
    MusicDataSource.source2t58 => strings.source2t58,
    MusicDataSource.source22a5 => '22a5',
    MusicDataSource.gequhai => strings.gequhaiSource,
    MusicDataSource.gequbao => strings.gequbaoSource,
    MusicDataSource.kuwoFullAudio => strings.kuwoFullAudioSource,
    MusicDataSource.itunesPreview => strings.itunesPreviewSource,
  };
}
