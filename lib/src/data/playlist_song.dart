/// Original playlist metadata, independent of the chosen playback resource.
class PlaylistSong {
  const PlaylistSong({
    required this.key,
    required this.title,
    required this.artist,
    this.coverUrl = '',
    this.durationSeconds = 0,
    this.metadataVersion = 1,
  });
  final String key;
  final String title;
  final String artist;
  final String coverUrl;
  final int durationSeconds;
  final int metadataVersion;
  String get query => '$title $artist'.trim();
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'artist': artist,
    'coverUrl': coverUrl,
    'durationSeconds': durationSeconds,
    'metadataVersion': metadataVersion,
  };
  static PlaylistSong? fromJson(Object? value) {
    if (value is! Map) return null;
    final key = value['key']?.toString().trim() ?? '';
    final title = value['title']?.toString().trim() ?? '';
    if (key.isEmpty || title.isEmpty) return null;
    return PlaylistSong(
      key: key,
      title: title,
      artist: value['artist']?.toString() ?? '',
      coverUrl: value['coverUrl']?.toString() ?? '',
      durationSeconds: int.tryParse('${value['durationSeconds']}') ?? 0,
      metadataVersion: int.tryParse('${value['metadataVersion']}') ?? 0,
    );
  }
}
