import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/application/music_controller.dart';
import 'src/data/music_settings.dart';
import 'src/presentation/app_localizations.dart';
import 'src/playback/music_audio_handler.dart';
import 'src/presentation/music_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await _createAudioHandler();
  await audioHandler.configure();
  runApp(AiMusicApp(controller: MusicController(audioHandler: audioHandler)));
}

Future<MusicAudioHandler> _createAudioHandler() async {
  try {
    return await AudioService.init<MusicAudioHandler>(
      builder: MusicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.qi.ai.music.channel.audio',
        androidNotificationChannelName: 'AI Music playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
  } on MissingPluginException {
    return MusicAudioHandler();
  }
}

class AiMusicApp extends StatelessWidget {
  const AiMusicApp({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final strings = AppStrings(controller.language);
        return MaterialApp(
          title: strings.appTitle,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0D9488),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0D9488),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: controller.themePreference == AppThemePreference.light
              ? ThemeMode.light
              : ThemeMode.dark,
          builder: (context, child) => AppStringsScope(
            language: controller.language,
            child: child ?? const SizedBox.shrink(),
          ),
          home: MusicHomePage(controller: controller),
        );
      },
    );
  }
}
