import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/data/library_repository.dart';
import '../features/player/data/music_audio_handler.dart';
import '../features/source_import/data/lan_music_source_client.dart';

const emulatorMusicSourceUrl = 'http://10.0.2.2:8787/api/tracks';
const lanMusicSourceUrl = 'http://192.168.31.57:8787/api/tracks';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
});

final sourceCandidateUrisProvider = Provider<List<Uri>>((ref) {
  const configured = String.fromEnvironment('MUSIC_SOURCE_URL');
  return [
    if (configured.isNotEmpty) Uri.parse(configured),
    Uri.parse(emulatorMusicSourceUrl),
    Uri.parse(lanMusicSourceUrl),
  ];
});

final lanMusicSourceClientProvider = Provider<LanMusicSourceClient>((ref) {
  return LanMusicSourceClient(ref.watch(dioProvider));
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(dioProvider));
});

final musicAudioHandlerProvider = Provider<MusicAudioHandler>((ref) {
  throw StateError('MusicAudioHandler must be provided at app bootstrap.');
});
