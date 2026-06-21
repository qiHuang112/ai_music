import 'dart:convert';
import 'dart:io';

import 'json_file_store.dart';
import 'music_resolver.dart';
import '../platform/app_storage.dart';

enum AppLanguage {
  zh('zh'),
  en('en');

  const AppLanguage(this.storageValue);

  final String storageValue;

  static AppLanguage fromStorage(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.storageValue == value,
      orElse: () => AppLanguage.zh,
    );
  }
}

enum AppThemePreference {
  light('light'),
  dark('dark');

  const AppThemePreference(this.storageValue);

  final String storageValue;

  static AppThemePreference fromStorage(String? value) {
    return AppThemePreference.values.firstWhere(
      (theme) => theme.storageValue == value,
      orElse: () => AppThemePreference.dark,
    );
  }
}

class MusicAppSettings {
  const MusicAppSettings({
    this.source = MusicDataSource.buguyy,
    this.language = AppLanguage.zh,
    this.theme = AppThemePreference.dark,
  });

  final MusicDataSource source;
  final AppLanguage language;
  final AppThemePreference theme;

  MusicAppSettings copyWith({
    MusicDataSource? source,
    AppLanguage? language,
    AppThemePreference? theme,
  }) {
    return MusicAppSettings(
      source: source ?? this.source,
      language: language ?? this.language,
      theme: theme ?? this.theme,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'source': source.storageValue,
      'language': language.storageValue,
      'themeMode': theme.storageValue,
    };
  }
}

class MusicSettingsStore {
  MusicSettingsStore({Future<Directory> Function()? rootProvider})
    : _rootProvider = rootProvider ?? getAiMusicSupportDirectory;

  static const _fileName = 'settings.json';
  final Future<Directory> Function() _rootProvider;
  final JsonFileStore _jsonStore = const JsonFileStore();

  Future<MusicAppSettings> loadSettings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return const MusicAppSettings();
      }
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) {
        return const MusicAppSettings();
      }
      final decoded = await _tryDecodeJson(file, text);
      if (decoded is Map) {
        return MusicAppSettings(
          source: _singleSupportedSource(decoded['source']?.toString()),
          language: AppLanguage.fromStorage(decoded['language']?.toString()),
          theme: AppThemePreference.fromStorage(
            decoded['themeMode']?.toString() ?? decoded['theme']?.toString(),
          ),
        );
      }
      return MusicAppSettings(source: _singleSupportedSource(text));
    } catch (_) {
      return const MusicAppSettings();
    }
  }

  Future<void> saveSettings(MusicAppSettings settings) async {
    final file = await _settingsFile();
    await _jsonStore.write(
      file,
      settings.copyWith(source: _singleSupportedSource(null)).toJson(),
    );
  }

  Future<MusicDataSource> loadSource() async {
    return (await loadSettings()).source;
  }

  Future<void> saveSource(MusicDataSource source) async {
    final current = await loadSettings();
    await saveSettings(current.copyWith(source: _singleSupportedSource(null)));
  }

  Future<File> _settingsFile() async {
    final support = await _rootProvider();
    return File('${support.path}${Platform.pathSeparator}$_fileName');
  }
}

Future<Object?> _tryDecodeJson(File file, String text) async {
  try {
    return jsonDecode(text);
  } catch (_) {
    if ({'auto', 'buguyy', 'flac'}.contains(text.trim())) {
      return text;
    }
    await const JsonFileStore().backupCorruptFile(file);
    return text;
  }
}

MusicDataSource _singleSupportedSource(String? _) {
  return MusicDataSource.buguyy;
}
