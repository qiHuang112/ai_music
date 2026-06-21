import 'dart:math';

import 'resolver_models.dart';

Map<String, dynamic> asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return {};
}

int intFrom(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String urlExtension(String url) {
  try {
    final path = Uri.parse(url).path;
    final index = path.lastIndexOf('.');
    if (index >= 0) {
      return path.substring(index).toLowerCase();
    }
  } catch (_) {
    // Fall back to the resolved quality.
  }
  return '';
}

String prefix(String value) {
  return value.substring(0, min(160, value.length));
}

String formatResolverError(Object error) {
  return error.toString();
}

MusicQuality? bestQuality(List<MusicQuality> qualities, String prefer) {
  if (qualities.isEmpty) {
    return null;
  }
  final preferred = qualities
      .where((quality) => quality.format.toLowerCase() == prefer)
      .firstOrNull;
  if (preferred != null) {
    return preferred;
  }
  final flac = qualities
      .where((quality) => quality.format.toLowerCase() == 'flac')
      .firstOrNull;
  if (flac != null) {
    return flac;
  }
  final mp3 = qualities
      .where(
        (quality) =>
            quality.format.toLowerCase() == 'mp3' && quality.bitrate == '320',
      )
      .firstOrNull;
  return mp3 ?? qualities.first;
}

List<MusicQuality> qualityOrder(List<MusicQuality> qualities, String prefer) {
  final ordered = <MusicQuality>[];
  void add(MusicQuality? quality) {
    if (quality == null) {
      return;
    }
    final key = '${quality.format}:${quality.bitrate}';
    if (!ordered.any((item) => '${item.format}:${item.bitrate}' == key)) {
      ordered.add(quality);
    }
  }

  add(
    qualities
        .where((quality) => quality.format.toLowerCase() == prefer)
        .firstOrNull,
  );
  add(
    qualities
        .where((quality) => quality.format.toLowerCase() == 'flac')
        .firstOrNull,
  );
  add(
    qualities
        .where(
          (quality) =>
              quality.format.toLowerCase() == 'mp3' && quality.bitrate == '320',
        )
        .firstOrNull,
  );
  add(
    qualities
        .where(
          (quality) =>
              quality.format.toLowerCase() == 'mp3' && quality.bitrate == '128',
        )
        .firstOrNull,
  );
  for (final quality in qualities) {
    add(quality);
  }
  return ordered;
}
