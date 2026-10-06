import 'dart:io';

import 'package:flutter/material.dart';

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
    final art = uri;
    ImageProvider? image;
    if (art != null) {
      if (art.isScheme('file') && art.host.isEmpty) {
        image = FileImage(File(art.toFilePath()));
      } else if ((art.isScheme('http') || art.isScheme('https')) &&
          art.host.isNotEmpty) {
        image = NetworkImage(art.toString(), headers: headers);
      }
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
      1,
      512,
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: image == null
              ? fallback
              : Image(
                  image: ResizeImage.resizeIfNeeded(pixels, pixels, image),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (_, child, frame, synchronous) =>
                      synchronous || frame != null ? child : fallback,
                ),
        ),
      ),
    );
  }
}
