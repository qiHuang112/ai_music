import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_theme.dart';
import 'ambient_clock.dart';
import 'paper_texture.dart';

/// The room behind everything: the page color, two slow pools of light and a
/// veil of film grain. Pass colors from [ArtworkPalette] to light it from the
/// playing record; without them it takes the palette's accent and haze.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.glow,
    this.shade,
    this.drift = true,
    this.grain = true,
    this.child,
  });

  final Color? glow, shade;

  /// Whether the light wanders. Leave it off behind long lists.
  final bool drift;
  final bool grain;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = MusicTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: glow ?? palette.accent),
      duration: const Duration(milliseconds: 900),
      curve: MusicMotion.standard,
      builder: (context, glow, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: shade ?? palette.haze),
        duration: const Duration(milliseconds: 900),
        curve: MusicMotion.standard,
        builder: (context, shade, _) => _Drift(
          enabled: drift,
          // The lights repaint as they wander; kept apart, they do not drag
          // the page in front of them into every repaint.
          builder: (phase) => Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AmbientPainter(
                      phase: phase,
                      base: palette.background,
                      glow: glow!,
                      shade: shade!,
                      ember: palette.accent,
                      dark: dark,
                      palette: palette,
                    ),
                  ),
                ),
              ),
              if (grain)
                Positioned.fill(
                  child: IgnorePointer(
                    child: FilmGrain(opacity: dark ? .075 : .05),
                  ),
                ),
              if (palette.neon)
                const Positioned.fill(child: IgnorePointer(child: NeonRain())),
              if (palette.skin == MusicSkin.aurora)
                const Positioned.fill(
                  child: IgnorePointer(child: AuroraLights()),
                ),
              if (child != null) RepaintBoundary(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints what lies behind a page, as if the canvas were the whole screen:
/// by day cream xuan paper, by night the room's amber and red light.
void paintPageBackdrop(
  Canvas canvas,
  Size screen,
  MusicPalette palette, {
  required bool dark,
}) {
  if (palette.skin == MusicSkin.day) {
    canvas.drawRect(Offset.zero & screen, Paint()..color = palette.background);
    PaperTexture.paintOn(canvas, screen);
    return;
  }
  _AmbientPainter(
    phase: const AlwaysStoppedAnimation(0),
    base: palette.background,
    glow: palette.skin == MusicSkin.berry
        ? const Color(0xFFFF9EBB)
        : palette.accent,
    shade: palette.haze,
    ember: palette.accent,
    dark: dark,
    palette: palette,
    // Behind lists the lights are held back.
    k: palette.skin == MusicSkin.neon || palette.skin == MusicSkin.aurora
        ? .5
        : 1,
  ).paint(canvas, screen);
}

/// The background of every pushed page. It sits behind the page's content,
/// so buttons and covers on top of it keep their own solid colors.
class PageBackdrop extends StatelessWidget {
  const PageBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _PagePainter(MusicTokens.of(context), dark)),
          if (dark) const FilmGrain(opacity: .075),
          // Under a page that brings its own backdrop nobody can see these,
          // but they would still be drawn on every frame.
          ValueListenableBuilder(
            valueListenable: _covers,
            builder: (context, covers, _) => covers > 0
                ? const SizedBox.shrink()
                : switch (MusicTokens.of(context).skin) {
                    MusicSkin.neon => const NeonRain(),
                    MusicSkin.aurora => const AuroraLights(k: .5),
                    _ => const SizedBox.shrink(),
                  },
          ),
        ],
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  const _PagePainter(this.palette, this.dark);

  final MusicPalette palette;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPageBackdrop(canvas, size, palette, dark: dark);

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.palette != palette || old.dark != dark;
}

/// A piece of the page backdrop for a bar that stays put while content
/// scrolls under it. It paints the part of the backdrop that lies behind
/// itself, so the bar hides the content without showing as a flat band.
class BackdropSlice extends StatelessWidget {
  const BackdropSlice({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => _BackdropSliceBox(
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        // The same grain the page has, or the bar would read as a darker band.
        if (Theme.of(context).brightness == Brightness.dark)
          const Positioned.fill(
            child: IgnorePointer(child: FilmGrain(opacity: .075)),
          ),
        child ?? const SizedBox.shrink(),
      ],
    ),
  );
}

class _BackdropSliceBox extends SingleChildRenderObjectWidget {
  const _BackdropSliceBox({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBackdropSlice(
    MusicTokens.of(context),
    Theme.of(context).brightness == Brightness.dark,
    MediaQuery.sizeOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderBackdropSlice)
      ..palette = MusicTokens.of(context)
      ..dark = Theme.of(context).brightness == Brightness.dark
      ..screen = MediaQuery.sizeOf(context)
      ..markNeedsPaint();
  }
}

/// Marks a page's own area; [BackdropSlice] places itself against it.
class BackdropScope extends SingleChildRenderObjectWidget {
  const BackdropScope({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropScope();
}

class _RenderBackdropScope extends RenderProxyBox {}

class _RenderBackdropSlice extends RenderProxyBox {
  _RenderBackdropSlice(this.palette, this.dark, this.screen);

  MusicPalette palette;
  bool dark;
  Size screen;

  void _tick() {
    if (palette.skin == MusicSkin.aurora) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _skyClock.addListener(_tick);
  }

  @override
  void detach() {
    _skyClock.removeListener(_tick);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Measured within the page, not the screen: a page sliding in during a
    // route transition must not shift which part of the backdrop this shows.
    RenderObject? page = parent;
    while (page != null && page is! _RenderBackdropScope) {
      page = page.parent;
    }
    final origin = localToGlobal(Offset.zero, ancestor: page);
    context.canvas
      ..save()
      ..clipRect(offset & size)
      ..translate(offset.dx - origin.dx, offset.dy - origin.dy);
    paintPageBackdrop(context.canvas, screen, palette, dark: dark);
    if (palette.skin == MusicSkin.aurora) {
      _paintAuroraLights(context.canvas, screen, .5, _skyClock.value);
    }
    context.canvas.restore();
    super.paint(context, offset);
  }
}

/// How many pages with an [AmbientBackdrop] of their own have finished
/// arriving and so hide the [PageBackdrop] completely.
final _covers = ValueNotifier<int>(0);

class _Drift extends StatefulWidget {
  const _Drift({required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(ValueListenable<double> phase) builder;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> {
  // The light wanders slowly; fifteen frames a second is plenty.
  final _clock = AmbientClock(fps: 15);
  late final _phase = _Loop(_clock, 32);

  Animation<double>? _arrival;
  bool _covering = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arrival = ModalRoute.of(context)?.animation;
    if (arrival != _arrival) {
      _arrival?.removeStatusListener(_arrived);
      _arrival = arrival?..addStatusListener(_arrived);
      // Deferred: the page backdrop may be building right now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cover(_arrival?.isCompleted ?? false);
      });
    }
    _sync();
  }

  @override
  void didUpdateWidget(_Drift oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() => _clock.run(widget.enabled && AmbientClock.wanted(context));

  void _arrived(AnimationStatus status) =>
      _cover(status == AnimationStatus.completed);

  void _cover(bool covering) {
    if (covering == _covering) return;
    _covering = covering;
    _covers.value += covering ? 1 : -1;
  }

  @override
  void dispose() {
    _arrival?.removeStatusListener(_arrived);
    if (_covering) {
      _covering = false;
      // Deferred: listeners must not rebuild while the tree is being torn down.
      WidgetsBinding.instance.addPostFrameCallback((_) => _covers.value--);
    }
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_phase);
}

/// A clock's seconds as a 0–1 phase that wraps every [period] seconds.
class _Loop extends ValueListenable<double> {
  const _Loop(this.clock, this.period);

  final AmbientClock clock;
  final double period;

  @override
  double get value => (clock.value / period) % 1;

  @override
  void addListener(VoidCallback listener) => clock.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => clock.removeListener(listener);
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.phase,
    required this.base,
    required this.glow,
    required this.shade,
    required this.ember,
    required this.dark,
    required this.palette,
    this.k = 1,
  }) : super(repaint: phase);

  final ValueListenable<double> phase;
  final Color base, glow, shade, ember;
  final bool dark;

  /// The skin decides the textures; its own colors paint them.
  final MusicPalette palette;

  /// How strong a skin's lights are: 1 in the player, about half behind
  /// lists, where they must not fight the text.
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final skin = palette.skin;
    if (skin == MusicSkin.aurora) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF030D15), base, const Color(0xFF0A242A)],
            stops: const [0, .55, 1],
          ).createShader(rect),
      );
    } else {
      canvas.drawRect(rect, Paint()..color = base);
    }
    final turn = phase.value * 2 * math.pi;
    final reach = size.longestSide;
    final w = size.width, h = size.height;

    void pool(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .36),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .42, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // The first two lights wander a little; in the player they take the
    // cover's colors.
    final first = Offset(
      w * (.14 + .10 * math.sin(turn)),
      h * (.10 + .05 * math.cos(turn)),
    );
    final second = Offset(
      w * (.94 + .08 * math.cos(turn + 1)),
      h * (.64 + .07 * math.sin(turn + 2)),
    );
    void texture(BlendMode blend) => canvas.drawImageRect(
      _texture(size, k, palette),
      Offset.zero & (size * _textureScale),
      rect,
      Paint()..blendMode = blend,
    );

    switch (skin) {
      case MusicSkin.night:
        pool(first, reach * .56, glow, .52);
        pool(second, reach * .54, shade, .40);
        pool(Offset(w * .20, h * 1.06), reach * .40, ember, .16);
      case MusicSkin.day:
        // On a pale page the pools tint the page itself; keep them faint.
        pool(first, reach * .56, glow, .40 * .35);
        pool(second, reach * .54, shade, .34 * .35);
        pool(Offset(w * .20, h * 1.06), reach * .40, ember, .10 * .35);
      case MusicSkin.neon:
        pool(first, reach * .56, glow, .42 * k + .1);
        pool(second, reach * .54, shade, .28 * k + .06);
        pool(Offset(w * .5, h * .34), h * .3, const Color(0xFF7B5CFF), .16);
        // Signs reflected in the wet street, laid on additively.
        texture(BlendMode.plus);
        // Tube scanlines.
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.ImageShader(
              _scanlines,
              TileMode.repeated,
              TileMode.repeated,
              Matrix4.identity().storage,
            ),
        );
      case MusicSkin.berry:
        // Watercolor blooms: pink, cream yellow, pale violet.
        pool(first, h * .5, glow, .34);
        pool(second, h * .5, shade, .5);
        pool(Offset(w * .95, h * .05), h * .32, const Color(0xFFD9C8FF), .42);
        pool(Offset(w * .1, h), h * .36, const Color(0xFFFFB8CE), .3);
        texture(BlendMode.srcOver);
      case MusicSkin.riso:
        // Flat paper and two halftone corners; no light at all.
        texture(BlendMode.srcOver);
      case MusicSkin.aurora:
        // The sky itself moves: see [AuroraLights].
        pool(Offset(w * .5, h * 1.05), h * .45, glow, .14 * k);
        pool(Offset(w, h * .02), h * .4, shade, .2 * k);
      case MusicSkin.silver:
        texture(BlendMode.srcOver);
        pool(Offset(w * .5, h * .3), h * .4, shade, .14);
    }

    if (dark) {
      final depth = switch (skin) {
        MusicSkin.neon => .4,
        MusicSkin.aurora => .3,
        _ => .34,
      };
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: .95,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: depth),
            ],
            stops: const [.55, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.phase != phase ||
      old.base != base ||
      old.glow != glow ||
      old.shade != shade ||
      old.ember != ember ||
      old.dark != dark ||
      old.palette != palette ||
      old.k != k;

  /// One dark row in every three, as a tile: a single draw covers the screen.
  static final ui.Image _scanlines = () {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = Colors.black.withValues(alpha: .2),
    );
    return recorder.endRecording().toImageSync(1, 3);
  }();

  static const _textureScale = 2.0;
  static final _textures = <String, ui.Image>{};

  /// A skin's still texture, drawn once per size and strength.
  static ui.Image _texture(Size size, double k, MusicPalette palette) {
    final key = '${palette.skin.name} ${size.width}x${size.height} $k';
    final cached = _textures[key];
    if (cached != null) return cached;
    if (_textures.length > 8) _textures.clear();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_textureScale);
    switch (palette.skin) {
      case MusicSkin.neon:
        _neonStreet(canvas, size, k, palette);
      case MusicSkin.berry:
        _pearl(canvas, size);
      case MusicSkin.riso:
        _halftone(canvas, size, palette);
      case MusicSkin.aurora:
        break;
      case MusicSkin.silver:
        _brushed(canvas, size);
      case MusicSkin.day || MusicSkin.night:
        break;
    }
    return _textures[key] = recorder.endRecording().toImageSync(
      (size.width * _textureScale).ceil(),
      (size.height * _textureScale).ceil(),
    );
  }

  static void _neonStreet(Canvas canvas, Size size, double k, MusicPalette p) {
    final random = math.Random(11);
    const violet = Color(0xFF7B5CFF);
    final colors = [p.accent, p.haze, p.accent, violet, p.haze, p.label];
    for (var i = 0; i < 18; i++) {
      final cx = random.nextDouble() * size.width;
      final cy = size.height * (.74 + random.nextDouble() * .24);
      final rx = 3 + random.nextDouble() * 10;
      final ry = 40 + random.nextDouble() * 110;
      final color = colors[i % colors.length];
      // A tall streak: a round glow stretched down the wet road.
      const unit = Rect.fromLTRB(-1, -1, 1, 1);
      canvas
        ..save()
        ..translate(cx, cy)
        ..scale(rx, ry)
        ..drawOval(
          unit,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: .36 * k),
                color.withValues(alpha: 0),
              ],
            ).createShader(unit),
        )
        ..restore();
    }
  }

  /// Pearl dust and a few four-pointed sparkles.
  static void _pearl(Canvas canvas, Size size) {
    final random = math.Random(5);
    const colors = [
      Color(0xFFFF9EBB),
      Color(0xFFB9A0FF),
      Color(0xFFFFD77A),
      Color(0xFFFFFFFF),
    ];
    for (var i = 0; i < 1100; i++) {
      final alpha = .35 + random.nextDouble() * .5;
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .3 + random.nextDouble() * .75,
        Paint()..color = colors[i % 4].withValues(alpha: alpha),
      );
    }
    for (var i = 0; i < 16; i++) {
      final r = 2.5 + random.nextDouble() * 4.5;
      final c = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final star = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
      canvas
        ..drawPath(
          star,
          Paint()
            ..color = const Color(0xE6FF82AA)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        )
        ..drawPath(star, Paint()..color = const Color(0xF2FFFFFF));
    }
  }

  /// Specks in recycled paper and a halftone fan in each ink, at two corners.
  static void _halftone(Canvas canvas, Size size, MusicPalette p) {
    final random = math.Random(9);
    final specks = [
      p.text.withValues(alpha: .2),
      p.haze.withValues(alpha: .28),
      Colors.white.withValues(alpha: .7),
    ];
    for (var i = 0; i < 900; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
          .5 + random.nextDouble() * 1.1,
          .5 + random.nextDouble() * .9,
        ),
        Paint()..color = specks[i % 3],
      );
    }
    // Dots on a turned grid, largest at the corner and shrinking to nothing.
    void fan(
      Offset corner,
      double reach,
      double cell,
      double angle,
      double largest,
      Color color,
    ) {
      final paint = Paint()..color = color;
      final cosA = math.cos(angle), sinA = math.sin(angle);
      final steps = (reach / cell).ceil();
      for (var i = -steps; i <= steps; i++) {
        for (var j = -steps; j <= steps; j++) {
          final at =
              corner +
              Offset(
                (i * cosA - j * sinA) * cell,
                (i * sinA + j * cosA) * cell,
              );
          final distance = (at - corner).distance;
          if (distance > reach ||
              at.dx < -4 ||
              at.dy < -4 ||
              at.dx > size.width + 4 ||
              at.dy > size.height + 4) {
            continue;
          }
          canvas.drawCircle(at, largest * (1 - distance / reach), paint);
        }
      }
    }

    final f = size.width / 286;
    fan(
      Offset(size.width + 10, -10),
      300 * f,
      7 * f,
      math.pi / 4,
      3.3 * f,
      p.haze.withValues(alpha: .95),
    );
    fan(
      Offset(-10, size.height + 10),
      170 * f,
      6 * f,
      math.pi / 12,
      2.4 * f,
      p.accent.withValues(alpha: .9),
    );
  }

  /// One of two sets of light curtains hanging from the sky: green along
  /// the lower hem, fading to violet above. Drifting against each other they
  /// make the aurora move.
  static ui.Image _auroraCurtains(Size size, double k, int variant) {
    final key = 'curtains$variant ${size.width}x${size.height} $k';
    final cached = _textures[key];
    if (cached != null) return cached;
    if (_textures.length > 8) _textures.clear();
    final recorder = ui.PictureRecorder();
    _curtains(Canvas(recorder)..scale(_textureScale), size, k, variant);
    return _textures[key] = recorder.endRecording().toImageSync(
      (size.width * _textureScale).ceil(),
      (size.height * _textureScale).ceil(),
    );
  }

  static void _curtains(Canvas canvas, Size size, double k, int variant) {
    // Smooth pseudo-random values, the same on every run.
    double hash(double n) {
      final v = math.sin(n * 127.1) * 43758.5453;
      return v - v.floorToDouble();
    }

    double noise(double x, double seed) {
      final i = x.floorToDouble(), t = x - i;
      final u = t * t * (3 - 2 * t);
      return hash(i + seed * 57) * (1 - u) + hash(i + 1 + seed * 57) * u;
    }

    const green = Color(0xFF5FFFB4);
    const teal = Color(0xFF3CE1C8);
    const violet = Color(0xFF7C5CFF);
    final f = size.width / 286;
    void curtain(double hem, double wave, double tall, double seed, double a) {
      for (var x = 0.0; x < size.width; x += 1) {
        final u = x / f;
        final y =
            hem +
            wave * f * math.sin(u * .017 + seed) +
            34 * f * (noise(u * .011 + seed, seed) - .5);
        final height = tall * f * (.35 + 1.1 * noise(u * .11, seed * 3.1));
        final glow = a * (.25 + .75 * noise(u * .028, seed * 7.7)) * k;
        final up = Rect.fromLTWH(x, y - height, 1, height);
        canvas.drawRect(
          up,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(
              up.bottomLeft,
              up.topLeft,
              [
                green.withValues(alpha: glow),
                teal.withValues(alpha: glow * .62),
                violet.withValues(alpha: glow * .3),
                violet.withValues(alpha: 0),
              ],
              [0, .22, .62, 1],
            ),
        );
        final down = Rect.fromLTWH(x, y, 1, 16 * f);
        canvas.drawRect(
          down,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(down.topLeft, down.bottomLeft, [
              green.withValues(alpha: glow * .7),
              green.withValues(alpha: 0),
            ]),
        );
      }
    }

    if (variant == 0) {
      curtain(size.height * .33, 20, 150, 1.3, .20);
      curtain(size.height * .47, 30, 210, 4.1, .32);
    } else {
      curtain(size.height * .30, 26, 170, 2.6, .16);
      curtain(size.height * .50, 22, 190, 5.9, .26);
    }
  }

  /// Brushed aluminium: hairlines along the grain and two broad reflections.
  static void _brushed(Canvas canvas, Size size) {
    final random = math.Random(17);
    for (var y = 0.0; y < size.height; y += .5) {
      final v = (random.nextDouble() - .5) * .11;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, .5),
        Paint()
          ..color = (v > 0 ? Colors.white : Colors.black).withValues(
            alpha: v.abs(),
          ),
      );
    }
    for (var i = 0; i < 2600; i++) {
      final length = 16 + random.nextDouble() * 130;
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextDouble() * size.width - length / 2,
          random.nextDouble() * size.height,
          length,
          .5,
        ),
        Paint()
          ..color = random.nextBool()
              ? Colors.white.withValues(alpha: .07)
              : Colors.black.withValues(alpha: .045),
      );
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .42),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .07),
            Colors.white.withValues(alpha: .2),
            Colors.black.withValues(alpha: .05),
          ],
          stops: const [0, .22, .6, .86, 1],
        ).createShader(rect),
    );
  }
}

/// Seconds on the clock that moves the aurora, shared so that a bar painting
/// its own piece of the sky stays in step with the sky behind it.
final _skyClock = ValueNotifier<double>(0);

/// Draws the aurora's moving parts across [size]: stars that twinkle each at
/// their own pace, and two sets of light curtains swaying slowly past each
/// other.
void _paintAuroraLights(Canvas canvas, Size size, double k, double seconds) {
  const loop = 600.0;
  final turn = seconds / loop * 2 * math.pi;
  final rect = Offset.zero & size;
  void curtains(int variant, Offset sway, double strength) {
    final image = _AmbientPainter._auroraCurtains(size, k, variant);
    canvas.drawImageRect(
      image,
      Offset.zero & (size * _AmbientPainter._textureScale),
      // Drawn a little oversize so the sway never uncovers an edge.
      rect.shift(sway).inflate(44),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: strength),
    );
  }

  // Whole cycles per loop, so the wrap-around never shows.
  curtains(
    0,
    Offset(34 * math.sin(turn * 40), 10 * math.sin(turn * 29 + 2)),
    .7 + .3 * math.sin(turn * 53),
  );
  curtains(
    1,
    Offset(-42 * math.sin(turn * 31 + 1), -12 * math.sin(turn * 37)),
    .7 + .3 * math.cos(turn * 43),
  );

  const star = Color(0xFFDFF8FF);
  final dot = Paint();
  for (final s in _stars) {
    final twinkle = .55 + .45 * math.sin(turn * s.pace + s.phase);
    canvas.drawCircle(
      Offset(s.x * size.width, s.y * size.height * .85),
      s.radius,
      dot..color = star.withValues(alpha: s.alpha * twinkle),
    );
  }
}

final _stars = () {
  final random = math.Random(21);
  return [
    for (var i = 0; i < 230; i++)
      (
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: random.nextDouble() > .92
            ? .9 + random.nextDouble() * .5
            : .35 + random.nextDouble() * .4,
        alpha: .2 + random.nextDouble() * .75,
        // A blink every two to five seconds.
        pace: (120 + random.nextInt(180)).toDouble(),
        phase: random.nextDouble() * 2 * math.pi,
      ),
  ];
}();

/// The aurora skin's living sky. Still when motion is reduced.
class AuroraLights extends StatefulWidget {
  const AuroraLights({super.key, this.k = 1});

  /// Strength of the curtains: 1 in the player, about half behind lists.
  final double k;

  @override
  State<AuroraLights> createState() => _AuroraLightsState();
}

class _AuroraLightsState extends State<AuroraLights> {
  // The sky moves slowly; fifteen frames a second is plenty.
  final _clock = AmbientClock(fps: 15);

  @override
  void initState() {
    super.initState();
    _clock.addListener(() => _skyClock.value = _clock.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.run(AmbientClock.wanted(context));
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _AuroraPainter(_clock, widget.k),
      size: Size.infinite,
    ),
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.clock, this.k) : super(repaint: clock);

  final ValueListenable<double> clock;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    _paintAuroraLights(canvas, size, k, clock.value);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.k != k;
}

/// Thin rain, actually falling: a few dozen drops, each at its own speed, so
/// the street looks drizzled on, not streaked. Still when motion is reduced.
class NeonRain extends StatefulWidget {
  const NeonRain({super.key});

  @override
  State<NeonRain> createState() => _NeonRainState();
}

class _NeonRainState extends State<NeonRain> {
  final _clock = AmbientClock(fps: 30);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.run(AmbientClock.wanted(context));
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _RainPainter(_clock), size: Size.infinite),
  );
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.clock) : super(repaint: clock);

  final ValueListenable<double> clock;

  /// Per drop: where along the top it starts, speed (pt/s), length, how
  /// bright, and where in its fall it begins.
  static final _drops = () {
    final random = math.Random(11);
    return [
      for (var i = 0; i < 30; i++)
        (
          x: random.nextDouble(),
          speed: 240 + random.nextDouble() * 300,
          length: 14 + random.nextDouble() * 30,
          alpha: .12 + random.nextDouble() * .2,
          phase: random.nextDouble(),
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFCDD7FF);
    final stroke = Paint()
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round;
    for (final drop in _drops) {
      final span = size.height + drop.length;
      final fall = (clock.value * drop.speed / span + drop.phase) % 1;
      final y = fall * span - drop.length;
      // The wind leans every drop the same way.
      final from = Offset(drop.x * (size.width + 60) - y * .2, y);
      final lean = Offset(-drop.length * .2, drop.length);
      // A faint tail and a brighter head, without a shader per drop.
      canvas
        ..drawLine(
          from,
          from + lean * .55,
          stroke..color = color.withValues(alpha: drop.alpha * .35),
        )
        ..drawLine(
          from + lean * .55,
          from + lean,
          stroke..color = color.withValues(alpha: drop.alpha),
        );
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => false;
}

/// Analogue grain: one small noise tile, generated once and repeated.
class FilmGrain extends StatefulWidget {
  const FilmGrain({super.key, this.opacity = .06});

  final double opacity;

  @override
  State<FilmGrain> createState() => _FilmGrainState();
}

class _FilmGrainState extends State<FilmGrain> {
  static const _side = 128;

  /// Shared by every instance, including ones mounted while it decodes.
  static final _tile = ValueNotifier<ui.Image?>(null);
  static bool _requested = false;

  @override
  void initState() {
    super.initState();
    _tile.addListener(_ready);
    if (_tile.value != null || _requested) return;
    _requested = true;
    final random = math.Random(33);
    final pixels = Uint8List(_side * _side * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      // Premultiplied: a white or black speck of random strength.
      final alpha = random.nextInt(256);
      final value = random.nextBool() ? alpha : 0;
      pixels
        ..[i] = value
        ..[i + 1] = value
        ..[i + 2] = value
        ..[i + 3] = alpha;
    }
    ui.decodeImageFromPixels(
      pixels,
      _side,
      _side,
      ui.PixelFormat.rgba8888,
      (image) => _tile.value = image,
    );
  }

  void _ready() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tile.removeListener(_ready);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile.value;
    if (tile == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainPainter(
          tile: tile,
          opacity: widget.opacity,
          // Two device pixels per speck: visible, but finer than a point.
          scale: 2 / MediaQuery.devicePixelRatioOf(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({
    required this.tile,
    required this.opacity,
    required this.scale,
  });

  final ui.Image tile;
  final double opacity, scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..shader = ui.ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.tile != tile || old.opacity != opacity || old.scale != scale;
}
