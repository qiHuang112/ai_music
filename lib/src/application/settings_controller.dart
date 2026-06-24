import '../data/music_resolver.dart';
import '../data/music_settings.dart';

class SettingsController {
  const SettingsController({required this.settingsStore});

  final MusicSettingsStore settingsStore;

  Future<MusicAppSettings> load() {
    return settingsStore.loadSettings();
  }

  Future<void> save({
    required MusicDataSource source,
    required AppLanguage language,
    required AppThemePreference theme,
  }) {
    return settingsStore.saveSettings(
      MusicAppSettings(source: source, language: language, theme: theme),
    );
  }
}
