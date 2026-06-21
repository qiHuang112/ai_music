import 'dart:io';

import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings store migrates legacy source text to buguyy', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai_music_settings_old_',
    );
    final file = File('${root.path}${Platform.pathSeparator}settings.json');
    await file.writeAsString('flac');
    final store = MusicSettingsStore(rootProvider: () async => root);

    try {
      final settings = await store.loadSettings();

      expect(settings.source, MusicDataSource.buguyy);
      expect(settings.language, AppLanguage.zh);
      expect(settings.theme, AppThemePreference.dark);
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
        ),
      );

      final restored = await store.loadSettings();
      expect(restored.source, MusicDataSource.buguyy);
      expect(restored.language, AppLanguage.en);
      expect(restored.theme, AppThemePreference.light);
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
