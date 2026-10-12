import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Two colors read from cover art. The room takes its light from the record
/// that is playing.
class ArtworkPalette {
  const ArtworkPalette({required this.dominant, required this.vibrant});

  /// The color covering most of the art, and its most saturated one.
  final Color dominant, vibrant;

  static const _capacity = 64;
  static final _cache = <Object, Future<ArtworkPalette?>>{};

  /// Reads [image] at thumbnail size. Returns null when it cannot be loaded.
  /// Results are kept per provider, so list rows can ask freely.
  static Future<ArtworkPalette?> of(ImageProvider image) {
    final cached = _cache.remove(image);
    final result = cached ?? _extract(image);
    _cache[image] = result;
    if (_cache.length > _capacity) _cache.remove(_cache.keys.first);
    return result;
  }

  /// Light for a backdrop: saturated enough to color the room, dark enough
  /// for cream text on top. In a light theme it stays pale instead.
  Color glow(Brightness brightness) => _fit(
    vibrant,
    brightness == Brightness.dark ? (.30, .46) : (.62, .78),
    maxSaturation: .72,
  );

  Color shade(Brightness brightness) => _fit(
    dominant,
    brightness == Brightness.dark ? (.14, .26) : (.74, .86),
    maxSaturation: .55,
  );

  /// A paper-label tone for the centre of the record.
  Color get label => _fit(vibrant, (.34, .52), maxSaturation: .66);

  static Color _fit(
    Color color,
    (double, double) lightness, {
    required double maxSaturation,
  }) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(
          hsl.lightness.clamp(lightness.$1, lightness.$2).toDouble(),
        )
        .withSaturation(hsl.saturation.clamp(0, maxSaturation).toDouble())
        .toColor();
  }

  static Future<ArtworkPalette?> _extract(ImageProvider image) {
    final completer = Completer<ArtworkPalette?>();
    final stream = ResizeImage(
      image,
      width: 32,
      height: 32,
      policy: ResizeImagePolicy.fit,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) async {
        stream.removeListener(listener);
        try {
          final bytes = await info.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          completer.complete(bytes == null ? null : _quantize(bytes));
        } catch (_) {
          completer.complete(null);
        } finally {
          info.dispose();
        }
      },
      onError: (_, _) {
        stream.removeListener(listener);
        // Do not remember a failure: the art may load on the next attempt.
        _cache.remove(image);
        completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Buckets pixels into a 16-level cube per channel and scores the buckets.
  static ArtworkPalette? _quantize(ByteData bytes) {
    final count = Int32List(4096);
    final red = Int32List(4096);
    final green = Int32List(4096);
    final blue = Int32List(4096);
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) < 128) continue;
      final r = bytes.getUint8(i);
      final g = bytes.getUint8(i + 1);
      final b = bytes.getUint8(i + 2);
      final bucket = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      count[bucket]++;
      red[bucket] += r;
      green[bucket] += g;
      blue[bucket] += b;
    }
    Color? dominant, vibrant;
    var most = 0;
    var liveliest = 0.0;
    for (var bucket = 0; bucket < 4096; bucket++) {
      final n = count[bucket];
      if (n == 0) continue;
      final color = Color.fromARGB(
        255,
        red[bucket] ~/ n,
        green[bucket] ~/ n,
        blue[bucket] ~/ n,
      );
      if (n > most) {
        most = n;
        dominant = color;
      }
      // Favor saturated mid-tones, but not a single stray pixel.
      final hsl = HSLColor.fromColor(color);
      final midtone = (1 - (hsl.lightness - .5).abs() * 1.6).clamp(0, 1);
      final score = hsl.saturation * midtone * (n < 3 ? .2 : 1 + n / 256);
      if (score > liveliest) {
        liveliest = score;
        vibrant = color;
      }
    }
    if (dominant == null) return null;
    return ArtworkPalette(dominant: dominant, vibrant: vibrant ?? dominant);
  }
}
