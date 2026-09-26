import 'dart:io';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/lan_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings store restores legacy source text', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_old_',
    );
    final file = File('${root.path}${Platform.pathSeparator}settings.json');
    await file.writeAsString('flac');
    final store = MusicSettingsStore(rootProvider: () async => root);

    try {
      final settings = await store.loadSettings();

      expect(settings.source, MusicDataSource.flac);
      expect(settings.language, AppLanguage.zh);
      expect(settings.theme, AppThemePreference.dark);
      expect(settings.lanLibraryUrl, defaultLanLibraryUrl);
      expect(settings.screenshotSearchConcurrency, 3);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('settings store defaults to auto source', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_default_',
    );
    final store = MusicSettingsStore(rootProvider: () async => root);

    try {
      final settings = await store.loadSettings();

      expect(settings.source, MusicDataSource.auto);
      expect(settings.language, AppLanguage.zh);
      expect(settings.theme, AppThemePreference.dark);
      expect(settings.lanLibraryUrl, defaultLanLibraryUrl);
      expect(settings.screenshotSearchConcurrency, 3);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('settings store persists language theme and source as json', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_json_',
    );
    final store = MusicSettingsStore(rootProvider: () async => root);

    try {
      await store.saveSettings(
        const MusicAppSettings(
          source: MusicDataSource.buguyy,
          language: AppLanguage.en,
          theme: AppThemePreference.light,
          lanLibraryUrl: 'http://10.0.0.9:9000',
          screenshotSearchConcurrency: 7,
        ),
      );

      final restored = await store.loadSettings();
      expect(restored.source, MusicDataSource.buguyy);
      expect(restored.language, AppLanguage.en);
      expect(restored.theme, AppThemePreference.light);
      expect(restored.lanLibraryUrl, 'http://10.0.0.9:9000');
      expect(restored.screenshotSearchConcurrency, 7);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('settings store bounds screenshot search concurrency to 1–10', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_concurrency_',
    );
    final file = File('${root.path}${Platform.pathSeparator}settings.json');
    final store = MusicSettingsStore(rootProvider: () async => root);
    try {
      await file.writeAsString('{"screenshotSearchConcurrency":0}');
      expect((await store.loadSettings()).screenshotSearchConcurrency, 1);
      await file.writeAsString('{"screenshotSearchConcurrency":12}');
      expect((await store.loadSettings()).screenshotSearchConcurrency, 10);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('settings store serializes concurrent writes so latest wins', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_race_',
    );
    final store = MusicSettingsStore(rootProvider: () async => root);

    try {
      await Future.wait([
        store.saveSettings(
          const MusicAppSettings(
            source: MusicDataSource.buguyy,
            language: AppLanguage.en,
            theme: AppThemePreference.dark,
          ),
        ),
        store.saveSettings(
          const MusicAppSettings(
            source: MusicDataSource.buguyy,
            language: AppLanguage.en,
            theme: AppThemePreference.light,
          ),
        ),
      ]);

      final restored = await store.loadSettings();
      expect(restored.source, MusicDataSource.buguyy);
      expect(restored.language, AppLanguage.en);
      expect(restored.theme, AppThemePreference.light);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
