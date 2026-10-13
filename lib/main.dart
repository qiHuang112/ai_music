import 'dart:io';

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
import 'src/presentation/design/ambient_backdrop.dart';
import 'src/presentation/design/controls.dart';
import 'src/presentation/design/design_gallery_page.dart';
import 'src/presentation/design/soft_scroll_edge.dart';

const _disableAudioService = bool.fromEnvironment(
  'AI_MUSIC_DISABLE_AUDIO_SERVICE',
);

/// Opens on the design-system gallery instead of the home page.
const _designGallery = bool.fromEnvironment('AI_MUSIC_DESIGN_GALLERY');

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
  final controller = MusicController(audioHandler: audioHandler);
  // Know the saved look before the first frame. Otherwise the app opens in
  // the default dark theme and visibly fades to the user's light one.
  try {
    final saved = await controller.settingsController.load();
    controller
      ..themePreference = saved.theme
      ..language = saved.language;
  } catch (_) {
    // The defaults stand; initialize() reports real settings failures.
  }
  runApp(AiMusicApp(controller: controller));
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
          // The page backdrop swaps whole with the theme; a cross-fade would
          // show it under half-changed colors.
          themeAnimationDuration: Duration.zero,
          scrollBehavior: const SoftEdgeScrollBehavior(),
          theme: MusicAppTheme.create(Brightness.light),
          darkTheme: MusicAppTheme.create(Brightness.dark),
          themeMode: controller.themePreference == AppThemePreference.light
              ? ThemeMode.light
              : ThemeMode.dark,
          builder: (context, child) => AppStringsScope(
            language: controller.language,
            // One backdrop for the whole app, fixed behind every page, so
            // moving between pages changes only what lies on top of it.
            child: Stack(
              fit: StackFit.expand,
              children: [
                const PageBackdrop(),
                DismissKeyboardOnTap(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
          home: _designGallery
              ? _DesignGalleryHome(controller: controller)
              : MusicHomePage(controller: controller),
        );
      },
    );
  }
}

/// Feeds the gallery the cover of whatever is in the player.
class _DesignGalleryHome extends StatelessWidget {
  const _DesignGalleryHome({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.value,
    builder: (context, snapshot) {
      final item = snapshot.data;
      final art = item?.artUri;
      return DesignGalleryPage(
        artwork: art == null
            ? null
            : art.isScheme('file')
            ? FileImage(File(art.toFilePath()))
            : NetworkImage(art.toString()),
        title: item?.title,
        artist: item?.artist,
        onEnterApp: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MusicHomePage(controller: controller),
          ),
        ),
      );
    },
  );
}
