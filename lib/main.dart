import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'src/data/operation_log.dart';

import 'src/application/music_controller.dart';
import 'src/domain/app_brand.dart';
import 'src/data/music_settings.dart';
import 'src/platform/platform_detection.dart';
import 'src/presentation/app_localizations.dart';
import 'src/playback/music_audio_handler.dart';
import 'src/presentation/music_home_page.dart';
import 'src/presentation/app_theme.dart';

const _disableAudioService = bool.fromEnvironment(
  'AI_MUSIC_DISABLE_AUDIO_SERVICE',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OperationLog.instance = OperationLog();
  OperationLog.event('app.start');
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    OperationLog.event('app.flutter_error', {
      'error': details.exceptionAsString(),
      'stack': details.stack?.toString(),
    });
    previousFlutterError?.call(details);
  };
  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    OperationLog.event('app.async_error', {
      'error': error.toString(),
      'stack': stack.toString(),
    });
    return previousPlatformError?.call(error, stack) ?? false;
  };
  final audioHandler = await _createAudioHandler();
  await audioHandler.configure();
  runApp(AiMusicApp(controller: MusicController(audioHandler: audioHandler)));
}

Future<MusicAudioHandler> _createAudioHandler() async {
  // HarmonyOS does not ship the audio_service platform service used by Android.
  // Keep playback in the foreground handler and let just_audio_harmonyos own the
  // native media session instead.
  if (_disableAudioService || isOpenHarmonyPlatform) {
    return MusicAudioHandler();
  }

  try {
    return await AudioService.init<MusicAudioHandler>(
      builder: MusicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.qi.ai.music.channel.audio',
        androidNotificationChannelName: AppBrand.playbackChannel,
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
        return MaterialApp(
          title: AppBrand.name,
          debugShowCheckedModeBanner: false,
          theme: MusicAppTheme.create(Brightness.light),
          darkTheme: MusicAppTheme.create(Brightness.dark),
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
