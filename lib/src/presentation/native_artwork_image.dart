import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Android's network stack can fetch NetEase artwork refused to Dart's client.
/// ImageCache coalesces requests and retains the decoded, size-bounded image.
class NativeArtworkImage extends ImageProvider<NativeArtworkImage> {
  const NativeArtworkImage(this.url);
  final String url;
  static const channel = MethodChannel('ai_music/artwork');

  @override
  Future<NativeArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    NativeArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(
    NativeArtworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await channel.invokeMethod<Uint8List>('load', {'url': url});
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Empty artwork response');
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NativeArtworkImage && other.url == url;
  @override
  int get hashCode => Object.hash(NativeArtworkImage, url);
}
