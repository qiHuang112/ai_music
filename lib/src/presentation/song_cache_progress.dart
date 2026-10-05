import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../application/music_controller.dart';
import '../application/song_cache_progress.dart';
import '../domain/music_models.dart';
import 'app_localizations.dart';

/// Byte changes repaint the background; the row rebuilds only on status changes.
class SongCacheProgressRow extends StatefulWidget {
  const SongCacheProgressRow({
    super.key,
    required this.controller,
    required this.track,
    required this.rowBuilder,
  });
  final MusicController controller;
  final Track track;
  final Widget Function(BuildContext context, bool cached) rowBuilder;
  @override
  State<SongCacheProgressRow> createState() => _SongCacheProgressRowState();
}

class _SongCacheProgressRowState extends State<SongCacheProgressRow> {
  late ValueListenable<SongCacheProgress> _progress;
  late ({bool offline, bool active, bool partial}) _status;
  static ({bool offline, bool active, bool partial}) status(
    SongCacheProgress p,
  ) => (offline: p.offline, active: p.active, partial: p.fraction != 0);
  @override
  void initState() {
    super.initState();
    _progress = widget.controller.cacheProgressFor(widget.track);
    _status = status(_progress.value);
    _progress.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SongCacheProgressRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller.cacheProgressFor(widget.track);
    if (!identical(_progress, next)) {
      _progress.removeListener(_changed);
      _progress = next;
      _status = status(next.value);
      _progress.addListener(_changed);
    }
  }

  void _changed() {
    final next = status(_progress.value);
    if (next != _status) setState(() => _status = next);
  }

  @override
  void dispose() {
    _progress.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final zh = AppStringsScope.of(context).isZh;
    final label = _status.offline
        ? (zh ? '已完整缓存，可离线播放' : 'Fully cached; available offline')
        : _status.active
        ? (zh ? '正在下载，可点击播放' : 'Downloading; tap to play')
        : _status.partial
        ? (zh ? '部分缓存，可点击播放' : 'Partly cached; tap to play')
        : (zh ? '尚未缓存，可点击播放' : 'Not cached; tap to play');
    return Semantics(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          key: ValueKey('song-cache-background-${widget.track.id}'),
          painter: _CacheBackground(
            _progress,
            active: colors.primary.withValues(alpha: .10),
            paused: colors.onSurface.withValues(alpha: .05),
          ),
          child: widget.rowBuilder(context, _status.offline),
        ),
      ),
    );
  }
}

class _CacheBackground extends CustomPainter {
  _CacheBackground(this.progress, {required this.active, required this.paused})
    : super(repaint: progress);
  final ValueListenable<SongCacheProgress> progress;
  final Color active;
  final Color paused;
  @override
  void paint(Canvas canvas, Size size) {
    final value = progress.value;
    if (value.offline && !value.active) return;
    final fraction = value.fraction ?? 0;
    if (fraction <= 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width * fraction, size.height);
    final color = value.active ? active : paused;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color,
            color.withValues(alpha: color.a * .65),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CacheBackground old) =>
      !identical(progress, old.progress) ||
      active != old.active ||
      paused != old.paused;
}
