import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/player/data/music_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());

  final audioHandler = await AudioService.init<MusicAudioHandler>(
    builder: MusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.qi.ai.music.playback',
      androidNotificationChannelName: 'AI Music Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [musicAudioHandlerProvider.overrideWithValue(audioHandler)],
      child: const MusicApp(),
    ),
  );
}

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'AI Music',
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
