import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../application/music_controller.dart';
import '../data/music_charts.dart';
import '../data/music_playlists.dart';
import '../data/playlist_usage_store.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'design/artwork_palette.dart';
import 'design/glass_surface.dart';
import 'design/record_sleeve.dart';
import 'design/vinyl_disc.dart';
import 'desktop_scope.dart';
import 'desktop_ui.dart';
import 'mini_player.dart';
import 'music_thumbnail.dart';
import 'player_page.dart';

/// The Mac home page when nothing is being searched: what is playing, the
/// favorites, the playlists as sleeves on a shelf, and the charts as tiles.
/// Every card opens the same pages the phone's home list does.
class DesktopHomeDashboard extends StatelessWidget {
  const DesktopHomeDashboard({
    super.key,
    required this.controller,
    required this.onOpenFavorites,
    required this.onOpenPlaylist,
    required this.onOpenLibrary,
    required this.onOpenChart,
  });

  final MusicController controller;
  final VoidCallback onOpenFavorites, onOpenLibrary;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final ValueChanged<MusicChart> onOpenChart;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final hero = _NowPlayingHero(controller: controller);
            final favorites = _FavoritesCard(
              controller: controller,
              onOpen: onOpenFavorites,
            );
            if (!wide) {
              return Column(
                children: [
                  SizedBox(height: 206, child: hero),
                  const SizedBox(height: 16),
                  SizedBox(height: 180, child: favorites),
                ],
              );
            }
            return SizedBox(
              height: 206,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 13, child: hero),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: favorites),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 34),
        _SectionHeader(
          title: strings.isZh ? '常听歌单' : 'Your playlists',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SortToggle(controller: controller),
              const SizedBox(width: 4),
              _TextLink(
                label: strings.isZh ? '全部' : 'See all',
                onTap: onOpenLibrary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlaylistShelf(
          controller: controller,
          onOpen: onOpenPlaylist,
          onEmpty: onOpenLibrary,
        ),
        const SizedBox(height: 34),
        _SectionHeader(title: strings.discover),
        const SizedBox(height: 14),
        _ChartGroup(
          title: strings.qqMusic,
          charts: qqMusicCharts,
          onOpen: onOpenChart,
          hue: 0,
        ),
        const SizedBox(height: 18),
        _ChartGroup(
          title: strings.neteaseMusic,
          charts: neteaseMusicCharts,
          onOpen: onOpenChart,
          hue: 2,
        ),
      ],
    );
  }
}

/// "Good evening", by the clock.
String desktopGreeting(bool zh, [DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (zh) {
    return switch (hour) {
      >= 5 && < 11 => '早上好',
      >= 11 && < 13 => '中午好',
      >= 13 && < 18 => '下午好',
      >= 18 && < 23 => '晚上好',
      _ => '夜深了',
    };
  }
  return switch (hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 18 => 'Good afternoon',
    _ => 'Good evening',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: Text(title, style: DesktopUi.sectionTitle(context))),
      ?trailing,
    ],
  );
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DesktopHover(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: hovered ? 1 : .85),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final zh = AppStringsScope.of(context).isZh;
    final recent =
        controller.playlistSortOrder == PlaylistSortOrder.recentlyOpened;
    return Tooltip(
      message: recent
          ? (zh ? '切换为访问次数（近30天）' : 'Switch to visits (30 days)')
          : (zh ? '切换为最近打开' : 'Switch to recently opened'),
      child: DesktopRow(
        key: const ValueKey('home-playlist-sort'),
        height: 26,
        radius: 13,
        onTap: () => controller.setPlaylistSortOrder(
          recent
              ? PlaylistSortOrder.visitCount
              : PlaylistSortOrder.recentlyOpened,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              recent ? (zh ? '最近打开' : 'Recent') : (zh ? '访问次数' : 'Visits'),
              style: TextStyle(fontSize: 12.5, color: DesktopUi.muted(context)),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.unfold_more_rounded,
              size: 15,
              color: DesktopUi.muted(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass card that lifts a little under the pointer.
class _LiftCard extends StatelessWidget {
  const _LiftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.backdrop,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Widget? backdrop;

  @override
  Widget build(BuildContext context) => DesktopHover(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    builder: (context, hovered) => AnimatedSlide(
      offset: Offset(0, hovered && onTap != null ? -.012 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: GlassSurface(
          level: GlassLevel.thin,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              if (backdrop != null) Positioned.fill(child: backdrop!),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NowPlayingHero extends StatelessWidget {
  const _NowPlayingHero({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.mediaItemStream,
    initialData: controller.audioHandler.mediaItem.value,
    builder: (context, media) => StreamBuilder<PlaybackState>(
      stream: controller.playbackStateStream,
      initialData: controller.audioHandler.playbackState.value,
      builder: (context, state) {
        final item = media.data;
        if (item == null) return _welcome(context);
        return _playing(context, item, state.data?.playing ?? false);
      },
    ),
  );

  Widget _welcome(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    return _LiftCard(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
      child: Row(
        children: [
          const SizedBox.square(dimension: 132, child: VinylDisc()),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(zh ? '来听' : 'LAITING', style: MusicType.eyebrow(context)),
                const SizedBox(height: 10),
                Text(
                  zh ? '今天想听点什么？' : 'What would you like to hear?',
                  style: MusicType.masthead(context, size: 26),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      zh ? '按 ' : 'Press ',
                      style: TextStyle(
                        fontSize: 13,
                        color: DesktopUi.muted(context),
                      ),
                    ),
                    const DesktopKeyCap('⌘K'),
                    Text(
                      zh ? ' 搜索歌曲或歌单' : ' to search songs or playlists',
                      style: TextStyle(
                        fontSize: 13,
                        color: DesktopUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playing(BuildContext context, MediaItem item, bool playing) {
    final uri = item.artUri ?? controller.currentArtworkUri;
    return _LiftCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 28, 24),
      backdrop: uri == null ? null : DesktopArtworkGlow(uri: uri),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _playingRow(context, item, playing, constraints.maxWidth < 440),
      ),
    );
  }

  Widget _playingRow(
    BuildContext context,
    MediaItem item,
    bool playing,
    bool compact,
  ) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final uri = item.artUri ?? controller.currentArtworkUri;
    final desktop = DesktopMusicScope.maybeOf(context);
    final origin = controller.playbackOriginName;
    return Row(
      children: [
        RecordSleeve(
          size: 156,
          reveal: playing ? .36 : .24,
          spinning: playing,
          cover: MusicThumbnail(
            uri: uri,
            label: item.title,
            size: 156,
            radius: 0,
          ),
          label: MusicThumbnail(
            uri: uri,
            label: item.title,
            size: 64,
            radius: 0,
          ),
        ),
        const SizedBox(width: 26),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                playing
                    ? (zh ? '正在播放' : 'NOW PLAYING')
                    : (zh ? '继续收听' : 'CONTINUE'),
                style: MusicType.eyebrow(context),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MusicType.masthead(context, size: 28),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if ((item.artist ?? '').isNotEmpty) item.artist!,
                  if (origin != null) '${zh ? '来自' : 'From'} $origin',
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: DesktopUi.muted(context),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  DesktopPlayButton(
                    playing: playing,
                    tooltip: playing ? strings.pause : strings.play,
                    onPressed: controller.togglePlayPause,
                  ),
                  if (desktop != null) ...[
                    const SizedBox(width: 12),
                    if (compact)
                      DesktopToolButton(
                        icon: Icons.album_rounded,
                        tooltip: zh ? '打开播放页' : 'Open player',
                        size: 34,
                        onPressed: desktop.openPlayer,
                      )
                    else
                      Flexible(
                        child: _PillButton(
                          icon: Icons.album_rounded,
                          label: zh ? '打开播放页' : 'Open player',
                          onTap: desktop.openPlayer,
                        ),
                      ),
                    const SizedBox(width: 8),
                    DesktopToolButton(
                      icon: Icons.lyrics_outlined,
                      tooltip: strings.lyrics,
                      size: 34,
                      onPressed: () => desktop.openDetail(DesktopDetail.lyrics),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The playing cover's own light, washed across the card.
class DesktopArtworkGlow extends StatefulWidget {
  const DesktopArtworkGlow({super.key, required this.uri});

  final Uri uri;

  @override
  State<DesktopArtworkGlow> createState() => _ArtworkGlowState();
}

class _ArtworkGlowState extends State<DesktopArtworkGlow> {
  ArtworkPalette? _palette;
  Uri? _for;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  @override
  void didUpdateWidget(DesktopArtworkGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _read();
  }

  Future<void> _read() async {
    final uri = widget.uri;
    if (_for == uri) return;
    _for = uri;
    final palette = await ArtworkPalette.of(artworkImageProvider(uri));
    if (mounted && _for == uri) setState(() => _palette = palette);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = _palette;
    return AnimatedOpacity(
      opacity: palette == null ? 0 : 1,
      duration: const Duration(milliseconds: 600),
      child: palette == null
          ? const SizedBox.expand()
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-.75, -.2),
                  radius: 1.3,
                  colors: [
                    palette.glow(brightness).withValues(alpha: .38),
                    palette.shade(brightness).withValues(alpha: .14),
                    palette.shade(brightness).withValues(alpha: 0),
                  ],
                  stops: const [0, .5, 1],
                ),
              ),
            ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DesktopHover(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DesktopUi.hover,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            color: colors.onSurface.withValues(alpha: hovered ? .12 : .07),
            border: Border.all(color: colors.onSurface.withValues(alpha: .08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.onSurface),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesCard extends StatelessWidget {
  const _FavoritesCard({required this.controller, required this.onOpen});

  final MusicController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final zh = strings.isZh;
    final tracks = controller.favoriteTracks;
    final covers = [
      for (final track in tracks)
        if (track.artworkUri != null) track,
    ].take(4).toList();
    final colors = Theme.of(context).colorScheme;
    return _LiftCard(
      key: const ValueKey('home-favorites-entry'),
      onTap: onOpen,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                zh ? '我的收藏' : 'FAVORITES',
                style: MusicType.eyebrow(context),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: DesktopUi.muted(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox.square(
                  dimension: 104,
                  child: covers.isEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.favorite_border_rounded,
                            color: colors.primary,
                            size: 36,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: covers.length < 4
                              ? MusicThumbnail(
                                  uri: covers.first.artworkUri,
                                  label: covers.first.title,
                                  size: 104,
                                  radius: 0,
                                )
                              : Column(
                                  children: [
                                    for (final row in [
                                      covers.sublist(0, 2),
                                      covers.sublist(2, 4),
                                    ])
                                      Expanded(
                                        child: Row(
                                          children: [
                                            for (final track in row)
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.cover,
                                                  child: MusicThumbnail(
                                                    uri: track.artworkUri,
                                                    label: track.title,
                                                    size: 52,
                                                    radius: 0,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        tracks.isEmpty
                            ? strings.noFavoritesYet
                            : strings.songCount(tracks.length),
                        style: MusicType.masthead(context, size: 24),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tracks.take(3).map((t) => t.title).join(' / '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: DesktopUi.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({
    required this.controller,
    required this.onOpen,
    required this.onEmpty,
  });

  final MusicController controller;
  final ValueChanged<MusicPlaylist> onOpen;
  final VoidCallback onEmpty;

  @override
  Widget build(BuildContext context) {
    final strings = AppStringsScope.of(context);
    final playlists = controller.frequentlyUsedPlaylists;
    if (playlists.isEmpty) {
      return _LiftCard(
        key: const ValueKey('home-empty-custom-playlists'),
        onTap: onEmpty,
        child: Row(
          children: [
            Icon(
              Icons.playlist_add_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.noCustomPlaylists,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.createPlaylistHomeHint,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: DesktopUi.muted(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return DesktopSleeveGrid(
      maxRows: 2,
      cards: [
        for (final playlist in playlists)
          DesktopSleeveCard(
            key: ValueKey('home-playlist-${playlist.id}'),
            title: playlist.name,
            subtitle: strings.songCount(playlist.entries.length),
            artwork: playlistArtworkUri(controller, playlist),
            onTap: () => onOpen(playlist),
          ),
      ],
    );
  }
}

/// Sleeves on a shelf: as many columns as fit, each at least 150pt wide.
class DesktopSleeveGrid extends StatelessWidget {
  const DesktopSleeveGrid({super.key, required this.cards, this.maxRows});

  final List<Widget> cards;
  final int? maxRows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 26.0;
      final columns = ((constraints.maxWidth + gap) / (150 + gap))
          .floor()
          .clamp(2, 7);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final shown = maxRows == null ? cards : cards.take(columns * maxRows!);
      return Wrap(
        spacing: gap,
        runSpacing: 22,
        children: [
          for (final card in shown) SizedBox(width: width, child: card),
        ],
      );
    },
  );
}

/// A playlist as a square sleeve. Under the pointer its record slides out.
class DesktopSleeveCard extends StatelessWidget {
  const DesktopSleeveCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.onTap,
  });

  final String title, subtitle;
  final Uri? artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DesktopHover(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: MusicMotion.emphasized,
                      left: hovered ? side * .2 : side * .03,
                      top: side * .04,
                      width: side * .92,
                      height: side * .92,
                      child: AnimatedRotation(
                        turns: hovered ? .08 : 0,
                        duration: const Duration(milliseconds: 600),
                        curve: MusicMotion.emphasized,
                        child: VinylDisc(
                          shadow: false,
                          label: MusicThumbnail(
                            uri: artwork,
                            label: title,
                            size: side * .34,
                            radius: 0,
                          ),
                        ),
                      ),
                    ),
                    AnimatedScale(
                      scale: hovered ? 1.015 : 1,
                      duration: const Duration(milliseconds: 220),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            MusicUi.sleeveRadius,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: hovered ? .45 : .3,
                              ),
                              blurRadius: hovered ? 22 : 14,
                              offset: Offset(0, hovered ? 10 : 6),
                            ),
                          ],
                        ),
                        // A solid sleeve: the record stays hidden behind
                        // a cover that is only a placeholder.
                        child: ColoredBox(
                          color: MusicTokens.of(context).panel,
                          child: MusicThumbnail(
                            uri: artwork,
                            label: title,
                            size: side,
                            radius: MusicUi.sleeveRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: DesktopUi.muted(context)),
          ),
        ],
      ),
    ),
  );
}

class _ChartGroup extends StatelessWidget {
  const _ChartGroup({
    required this.title,
    required this.charts,
    required this.onOpen,
    required this.hue,
  });

  final String title;
  final List<MusicChart> charts;
  final ValueChanged<MusicChart> onOpen;
  final int hue;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: DesktopUi.groupLabel(context)),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final columns = ((constraints.maxWidth + gap) / (156 + gap))
              .floor()
              .clamp(2, 8);
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (i, chart) in charts.indexed)
                SizedBox(
                  width: width,
                  child: _ChartTile(
                    key: ValueKey('chart-${chart.platform.name}-${chart.id}'),
                    chart: chart,
                    platform: title,
                    tone: hue + i,
                    onTap: () => onOpen(chart),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// How a chart tile is printed in each skin: its two colors, its lettering
/// and the label of the record in its corner.
class _TileStyle {
  const _TileStyle(
    this.from,
    this.to, {
    required this.text,
    required this.label,
    this.scrim = 0,
    this.border,
    this.shadow,
    this.lamp,
    this.dots,
  });

  final Color from, to, text, label;

  /// Darkens the lower part so light lettering stays legible.
  final double scrim;
  final Border? border;
  final List<BoxShadow>? shadow;

  /// Silver face: the meter lamp lit along the bottom edge.
  final Color? lamp;

  /// Riso: halftone dots printed over the tile in this ink.
  final Color? dots;

  bool get dark => text.computeLuminance() > .5;
}

List<_TileStyle> _tileStyles(MusicPalette p) {
  const white = Colors.white;
  switch (p.skin) {
    case MusicSkin.day:
      // Cream sleeves with a leaf-green, wheat or brick print.
      final border = Border.all(color: p.line);
      final shadow = [
        BoxShadow(
          color: p.text.withValues(alpha: .07),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];
      return [
        _TileStyle(
          const Color(0xFFF4F9EA),
          const Color(0xFFDDEDC4),
          text: const Color(0xFF2F5312),
          label: p.accent,
          border: border,
          shadow: shadow,
        ),
        _TileStyle(
          const Color(0xFFFCF6EA),
          const Color(0xFFF1E1C2),
          text: const Color(0xFF6A4A1C),
          label: const Color(0xFFE2B865),
          border: border,
          shadow: shadow,
        ),
        _TileStyle(
          const Color(0xFFFBF1EA),
          const Color(0xFFF2D8CB),
          text: const Color(0xFF7A3422),
          label: p.label,
          border: border,
          shadow: shadow,
        ),
        _TileStyle(
          const Color(0xFFEFF4EC),
          const Color(0xFFD4E3CF),
          text: const Color(0xFF2E4A37),
          label: const Color(0xFF7FA88A),
          border: border,
          shadow: shadow,
        ),
      ];
    case MusicSkin.berry:
      // Strawberry, custard, lavender and peach milk, with cocoa lettering.
      final shadow = [
        BoxShadow(
          color: const Color(0xFFF06491).withValues(alpha: .16),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
      final border = Border.all(color: Colors.white.withValues(alpha: .7));
      return [
        for (final (from, to, label) in const [
          (Color(0xFFFFE4EB), Color(0xFFFFB3C7), Color(0xFFFF8FAB)),
          (Color(0xFFFFF4DC), Color(0xFFFFDC8F), Color(0xFFFFC85C)),
          (Color(0xFFF1EAFF), Color(0xFFD6C6FF), Color(0xFFB9A0FF)),
          (Color(0xFFFFEDE6), Color(0xFFFFC7B5), Color(0xFFFF9F86)),
        ])
          _TileStyle(
            from,
            to,
            text: p.text,
            label: label,
            border: border,
            shadow: shadow,
          ),
      ];
    case MusicSkin.riso:
      // Cut paper in the two inks, printed solid or as halftone.
      final border = Border.all(color: p.text, width: 1.4);
      final shadow = [BoxShadow(color: p.haze, offset: const Offset(4, 4))];
      final blueShadow = [
        BoxShadow(color: p.accent, offset: const Offset(4, 4)),
      ];
      return [
        _TileStyle(
          p.accent,
          p.accent,
          text: p.panel,
          label: p.haze,
          border: border,
          shadow: shadow,
        ),
        _TileStyle(
          p.panel,
          p.panel,
          text: p.accent,
          label: p.haze,
          border: border,
          shadow: shadow,
          dots: p.haze.withValues(alpha: .55),
        ),
        _TileStyle(
          p.haze,
          p.haze,
          text: p.text,
          label: p.accent,
          border: border,
          shadow: blueShadow,
        ),
        _TileStyle(
          p.panel,
          p.panel,
          text: p.text,
          label: p.accent,
          border: border,
          shadow: blueShadow,
          dots: p.accent.withValues(alpha: .4),
        ),
      ];
    case MusicSkin.aurora:
      // Panes of polar night, each lit by a different curtain.
      final border = Border.all(color: p.sheen.withValues(alpha: .18));
      return [
        for (final (from, to, label) in const [
          (Color(0xFF14544A), Color(0xFF071A22), Color(0xFF5FE3B3)),
          (Color(0xFF2B2468), Color(0xFF081822), Color(0xFF7C5CFF)),
          (Color(0xFF0F4656), Color(0xFF07161D), Color(0xFF7DD3F0)),
          (Color(0xFF4A2350), Color(0xFF0A1A22), Color(0xFFFF8FA3)),
        ])
          _TileStyle(
            from,
            to,
            text: p.text,
            label: label,
            scrim: .2,
            border: border,
            shadow: [
              BoxShadow(
                color: label.withValues(alpha: .18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
      ];
    case MusicSkin.silver:
      // The amplifier's black display windows, each with its lamp.
      final border = Border.all(color: Colors.white.withValues(alpha: .55));
      final shadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: .28),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];
      return [
        for (final lamp in const [
          Color(0xFFFFC773),
          Color(0xFFFF6A2B),
          Color(0xFFFFE2A6),
          Color(0xFFFF8A5C),
        ])
          _TileStyle(
            const Color(0xFF26272A),
            const Color(0xFF0D0E0F),
            text: lamp,
            label: lamp,
            border: border,
            shadow: shadow,
            lamp: lamp,
          ),
      ];
    case MusicSkin.neon || MusicSkin.night:
      final pairs = [
        (p.accent, p.haze),
        (p.haze, p.label),
        (p.label, p.accent),
        (p.accent, p.label),
      ];
      return [
        for (final (from, to) in pairs)
          _TileStyle(
            Color.lerp(from, Colors.black, .12)!,
            Color.lerp(to, Colors.black, .38)!,
            text: white,
            label: Color.lerp(from, Colors.white, .2)!,
            scrim: .28,
          ),
      ];
  }
}

/// A chart as a printed tile with a record edge in its corner, styled by
/// the skin.
class _ChartTile extends StatelessWidget {
  const _ChartTile({
    super.key,
    required this.chart,
    required this.platform,
    required this.tone,
    required this.onTap,
  });

  final MusicChart chart;
  final String platform;
  final int tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = _tileStyles(MusicTokens.of(context));
    final style = styles[tone % styles.length];
    final riso = MusicTokens.of(context).skin == MusicSkin.riso;
    final radius = BorderRadius.circular(riso ? 4 : 14);
    return Semantics(
      button: true,
      label: chart.title,
      child: DesktopHover(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: hovered ? 1.03 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AspectRatio(
              aspectRatio: 1.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: style.shadow,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [style.from, style.to],
                          ),
                        ),
                      ),
                      if (style.dots != null)
                        CustomPaint(painter: _HalftonePainter(style.dots!)),
                      // A record peeking out of the corner.
                      Positioned(
                        right: -38,
                        bottom: -46,
                        width: 110,
                        height: 110,
                        child: AnimatedRotation(
                          turns: hovered ? .12 : 0,
                          duration: const Duration(milliseconds: 700),
                          curve: MusicMotion.emphasized,
                          child: VinylDisc(
                            shadow: false,
                            labelColor: style.label,
                          ),
                        ),
                      ),
                      if (style.scrim > 0)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: style.scrim),
                              ],
                            ),
                          ),
                        ),
                      if (style.lamp != null)
                        Positioned(
                          left: 14,
                          bottom: 9,
                          width: 34,
                          height: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: style.lamp,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: style.lamp!.withValues(alpha: .8),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              platform,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: .4,
                                color: style.text.withValues(alpha: .72),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              chart.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: style.text,
                                shadows: style.dark
                                    ? [
                                        Shadow(
                                          color: Colors.black.withValues(
                                            alpha: .4,
                                          ),
                                          blurRadius: 8,
                                        ),
                                        if (style.lamp != null)
                                          Shadow(
                                            color: style.lamp!.withValues(
                                              alpha: .6,
                                            ),
                                            blurRadius: 10,
                                          ),
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (style.border != null)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: style.border,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Riso: a fan of halftone dots, largest at the top right.
class _HalftonePainter extends CustomPainter {
  const _HalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 7.0;
    final paint = Paint()..color = color;
    for (var y = cell / 2; y < size.height; y += cell) {
      for (var x = cell / 2; x < size.width; x += cell) {
        final reach =
            1 - (Offset(size.width - x, y).distance / (size.width * .9));
        if (reach <= 0) continue;
        canvas.drawCircle(Offset(x, y), cell * .45 * reach, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) => old.color != color;
}
