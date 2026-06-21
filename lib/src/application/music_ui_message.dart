enum MusicUiMessageCode {
  noOnlineMatchesFound,
  resolving,
  downloading,
  downloadingBytes,
  downloadingPercent,
  alreadyInCache,
  downloadedToCache,
  downloadAlreadyRunning,
  downloadCanceled,
  playingCachedFile,
}

class MusicUiMessage {
  const MusicUiMessage(this.code, {this.subject = '', this.value = ''});

  final MusicUiMessageCode code;
  final String subject;
  final String value;
}
