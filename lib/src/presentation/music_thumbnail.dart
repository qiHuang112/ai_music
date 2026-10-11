import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'native_artwork_image.dart';

/// Uses existing artwork only, with bounded decoding and a stable fallback.
class MusicThumbnail extends StatelessWidget {
  const MusicThumbnail({
    super.key,
    this.uri,
    this.label = '',
    this.icon = Icons.music_note_rounded,
    this.size = 58,
    this.radius = 12,
    this.headers,
  });

  final Uri? uri;
  final Map<String, String>? headers;
  final String label;
  final IconData icon;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      key: const ValueKey('music-thumbnail-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainer, colors.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: label.trim().isEmpty
            ? Icon(icon, color: colors.primary, size: size * .42)
            : Text(
                label.trim().characters.first,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: size * .4,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
      1,
      512,
    );
    final art = uri;
    ImageProvider? image;
    ImageProvider? alternative;
    ImageProvider? native;
    if (art != null) {
      if (art.isScheme('file') && art.host.isEmpty) {
        image = FileImage(File(art.toFilePath()));
      } else if ((art.isScheme('http') || art.isScheme('https')) &&
          art.host.isNotEmpty) {
        // Legacy imports can contain HTTP CDN artwork. Use the same secure
        // provider request for these covers on every page, without rewriting
        // local/LAN image URLs.
        final host = art.host.toLowerCase();
        bool domain(String suffix) =>
            host == suffix || host.endsWith('.$suffix');
        final referer = domain('music.126.net')
            ? 'https://music.163.com/'
            : domain('qpic.cn') || domain('gtimg.cn')
            ? 'https://y.qq.com/'
            : domain('kuwo.cn')
            ? 'https://www.kuwo.cn/'
            : null;
        final requestHeaders = {
          if (referer != null) ...{
            'User-Agent': 'Mozilla/5.0',
            'Referer': referer,
          },
          ...?headers,
        };
        final primary = referer == null ? art : art.replace(scheme: 'https');
        image = NetworkImage(primary.toString(), headers: requestHeaders);
        if (RegExp(r'^p[1-4]\.music\.126\.net$').hasMatch(host)) {
          // Some NetEase CDN edges reject the original image on mobile.
          // Retry once through its alternate CDN's resized image endpoint.
          alternative = NetworkImage(
            primary
                .replace(
                  host: host == 'p2.music.126.net'
                      ? 'p1.music.126.net'
                      : 'p2.music.126.net',
                  queryParameters: {
                    ...primary.queryParameters,
                    'param': '${pixels}y$pixels',
                  },
                )
                .toString(),
            headers: requestHeaders,
          );
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
            native = NativeArtworkImage((alternative as NetworkImage).url);
          }
        }
      }
    }
    Widget artwork(ImageProvider provider, {Widget? onError}) => Image(
      image: ResizeImage.resizeIfNeeded(pixels, pixels, provider),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => onError ?? fallback,
      frameBuilder: (_, child, frame, synchronous) =>
          synchronous || frame != null ? child : fallback,
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: image == null
              ? fallback
              : artwork(
                  image,
                  onError: native != null
                      ? artwork(native, onError: artwork(alternative!))
                      : alternative == null
                      ? null
                      : artwork(alternative),
                ),
        ),
      ),
    );
  }
}
