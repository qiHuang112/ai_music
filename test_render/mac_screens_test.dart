// Offscreen renders of the Mac window, for design review only. Not part of
// the regular test suite (it lives outside test/). It loads macOS system
// fonts, so it runs on a Mac. Run:
//   SKIN=neon OUT=/tmp/mac-render ONLY=home,playlist \
//     flutter test --no-pub \
//     --dart-define=AI_MUSIC_SUPPORT_DIR=/tmp/mac-render/support \
//     test_render/mac_screens_test.dart
// SKIN is a theme name (light, dark, neon, berry, riso, aurora, silver); ONLY
// limits which screens are written. Without AI_MUSIC_SUPPORT_DIR the app
// falls back to ~/.ai_music for its small preference files.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ai_music/src/application/music_controller.dart';
import 'package:ai_music/src/application/music_mappers.dart';
import 'package:ai_music/src/data/lyrics_artwork.dart';
import 'package:ai_music/src/data/music_cache.dart';
import 'package:ai_music/src/data/music_playlists.dart';
import 'package:ai_music/src/data/music_resolver.dart';
import 'package:ai_music/src/data/music_settings.dart';
import 'package:ai_music/src/data/song_search_cache.dart';
import 'package:ai_music/src/domain/music_models.dart';
import 'package:ai_music/src/playback/music_audio_handler.dart';
import 'package:ai_music/src/presentation/app_localizations.dart';
import 'package:ai_music/src/presentation/app_theme.dart';
import 'package:ai_music/src/presentation/design/ambient_backdrop.dart';
import 'package:ai_music/src/presentation/desktop_home.dart';
import 'package:ai_music/src/presentation/desktop_music_shell.dart';
import 'package:ai_music/src/presentation/desktop_scope.dart';
import 'package:ai_music/src/presentation/desktop_window.dart';
import 'package:ai_music/src/presentation/music_home_page.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/memory_download_history.dart';

const _songs = [
  ('晴天', '周杰伦', '叶惠美'),
  ('夜曲', '周杰伦', '十一月的萧邦'),
  ('大城小爱', '王力宏', '盖世英雄'),
  ('Hello', 'Adele', '25'),
  ('富士山下', '陈奕迅', 'What\'s Going On…?'),
  ('后来', '刘若英', '我等你'),
  ('Blinding Lights', 'The Weeknd', 'After Hours'),
  ('小幸运', '田馥甄', '我的少女时代'),
  ('稻香', '周杰伦', '魔杰座'),
  ('Shape of You', 'Ed Sheeran', '÷'),
  ('平凡之路', '朴树', '猎户星座'),
  ('光年之外', '邓紫棋', '光年之外'),
];

const _palettes = [
  [Color(0xFF1D2B64), Color(0xFFF8CDDA)],
  [Color(0xFF0F2027), Color(0xFF2C5364)],
  [Color(0xFFB24592), Color(0xFFF15F79)],
  [Color(0xFF232526), Color(0xFF8E9EAB)],
  [Color(0xFF355C7D), Color(0xFFF67280)],
  [Color(0xFFDAE2F8), Color(0xFFD6A4A4)],
  [Color(0xFF8E0E00), Color(0xFF1F1C18)],
  [Color(0xFFFFE259), Color(0xFFFFA751)],
  [Color(0xFF56AB2F), Color(0xFFA8E063)],
  [Color(0xFF00B4DB), Color(0xFF0083B0)],
  [Color(0xFF3A1C71), Color(0xFFFFAF7B)],
  [Color(0xFF141E30), Color(0xFF243B55)],
];

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File(file).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const cjk = '/System/Library/Fonts/Hiragino Sans GB.ttc';
  for (final family in [
    'Roboto',
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'PingFang SC',
    '.SF NS',
    'SF Pro Text',
    'SF Pro Display',
    'MaterialIcons',
  ]) {
    if (family == 'MaterialIcons') continue;
    await load(family, [cjk]);
  }
  await load('Bodoni 72', ['/System/Library/Fonts/Supplemental/Bodoni 72.ttc']);
  await load('Didot', ['/System/Library/Fonts/Supplemental/Bodoni 72.ttc']);
  await load('DIN Alternate', [
    '/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf',
  ]);
  // Material icons ship with the Flutter SDK.
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/development/flutter';
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

Future<File> _cover(Directory dir, int i) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const side = 400.0;
  final rect = const Rect.fromLTWH(0, 0, side, side);
  final colors = _palettes[i % _palettes.length];
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect),
  );
  final random = math.Random(i * 7 + 1);
  for (var k = 0; k < 4; k++) {
    canvas.drawCircle(
      Offset(random.nextDouble() * side, random.nextDouble() * side),
      40 + random.nextDouble() * 120,
      Paint()
        ..color = Colors.white.withValues(
          alpha: .08 + random.nextDouble() * .14,
        ),
    );
  }
  canvas.drawRect(
    Rect.fromLTWH(30, side - 70, 120 + random.nextDouble() * 160, 8),
    Paint()..color = Colors.white.withValues(alpha: .7),
  );
  final image = await recorder.endRecording().toImage(
    side.toInt(),
    side.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/cover-$i.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

void main() {
  testWidgets('render mac screens', (tester) async {
    final out = Directory(
      Platform.environment['OUT'] ?? '${Directory.systemTemp.path}/mac-render',
    )..createSync(recursive: true);
    final skin = AppThemePreference.values.firstWhere(
      (p) => p.name == (Platform.environment['SKIN'] ?? 'neon'),
    );
    final onlyEnv = Platform.environment['ONLY'] ?? '';
    final only = onlyEnv.isEmpty ? null : onlyEnv.split(',');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const size = Size(1100, 780);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late List<CachedTrack> cached;
    late Directory dir;
    await tester.runAsync(() async {
      await _loadFonts();
      dir = await Directory.systemTemp.createTemp('mac_render_');
      cached = [
        for (final (i, (title, artist, album)) in _songs.indexed)
          await _cover(dir, i).then((file) async {
            final audio = await File(
              '${dir.path}/$i.mp3',
            ).open(mode: FileMode.write);
            await audio.truncate(4200000 + i * 310000);
            await audio.close();
            final music = ResolvedMusic(
              query: title,
              source: MusicDataSource.buguyy,
              platform: 'buguyy',
              id: 'song-$i',
              name: title,
              artist: artist,
              album: album,
              url: 'https://cdn.example.test/$i.mp3',
              quality: const MusicQuality(format: 'mp3', bitrate: '320'),
              coverUrl: file.uri.toString(),
            );
            return CachedTrack(
              cacheId: cacheIdForResolved(music),
              music: music,
              filePath: '${dir.path}/$i.mp3',
              sizeBytes: 4200000 + i * 310000,
              fromCache: true,
              cachedAt: DateTime(2026, 10, 20 - i ~/ 3, 21, i * 3),
            );
          }),
      ];
    });
    final ids = [for (final c in cached) c.cacheId];
    final now = DateTime(2026, 10, 25);
    final library = PlaylistLibrary(
      favoriteTrackIds: ids.sublist(0, 9),
      playlists: [
        MusicPlaylist(
          id: 'p1',
          name: '深夜电台',
          trackIds: [ids[1], ids[4], ids[5], ids[7], ids[10]],
          createdAt: now,
          updatedAt: now,
          hasBeenOpened: true,
        ),
        MusicPlaylist(
          id: 'p2',
          name: '周末通勤',
          trackIds: [ids[2], ids[6], ids[9], ids[11]],
          createdAt: now,
          updatedAt: now,
          hasBeenOpened: true,
        ),
        MusicPlaylist(
          id: 'p3',
          name: '华语经典',
          trackIds: [ids[0], ids[2], ids[8], ids[10], ids[5]],
          createdAt: now,
          updatedAt: now,
          hasBeenOpened: true,
        ),
        MusicPlaylist(
          id: 'p4',
          name: 'Workout Mix',
          trackIds: [ids[6], ids[9], ids[3]],
          createdAt: now,
          updatedAt: now,
          hasBeenOpened: true,
        ),
      ],
    );

    final handler = _Handler();
    final controller = MusicController(
      songSearchCache: SongSearchCache.memory(),
      downloadHistoryStore: MemoryDownloadHistory(),
      connectivityChanges: const Stream.empty(),
      audioHandler: handler,
      resolver: _Resolver(),
      cacheStore: _CacheStore(cached),
      playlistStore: _PlaylistStore(library),
      settingsStore: _SettingsStore(skin),
      metadataRepository: _Metadata(),
    );
    await controller.initialize();
    final tracks = [for (final c in cached) trackFromCached(c)];
    var played = 'pending';
    controller
        .playTrack(
          tracks[2].copyWith(duration: const Duration(minutes: 4, seconds: 12)),
          playlistId: favoritePlaylistId,
        )
        .then((_) => played = 'done', onError: (Object e) => played = '$e');
    for (var i = 0; i < 40 && played == 'pending'; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (handler.mediaItem.value == null) {
      final favorites = [
        for (final id in ids.sublist(0, 9)) tracks[ids.indexOf(id)],
      ];
      handler.queue.add([for (final t in favorites) mediaItemFromTrack(t)]);
      handler.mediaItem.add(
        mediaItemFromTrack(
          tracks[2].copyWith(duration: const Duration(minutes: 4, seconds: 12)),
        ),
      );
    }
    handler.position = const Duration(minutes: 1, seconds: 44);
    handler.playbackState.add(
      handler.playbackState.value.copyWith(
        playing: true,
        bufferedPosition: const Duration(minutes: 3),
      ),
    );
    await tester.runAsync(() async {
      for (final c in cached) {
        await precacheImage(
          FileImage(File(Uri.parse(c.music.coverUrl).toFilePath())),
          tester.binding.rootElement!,
        );
      }
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            theme: MusicAppTheme.create(
              Brightness.light,
              palette: skin.isDark ? null : MusicPalette.of(skin),
            ),
            darkTheme: MusicAppTheme.create(
              Brightness.dark,
              palette: skin.isDark ? MusicPalette.of(skin) : null,
            ),
            themeMode: skin.isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => AppStringsScope(
              language: AppLanguage.zh,
              child: Stack(
                fit: StackFit.expand,
                children: [const PageBackdrop(), child!],
              ),
            ),
            home: MusicHomePage(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> shot(String name) async {
      if (only != null && !only.contains(name)) return;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 150)),
        );
      }
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${out.path}/${skin.name}-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    DesktopMusicShellState shell() =>
        tester.state<DesktopMusicShellState>(find.byType(DesktopMusicShell));
    await shot('home');
    if (Platform.environment['SWEEP'] != null) {
      // Moves a mouse across the sidebar and the cards, one frame at a time,
      // and keeps every frame: a flicker shows as a jump between them.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(60, 120));
      for (var i = 0; i < 40; i++) {
        await mouse.moveTo(Offset(60 + i * 22.0, 120 + (i % 10) * 40.0));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: .5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${out.path}/sweep-${i.toString().padLeft(2, '0')}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await mouse.removePointer();
    }
    if (only == null || only.contains('discover')) {
      await tester.drag(
        find.byType(DesktopHomeDashboard),
        const Offset(0, -700),
      );
      await shot('discover');
      await tester.drag(
        find.byType(DesktopHomeDashboard),
        const Offset(0, 700),
      );
    }
    shell().selectSection('library');
    await shot('library');
    shell().selectSection('playlist:$favoritePlaylistId');
    await shot('favorites');
    shell().selectSection('playlist:p1');
    await shot('playlist');
    shell().selectSection('downloads');
    await shot('downloads');
    shell().selectSection('settings');
    await shot('settings');
    shell().selectSection('home');
    final scope = DesktopMusicScope.maybeOf(
      tester.element(find.byType(DesktopPlaybackBar)),
    )!;
    scope.openDetail(DesktopDetail.lyrics);
    await tester.pump();
    await shot('lyrics');
    scope.openDetail(DesktopDetail.queue);
    await shot('queue');
    scope.openDetail(DesktopDetail.queue);
    scope.openPlayer();
    await shot('player');

    // The mini player, at the sizes the window takes for it.
    if (only == null || only.any((name) => name.startsWith('mini'))) {
      scope.openDetail(DesktopDetail.queue);
      await tester.pump();
      tester.view.physicalSize = DesktopWindow.miniStrip * 2;
      unawaited(shell().toggleMini());
      await tester.pump();
      await shot('mini-strip');
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(200, 20));
      await shot('mini-strip-hover');
      // 词 opens the square with the lyrics.
      await tester.tap(find.byKey(const ValueKey('mini-lyrics')));
      tester.view.physicalSize = DesktopWindow.miniSquare * 2;
      await pointer.moveTo(const Offset(-50, -50));
      await shot('mini-lyrics');
      await pointer.moveTo(const Offset(170, 170));
      await shot('mini-lyrics-hover');
      await tester.tap(find.byKey(const ValueKey('mini-lyrics')));
      await pointer.moveTo(const Offset(-50, -50));
      await shot('mini-cover');
      await pointer.moveTo(const Offset(170, 170));
      await shot('mini-cover-hover');
      await pointer.removePointer();
      await tester.tap(find.byKey(const ValueKey('mini-lyrics')));
      unawaited(shell().toggleMini());
      await tester.pump();
      tester.view.physicalSize = size * 2;
      await tester.pump();
    }

    // The smallest window the Mac app allows.
    tester.view.physicalSize = const Size(760, 600) * 2;
    scope.openDetail(DesktopDetail.queue);
    await shot('narrow-player');
    final closer = find.byTooltip('收起（Esc）');
    if (closer.evaluate().isNotEmpty) await tester.tap(closer.first);
    await shot('narrow-queue');
    shell().selectSection('playlist:p1');
    await shot('narrow-playlist');
    shell().selectSection('home');
    scope.openDetail(DesktopDetail.queue);
    await shot('narrow-home');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Handler extends MusicAudioHandler {
  Duration position = Duration.zero;
  final positions = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Duration get currentPosition => position;

  @override
  Duration get currentBufferedPosition => playbackState.value.bufferedPosition;

  @override
  Future<void> loadQueue(
    List<PlayableAudio> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
  }) async {
    queue.add(items.map((item) => item.mediaItem).toList(growable: false));
    if (items.isNotEmpty) mediaItem.add(items[initialIndex].mediaItem);
  }

  @override
  Future<void> play() async =>
      playbackState.add(playbackState.value.copyWith(playing: true));

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Future<void> restoreCurrentItemPosition(String id, Duration p) async {}
}

class _Metadata extends TrackMetadataRepository {
  @override
  Future<Uri?> cachedArtwork(CachedTrack track) async => null;

  static const _lyrics = '''
[00:00.00]大城小爱 - 王力宏
[00:20.00]Baby 你就是我的唯一
[00:26.00]两个世界都变形
[00:31.00]回去谈何容易
[00:37.00]确定 你就是我的唯一
[00:43.00]独自对着电脑说我爱你
[00:48.00]你知道我在等你吗
[01:40.00]黄色的路灯 照亮了我们
[01:44.00]走过的城市每一个角落
[01:50.00]我想你 不在我身边的时候
[01:56.00]总有一个地方会想起你
[02:02.00]大城小爱 在这里
''';

  @override
  Future<TrackMetadata> load(CachedTrack track) async => TrackMetadata(
    lyricsStatus: LyricsStatus.available,
    lyrics: parseLrcLines(_lyrics),
  );

  @override
  Future<TrackMetadata> upgradeTimedLyrics(CachedTrack track) => load(track);
}

class _CacheStore extends CachedTrackStore {
  _CacheStore(this.cached);
  final List<CachedTrack> cached;

  @override
  Future<Map<String, ({int bytes, int? total})>> partialProgress() async => {};

  @override
  Future<List<CachedTrack>> listCached() async => cached;

  @override
  Future<void> cleanupTemporaryFiles() async {}
}

class _PlaylistStore extends PlaylistStore {
  _PlaylistStore(this.library) : super(rootProvider: _root);
  final PlaylistLibrary library;

  @override
  Future<PlaylistLibrary> load({Set<String>? validTrackIds}) async => library;

  @override
  Future<void> write(
    PlaylistLibrary library, {
    Set<String>? validTrackIds,
  }) async {}
}

Future<Directory> _root() =>
    Directory.systemTemp.createTemp('mac_render_root_');

class _SettingsStore implements MusicSettingsStore {
  _SettingsStore(this.theme);
  final AppThemePreference theme;

  @override
  Future<MusicAppSettings> loadSettings() async =>
      MusicAppSettings(theme: theme);

  @override
  Future<void> saveSettings(MusicAppSettings settings) async {}

  @override
  Future<MusicDataSource> loadSource() async => MusicDataSource.auto;

  @override
  Future<void> saveSource(MusicDataSource source) async {}
}

class _Resolver implements MusicResolver {
  @override
  Future<List<MusicSearchCandidate>> search(
    String q,
    MusicDataSource s,
  ) async => const [];

  @override
  Future<ResolvedMusic> resolve(MusicSearchCandidate candidate) =>
      throw UnimplementedError();
}
