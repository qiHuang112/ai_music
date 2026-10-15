import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import 'ambient_backdrop.dart';
import 'artwork_palette.dart';
import 'controls.dart';
import 'glass_surface.dart';
import 'record_sleeve.dart';
import 'turntable.dart';
import 'vinyl_disc.dart';

/// Every token and component of the design system on one page, for review on a
/// device. Start the app with `--dart-define=AI_MUSIC_DESIGN_GALLERY=true`.
class DesignGalleryPage extends StatefulWidget {
  const DesignGalleryPage({
    super.key,
    this.artwork,
    this.title,
    this.artist,
    this.onEnterApp,
  });

  /// The cover of the song in the player, when there is one. Without it the
  /// page uses drawn sample sleeves.
  final ImageProvider? artwork;
  final String? title, artist;
  final VoidCallback? onEnterApp;

  @override
  State<DesignGalleryPage> createState() => _DesignGalleryPageState();
}

class _DesignGalleryPageState extends State<DesignGalleryPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position;
  // Follows the app's theme until the toggle is used.
  bool? _chosen;
  bool _playing = false;
  bool _favorite = true;
  int _chip = 0;
  int _sleeve = -1;
  ArtworkPalette? _fromArtwork;

  @override
  void initState() {
    super.initState();
    _position = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
      value: .22,
    );
    _readArtwork();
  }

  @override
  void didUpdateWidget(DesignGalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork != widget.artwork) _readArtwork();
  }

  Future<void> _readArtwork() async {
    final artwork = widget.artwork;
    final palette = artwork == null ? null : await ArtworkPalette.of(artwork);
    if (mounted && artwork == widget.artwork) {
      setState(() => _fromArtwork = palette);
    }
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _position.repeat();
    } else {
      _position.stop();
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  bool get _dark => _chosen ?? Theme.of(context).brightness == Brightness.dark;

  ArtworkPalette? get _light =>
      _sleeve >= 0 ? _DemoCover.palette(_sleeve) : _fromArtwork;

  @override
  Widget build(BuildContext context) {
    final brightness = _dark ? Brightness.dark : Brightness.light;
    return Theme(
      data: MusicAppTheme.create(brightness),
      child: Builder(
        builder: (context) {
          final inset = MediaQuery.paddingOf(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: MusicAppTheme.systemOverlayStyle(brightness),
            child: Scaffold(
              body: AmbientBackdrop(
                glow: _light?.glow(brightness),
                shade: _light?.shade(brightness),
                child: Stack(
                  children: [
                    ListView(
                      padding: EdgeInsets.fromLTRB(
                        MusicUi.pagePadding,
                        inset.top + 12,
                        MusicUi.pagePadding,
                        inset.bottom + 132,
                      ),
                      children: [
                        _header(context),
                        const SizedBox(height: 28),
                        _deck(context),
                        const SizedBox(height: 44),
                        _colors(context),
                        const SizedBox(height: 44),
                        _type(context),
                        const SizedBox(height: 44),
                        _glass(context),
                        const SizedBox(height: 44),
                        _sleeves(context),
                        const SizedBox(height: 44),
                        _controls(context),
                        const SizedBox(height: 44),
                        _rows(context),
                        const SizedBox(height: 44),
                        _shape(context),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: inset.bottom + 10,
                      child: _miniPlayer(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EyebrowLabel('Design system · Vol. 01'),
            const SizedBox(height: 8),
            Text('黑胶 × 玻璃', style: MusicType.masthead(context)),
            const SizedBox(height: 4),
            Text(
              'Vinyl warmth, modern glass.',
              style: MusicType.masthead(context, size: 17).copyWith(
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      if (widget.onEnterApp != null) ...[
        GlassIconButton(
          icon: Icons.arrow_forward_rounded,
          tooltip: '进入应用',
          onPressed: widget.onEnterApp,
        ),
        const SizedBox(width: 10),
      ],
      GlassIconButton(
        icon: _dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        tooltip: _dark ? '浅色' : '深色',
        onPressed: () => setState(() => _chosen = !_dark),
      ),
    ],
  );

  Widget _deck(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sample = _sleeve >= 0 ? _sleeve : 0;
    final useArtwork = _sleeve < 0 && widget.artwork != null;
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AnimatedBuilder(
            animation: _position,
            builder: (context, label) => Turntable(
              playing: _playing,
              labelColor: _light?.label,
              label: label,
            ),
            child: useArtwork
                ? Image(image: widget.artwork!, fit: BoxFit.cover)
                : _DemoCover(sample),
          ),
        ),
        const SizedBox(height: 26),
        EyebrowLabel(_playing ? 'Now spinning' : 'Paused'),
        const SizedBox(height: 8),
        Text(
          useArtwork
              ? widget.title ?? _DemoCover.titles[0]
              : _DemoCover.titles[sample],
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MusicType.masthead(context, size: 28),
        ),
        const SizedBox(height: 4),
        Text(
          useArtwork
              ? widget.artist ?? _DemoCover.artists[0]
              : _DemoCover.artists[sample],
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        AnimatedBuilder(
          animation: _position,
          builder: (context, _) {
            const total = Duration(minutes: 3, seconds: 42);
            final played = total * _position.value;
            return Column(
              children: [
                GrooveSlider(
                  value: _position.value,
                  buffered: .64,
                  semanticLabel: '播放进度',
                  onChanged: (value) => _position.value = value,
                  onChangeEnd: (_) {
                    if (_playing) _position.repeat();
                  },
                ),
                Row(
                  children: [
                    Text(_clock(played), style: MusicType.readout(context)),
                    const Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: QualityBadge('FLAC', highlighted: true),
                        ),
                      ),
                    ),
                    Text(
                      '-${_clock(total - played)}',
                      style: MusicType.readout(context),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIconButton(
                icon: Icons.shuffle_rounded,
                tooltip: '随机',
                onPressed: () {},
              ),
              const SizedBox(width: 14),
              GlassIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                size: 52,
                onPressed: () => _position.value = 0,
              ),
              const SizedBox(width: 18),
              PlayPauseButton(
                playing: _playing,
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _toggle,
              ),
              const SizedBox(width: 18),
              GlassIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                size: 52,
                onPressed: () => _position.value = 0,
              ),
              const SizedBox(width: 14),
              GlassIconButton(
                icon: _favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                tooltip: '收藏',
                selected: _favorite,
                onPressed: () => setState(() => _favorite = !_favorite),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _colors(BuildContext context) {
    final palette = MusicTokens.of(context);
    Widget row(String name, List<(String, Color)> swatches) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (label, color) in swatches)
                Expanded(
                  child: _Swatch(label: label, color: color),
                ),
              for (var i = swatches.length; i < 5; i++) const Spacer(),
            ],
          ),
        ],
      ),
    );
    final fromArt = _light;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Palette', title: '色彩'),
        row('底', [
          ('背景', palette.background),
          ('面板', palette.panel),
          ('输入', palette.field),
          ('选中', palette.tint),
          ('分隔', palette.line),
        ]),
        row('字', [('正文', palette.text), ('次要', palette.muted)]),
        row('光 · 每个模式只有一种亮色', [
          ('主色', palette.accent),
          ('主色字', palette.ink),
          ('标签红', palette.label),
          ('黄铜', palette.brass),
          ('唱片', palette.vinyl),
        ]),
        if (fromArt != null)
          row('封面取色 · 房间的光跟着正在放的唱片', [
            ('主色', fromArt.dominant),
            ('亮色', fromArt.vibrant),
            ('光', fromArt.glow(brightness)),
            ('影', fromArt.shade(brightness)),
            ('标签', fromArt.label),
          ]),
      ],
    );
  }

  Widget _type(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget voice(String name, List<Widget> samples) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: text.bodySmall),
          const SizedBox(height: 8),
          ...samples,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Typography', title: '字体'),
        voice('印刷 · Bodoni 72 · 页面大标题、正在播放的歌名、数字', [
          Text('我的音乐 Now Spinning', style: MusicType.masthead(context)),
          Text(
            'Kind of Blue · 1959',
            style: MusicType.masthead(context, size: 22),
          ),
        ]),
        voice('正文 · 系统字体 · 列表、按钮、说明', [
          Text('陈粒全收录：我不说任由时间涂抹', style: text.titleMedium),
          const SizedBox(height: 2),
          Text('QQ 音乐 · 151 首 · 已下载 96 首', style: text.bodyMedium),
          const SizedBox(height: 2),
          Text('次要说明文字用这一级', style: text.bodySmall),
        ]),
        voice('刻字 · DIN Alternate · 小标签、时间、音质', [
          const EyebrowLabel('Side A · Recently played'),
          const SizedBox(height: 8),
          Text('00:45 / 03:42', style: MusicType.readout(context, size: 20)),
          const SizedBox(height: 8),
          const Row(
            children: [
              QualityBadge('FLAC', highlighted: true),
              SizedBox(width: 6),
              QualityBadge('24bit'),
              SizedBox(width: 6),
              QualityBadge('320K'),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _glass(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Material', title: '烟熏玻璃'),
        const SizedBox(height: 6),
        Text('模糊并提亮背后的内容，再盖一层暖色，顶边带一道高光。', style: text.bodySmall),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              MusicUi.sleeveRadius,
                            ),
                            child: _DemoCover(i + 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                top: 34,
                child: Row(
                  children: [
                    for (final level in GlassLevel.values) ...[
                      Expanded(
                        child: GlassSurface(
                          level: level,
                          borderRadius: BorderRadius.circular(20),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              EyebrowLabel(level.name),
                              const SizedBox(height: 4),
                              Text(
                                const [
                                  '薄 · 按钮',
                                  '中 · 播放条',
                                  '厚 · 弹层',
                                ][level.index],
                                style: text.bodySmall?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (level != GlassLevel.thick) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sleeves(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Sleeve', title: '封套与唱片'),
        const SizedBox(height: 6),
        Text('点一张：唱片滑出来开始转，房间的光换成它的颜色。', style: text.bodySmall),
        const SizedBox(height: 18),
        SizedBox(
          // Room for the sleeve and two lines of text at any text size.
          height: 152 + MediaQuery.textScalerOf(context).scale(44),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(width: 22),
            itemBuilder: (context, index) {
              final active = _sleeve == index;
              return Pressable(
                pressedScale: .97,
                onTap: () => setState(() => _sleeve = active ? -1 : index),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RecordSleeve(
                      size: 132,
                      reveal: active ? .42 : .16,
                      spinning: active,
                      labelColor: _DemoCover.palette(index).label,
                      cover: _DemoCover(index),
                    ),
                    const SizedBox(height: 12),
                    Text(_DemoCover.titles[index], style: text.titleSmall),
                    Text(_DemoCover.artists[index], style: text.bodySmall),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    const chips = ['歌曲', '歌单', '专辑', '歌手'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Controls', title: '控件'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, label) in chips.indexed)
              LabelChip(
                label: label,
                selected: _chip == index,
                onTap: () => setState(() => _chip = index),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放全部'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download_rounded),
              label: const Text('下载'),
            ),
            TextButton(onPressed: () {}, child: const Text('查看全部')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            GlassIconButton(
              icon: Icons.queue_music_rounded,
              tooltip: '队列',
              onPressed: () {},
            ),
            const SizedBox(width: 10),
            GlassIconButton(
              icon: Icons.favorite_rounded,
              tooltip: '收藏',
              selected: true,
              onPressed: () {},
            ),
            const SizedBox(width: 10),
            const GlassIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: '不可用',
              onPressed: null,
            ),
            const SizedBox(width: 22),
            const EqualizerBars(playing: true, size: 22),
            const SizedBox(width: 14),
            const EqualizerBars(playing: false, size: 22),
          ],
        ),
      ],
    );
  }

  Widget _rows(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget track(int index, {bool current = false, String? quality}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: current
                ? EqualizerBars(playing: _playing, size: 16)
                : Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: MusicType.readout(context, size: 13),
                  ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(MusicUi.sleeveRadius),
            child: SizedBox.square(dimension: 48, child: _DemoCover(index)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _DemoCover.titles[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: current ? colors.primary : null,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (quality != null) ...[
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: QualityBadge(quality, highlighted: current),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        _DemoCover.artists[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('3:42', style: MusicType.readout(context)),
          const SizedBox(width: 4),
          Icon(Icons.more_horiz_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Side A',
          title: '歌曲列表',
          trailing: TextButton(onPressed: () {}, child: const Text('全部')),
        ),
        const SizedBox(height: 8),
        track(0, quality: 'FLAC'),
        Divider(indent: 96, color: colors.onSurface.withValues(alpha: .08)),
        track(1, current: true, quality: '24bit'),
        Divider(indent: 96, color: colors.onSurface.withValues(alpha: .08)),
        track(2),
      ],
    );
  }

  Widget _shape(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget corner(String name, double radius) => Expanded(
      child: Column(
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: colors.onSurface.withValues(alpha: .14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Shape & motion', title: '形状与动效'),
        const SizedBox(height: 6),
        Text('印刷品是方的，玻璃和金属是圆的。按压回弹用弹簧，唱片起停带惯性。', style: text.bodySmall),
        const SizedBox(height: 16),
        Row(
          children: [
            corner('封套 6', MusicUi.sleeveRadius),
            const SizedBox(width: 12),
            corner('控件 14', MusicUi.controlRadius),
            const SizedBox(width: 12),
            corner('玻璃 28', MusicUi.glassRadius),
            const SizedBox(width: 12),
            corner('按钮 全圆', 32),
          ],
        ),
      ],
    );
  }

  Widget _miniPlayer(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sample = _sleeve >= 0 ? _sleeve : 0;
    final useArtwork = _sleeve < 0 && widget.artwork != null;
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 52,
            child: SpinningVinyl(
              spinning: _playing,
              shadow: false,
              labelColor: _light?.label,
              label: useArtwork
                  ? Image(image: widget.artwork!, fit: BoxFit.cover)
                  : _DemoCover(sample),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  useArtwork
                      ? widget.title ?? _DemoCover.titles[0]
                      : _DemoCover.titles[sample],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  useArtwork
                      ? widget.artist ?? _DemoCover.artists[0]
                      : _DemoCover.artists[sample],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          PlayPauseButton(
            playing: _playing,
            tooltip: _playing ? '暂停' : '播放',
            size: 46,
            onPressed: _toggle,
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: '下一首',
            blur: false,
            onPressed: () => _position.value = 0,
          ),
        ],
      ),
    );
  }

  static String _clock(Duration time) {
    final seconds = time.inSeconds.clamp(0, 5999);
    return '${'${seconds ~/ 60}'.padLeft(2, '0')}:'
        '${'${seconds % 60}'.padLeft(2, '0')}';
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(MusicUi.controlRadius),
              border: Border.all(
                color: colors.onSurface.withValues(alpha: .14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurface),
          ),
          Text(hex, maxLines: 1, style: MusicType.readout(context, size: 10)),
        ],
      ),
    );
  }
}

/// Sample cover art drawn in code, in the flat geometric manner of old jazz
/// sleeves, so the gallery needs no image assets.
class _DemoCover extends StatelessWidget {
  const _DemoCover(this.index);

  final int index;

  static const titles = ['夜航', 'Blue Hour', '旧唱机', 'Round Midnight', '南方来信'];
  static const artists = [
    '示例乐队',
    'The Quiet Five',
    '林间',
    'M. Davis Trio',
    '海岸线',
  ];

  static const _ways = <List<Color>>[
    [Color(0xFF1F3A5F), Color(0xFFE8A33D), Color(0xFFF4EDE0)],
    [Color(0xFF8A2A1F), Color(0xFFF2C879), Color(0xFF14110F)],
    [Color(0xFF2F4B3A), Color(0xFFD9573C), Color(0xFFF4EDE0)],
    [Color(0xFF3B2A4D), Color(0xFFCDB98F), Color(0xFFE8A33D)],
    [Color(0xFF0F4C5C), Color(0xFFF4EDE0), Color(0xFFD9573C)],
  ];

  static ArtworkPalette palette(int index) {
    final way = _ways[index % _ways.length];
    return ArtworkPalette(dominant: way[0], vibrant: way[1]);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DemoCoverPainter(_ways[index % _ways.length], index % 5),
    size: Size.infinite,
  );
}

class _DemoCoverPainter extends CustomPainter {
  const _DemoCoverPainter(this.way, this.layout);

  final List<Color> way;
  final int layout;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final side = size.shortestSide;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(rect, Paint()..color = way[0]);
    final shape = Paint()..color = way[1];
    final mark = Paint()..color = way[2];
    switch (layout) {
      case 0:
        canvas
          ..drawCircle(Offset(side * .66, side * .40), side * .30, shape)
          ..drawRect(
            Rect.fromLTWH(side * .10, side * .74, side * .46, side * .05),
            mark,
          );
      case 1:
        canvas
          ..drawRect(Rect.fromLTWH(0, side * .58, side, side * .42), shape)
          ..drawCircle(Offset(side * .30, side * .58), side * .17, mark);
      case 2:
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH(
              side * (.12 + i * .20),
              side * .14,
              side * .11,
              side * .72,
            ),
            i == 2 ? shape : mark,
          );
        }
      case 3:
        canvas
          ..drawCircle(Offset(side * .5, side * .5), side * .36, shape)
          ..drawCircle(
            Offset(side * .5, side * .5),
            side * .20,
            Paint()..color = way[0],
          )
          ..drawCircle(Offset(side * .5, side * .5), side * .07, mark);
      default:
        canvas
          ..drawPath(
            Path()
              ..moveTo(0, side)
              ..lineTo(side, side * .30)
              ..lineTo(side, side)
              ..close(),
            shape,
          )
          ..drawCircle(Offset(side * .26, side * .30), side * .10, mark);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DemoCoverPainter old) =>
      old.way != way || old.layout != layout;
}
