import '../../library/domain/track.dart';

class DiscoveryResult {
  const DiscoveryResult({this.lyrics, this.wallpaperUrl});

  final String? lyrics;
  final String? wallpaperUrl;
}

abstract class DiscoveryService {
  Future<DiscoveryResult> discoverForTrack(Track track);
}

class EmptyDiscoveryService implements DiscoveryService {
  const EmptyDiscoveryService();

  @override
  Future<DiscoveryResult> discoverForTrack(Track track) async {
    return const DiscoveryResult();
  }
}
