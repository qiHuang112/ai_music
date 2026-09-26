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
    required String lanLibraryUrl,
    required int screenshotSearchConcurrency,
    required int playlistDownloadConcurrency,
    required bool downloadPlaylistsOnWifi,
  }) {
    return settingsStore.saveSettings(
      MusicAppSettings(
        source: source,
        language: language,
        theme: theme,
        lanLibraryUrl: lanLibraryUrl,
        screenshotSearchConcurrency: screenshotSearchConcurrency,
        playlistDownloadConcurrency: playlistDownloadConcurrency,
        downloadPlaylistsOnWifi: downloadPlaylistsOnWifi,
      ),
    );
  }
}
