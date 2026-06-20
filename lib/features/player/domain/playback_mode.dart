enum AppPlaybackMode { sequence, repeatOne }

extension AppPlaybackModeLabel on AppPlaybackMode {
  String get label {
    return switch (this) {
      AppPlaybackMode.sequence => '顺序播放',
      AppPlaybackMode.repeatOne => '单曲循环',
    };
  }
}
