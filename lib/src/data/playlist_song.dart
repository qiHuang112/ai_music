/// Original playlist metadata, independent of the chosen playback resource.
class PlaylistSong {
  const PlaylistSong({
    required this.key,
    required this.title,
    required this.artist,
    this.coverUrl = '',
  });
  final String key;
  final String title;
  final String artist;
  final String coverUrl;
  String get query => '$title $artist'.trim();
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'artist': artist,
    'coverUrl': coverUrl,
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
    );
  }
}
