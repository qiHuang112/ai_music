import 'package:flutter/widgets.dart';

import '../data/music_settings.dart';

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.language,
    required super.child,
  });

  final AppLanguage language;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return AppStrings(scope?.language ?? AppLanguage.zh);
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) {
    return language != oldWidget.language;
  }
}

class AppStrings {
  const AppStrings(this.languageCode);

  final AppLanguage languageCode;

  bool get isZh => languageCode == AppLanguage.zh;

  String get appTitle => isZh ? '搜音乐' : 'Search Music';
  String get searchHint => isZh ? '歌手或歌曲' : 'Artist or song';
  String get searchEmptyTitle => isZh ? '搜索音乐' : 'Search music';
  String get searchEmptyBody => isZh
      ? '输入歌手或歌曲名，下载后会保存在本机缓存里。'
      : 'Enter an artist or song name. Downloaded tracks stay in local cache.';
  String get hotlistDiscovery => isZh ? '热榜发现' : 'Hot Charts';
  String get hotlistPlaylists => isZh ? '热榜歌单' : 'Hot Chart Playlists';
  String get hotlistUnavailable =>
      isZh ? '暂时无法获取热榜，稍后再试。' : 'Hot charts are unavailable. Try again later.';
  String get hotlistSourceQq => isZh ? 'QQ 音乐' : 'QQ Music';
  String get hotlistMetadataNotice => isZh
      ? '榜单仅用于发现，播放需通过 AI Music 搜索匹配。'
      : 'Charts are for discovery. Playback uses AI Music search matching.';
  String get addHotlistToPlaylist => isZh ? '加入歌单' : 'Add playlist';
  String get playFromTransientCache => isZh ? '临时播放' : 'Stream temporarily';
  String hotlistSaved(int added, int skipped) => isZh
      ? '已加入 $added 首，跳过 $skipped 首重复歌曲'
      : 'Added $added, skipped $skipped duplicates';
  String hotlistUpdated(String value) => isZh ? '更新 $value' : 'Updated $value';
  String get pressBackAgainToExit =>
      isZh ? '再按一次返回桌面' : 'Press back again to exit';
  String get searchOnline => isZh ? '在线搜索' : 'Search online';
  String get searchAndPlay => isZh ? '搜索并播放' : 'Search and play';
  String get listSearchHint => isZh ? '搜索当前列表' : 'Search this list';
  String get noMatchingTracks => isZh ? '没有匹配的歌曲' : 'No matching songs';
  String get retrySearch => isZh ? '重新搜索' : 'Retry search';
  String get settings => isZh ? '设置' : 'Settings';
  String get downloads => isZh ? '下载' : 'Downloads';
  String get downloadManager => isZh ? '下载管理' : 'Download Manager';
  String get playlists => isZh ? '播放列表' : 'Playlists';
  String get language => isZh ? '语言' : 'Language';
  String get theme => isZh ? '换肤' : 'Theme';
  String get musicSource => isZh ? '音乐源' : 'Music Source';
  String get chinese => isZh ? '中文' : 'Chinese';
  String get english => isZh ? '英文' : 'English';
  String get lightTheme => isZh ? '白色' : 'Light';
  String get darkTheme => isZh ? '黑色' : 'Dark';
  String get autoSource => isZh ? '自动 / Auto' : 'Auto';
  String get buguyy => isZh ? '布谷歪歪 / BuguYY' : 'BuguYY';
  String get flacSource => isZh ? 'FLAC / flac.music.hi.cn' : 'FLAC';
  String get source2t58 => isZh ? '2t58.com' : '2t58.com';
  String get source22a5 => isZh ? '22a5.com' : '22a5.com';
  String get gequhaiSource => isZh ? '歌曲海 / gequhai.com' : 'Gequhai';
  String get gequbaoSource => isZh ? '歌曲宝 / gequbao.com' : 'Gequbao';
  String get kuwoFullAudioSource => isZh ? 'Kuwo 完整音频' : 'Kuwo Full Audio';
  String get itunesPreviewSource =>
      isZh ? 'iTunes 试听 / Preview' : 'iTunes Preview';
  String get autoSourceDescription => isZh
      ? '优先展示可下载的完整音频；不会用试听作为替代结果。'
      : 'Prioritizes downloadable full tracks; previews are hidden.';
  String get buguyyDescription =>
      isZh ? '只使用布谷歪歪搜索和下载。' : 'Search and download with BuguYY only.';
  String get flacSourceDescription => isZh
      ? '只使用 flac.music.hi.cn 搜索和下载。'
      : 'Search and download with flac.music.hi.cn only.';
  String get source2t58Description => isZh
      ? '当前为防护页，未开放客户端完整音频直链。'
      : 'Currently gated; no client-ready full-audio URL.';
  String get source22a5Description => isZh
      ? '当前为安全验证页，旧媒体 URL 已过期，不自动下载。'
      : 'Currently gated; old media URLs expired, no auto download.';
  String get gequhaiDescription => isZh
      ? '当前三条入口均 HTTP 403，未暴露完整音频直链。'
      : 'Current entry points return HTTP 403; no full-audio URL.';
  String get gequbaoDescription => isZh
      ? '当前为 403 / Just a moment 防护页，旧媒体 URL 已过期。'
      : 'Currently blocked by 403 / Just a moment; old media URLs expired.';
  String get kuwoFullAudioDescription => isZh
      ? '当前可用的完整音频 PoC，支持边下边播与正式缓存。'
      : 'Current full-track PoC with progressive playback and cache.';
  String get activeDownloads => isZh ? '正在下载' : 'Active Downloads';
  String get recentDownloads => isZh ? '最近任务' : 'Recent Tasks';
  String get cachedMusic => isZh ? '已缓存音乐' : 'Cached Music';
  String get noDownloads => isZh ? '没有正在下载的任务' : 'No active downloads';
  String get noRecentDownloads => isZh ? '没有最近任务' : 'No recent tasks';
  String get noCachedMusic => isZh ? '还没有缓存音乐' : 'No cached music yet';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get clear => isZh ? '清除' : 'Clear';
  String get delete => isZh ? '删除' : 'Delete';
  String get play => isZh ? '播放' : 'Play';
  String get playPreview => isZh ? '播放试听' : 'Play preview';
  String get download => isZh ? '下载' : 'Download';
  String get downloadAgain => isZh ? '重新下载' : 'Download again';
  String get playingFullAudioStream =>
      isZh ? '正在边下边播完整歌曲' : 'Streaming full track';
  String get playingPreviewAudio => isZh ? '正在播放试听片段' : 'Playing preview';
  String get previewCannotDownload => isZh
      ? '当前仅支持试听，无法缓存为完整歌曲。'
      : 'Only preview playback is available; full-track caching is unavailable.';
  String get repairLegacy => isZh ? '修复老资源' : 'Repair old cache';
  String get refresh => isZh ? '刷新' : 'Refresh';
  String get sort => isZh ? '排序' : 'Sort';
  String get sortByInitial => isZh ? '首字母' : 'A-Z';
  String get sortByDownloadTime => isZh ? '下载时间' : 'Download time';
  String get sortByAddedTime => isZh ? '加入时间' : 'Added time';
  String get customOrder => isZh ? '自定义顺序' : 'Custom order';
  String get dragToReorder => isZh ? '拖拽排序' : 'Drag to reorder';
  String get adjustOrder => isZh ? '调整顺序' : 'Adjust order';
  String get saveOrder => isZh ? '保存' : 'Save';
  String get finishOrderEdit => isZh ? '完成' : 'Done';
  String get discardOrderChangesTitle =>
      isZh ? '放弃本次排序调整？' : 'Discard order changes?';
  String get discardOrderChangesBody =>
      isZh ? '未保存的顺序调整会丢失。' : 'Unsaved order changes will be lost.';
  String get keepEditing => isZh ? '继续编辑' : 'Keep editing';
  String get discardChanges => isZh ? '放弃' : 'Discard';
  String get saveAndExit => isZh ? '保存并退出' : 'Save and exit';
  String get clearSearchToAdjustOrder =>
      isZh ? '清除搜索后可调整顺序' : 'Clear search to adjust order';
  String get lyrics => isZh ? '歌词' : 'Lyrics';
  String get noLyrics => isZh ? '暂无歌词' : 'No lyrics yet';
  String get retryLyrics => isZh ? '重新获取歌词' : 'Fetch lyrics again';
  String get fetchingLyrics => isZh ? '正在获取歌词' : 'Fetching lyrics';
  String get nowPlaying => isZh ? '正在播放' : 'Now playing';
  String get homeLibraryTitle => isZh ? '我的音乐' : 'My Music';
  String get libraryTitle => isZh ? '我的缓存列表' : 'My Library';
  String get localLibrary => isZh ? '本地' : 'Local';
  String get favorite => isZh ? '收藏' : 'Favorites';
  String get customPlaylists => isZh ? '自建歌单' : 'Custom Playlists';
  String get noCustomPlaylists => isZh ? '还没有自建歌单' : 'No custom playlists yet';
  String get managePlaylists => isZh ? '管理歌单' : 'Manage playlists';
  String get createPlaylistHomeHint =>
      isZh ? '打开播放列表后可新建歌单。' : 'Open playlists to create one.';
  String get createPlaylistHint =>
      isZh ? '点右上角新建一个歌单。' : 'Tap the top-right button to create one.';
  String get newPlaylist => isZh ? '新建歌单' : 'New playlist';
  String get create => isZh ? '创建' : 'Create';
  String get rename => isZh ? '重命名' : 'Rename';
  String get renamePlaylist => isZh ? '重命名歌单' : 'Rename playlist';
  String get deletePlaylist => isZh ? '删除歌单' : 'Delete playlist';
  String get deletePlaylistTitle => isZh ? '删除歌单？' : 'Delete playlist?';
  String deletePlaylistBody(String name) => isZh
      ? '只删除“$name”这个歌单，已缓存歌曲仍会保留在设备上。'
      : 'This removes "$name" only. Cached songs stay on this device.';
  String get noFavoritesYet => isZh ? '还没有收藏' : 'No favorites yet';
  String get noSongsInPlaylist =>
      isZh ? '这个歌单还没有歌曲' : 'No songs in this playlist';
  String get noCachedMusicBody => isZh
      ? '搜索歌手或歌曲，下载后会出现在这里。'
      : 'Search an artist or song, then download a result to build your local library.';
  String get emptyPlaylistBody => isZh
      ? '从本地库或播放器里添加已缓存歌曲。'
      : 'Add cached songs from the library or player.';
  String get playlistName => isZh ? '歌单名称' : 'Playlist name';
  String get noCustomPlaylistsYet =>
      isZh ? '还没有自建歌单' : 'No custom playlists yet';
  String get createOneToGroup =>
      isZh ? '新建歌单后可以归类已缓存歌曲。' : 'Create one to group cached songs.';
  String get alreadyAdded => isZh ? '已添加' : 'Already added';
  String get addToThisPlaylist => isZh ? '添加到这个歌单' : 'Add to this playlist';
  String get addToPlaylist => isZh ? '添加到歌单' : 'Add to playlist';
  String selectedSongCount(int count) =>
      isZh ? '已选择 $count 首' : '$count selected';
  String get selectAllVisible => isZh ? '全选当前列表' : 'Select visible';
  String get deleteLocalMusic => isZh ? '删除本地音乐' : 'Delete local music';
  String deleteLocalMusicTitle(int count) => isZh
      ? (count == 1 ? '删除本地音乐？' : '删除 $count 首本地音乐？')
      : (count == 1 ? 'Delete local music?' : 'Delete $count local songs?');
  String deleteLocalMusicBody(int count) => isZh
      ? (count == 1
            ? '会删除这首歌的本机缓存音频、歌词和元数据，并从收藏和歌单中移除。'
            : '会删除这 $count 首歌的本机缓存音频、歌词和元数据，并从收藏和歌单中移除。')
      : (count == 1
            ? 'This deletes the cached audio, lyrics, and metadata on this device, and removes the song from favorites and playlists.'
            : 'This deletes cached audio, lyrics, and metadata for these $count songs on this device, and removes them from favorites and playlists.');
  String get removeSelected => isZh ? '移除所选' : 'Remove selected';
  String get addToFavorites => isZh ? '添加到收藏' : 'Add to favorites';
  String get removeFromFavorites => isZh ? '从收藏移除' : 'Remove from favorites';
  String get removeFromThisPlaylist =>
      isZh ? '从这个歌单移除' : 'Remove from this playlist';
  String get playing => isZh ? '正在播放' : 'Playing';
  String get more => isZh ? '更多' : 'More';
  String get previous => isZh ? '上一首' : 'Previous';
  String get next => isZh ? '下一首' : 'Next';
  String get pause => isZh ? '暂停' : 'Pause';
  String get stop => isZh ? '停止' : 'Stop';
  String get nothingPlaying => isZh ? '当前没有播放内容' : 'Nothing playing';
  String get unknownArtist => isZh ? '未知歌手' : 'Unknown Artist';
  String songCount(int count) => isZh ? '$count 首' : '$count songs';
  String get modeSequential => isZh ? '顺序播放' : 'Sequential';
  String get modeLoopAll => isZh ? '列表循环' : 'Repeat all';
  String get modeRepeatOne => isZh ? '单曲循环' : 'Repeat one';
  String get modeShuffle => isZh ? '随机播放' : 'Shuffle';
  String get statusResolving => isZh ? '解析中' : 'Resolving';
  String get statusDownloading => isZh ? '下载中' : 'Downloading';
  String get statusCompleted => isZh ? '已完成' : 'Completed';
  String get statusFailed => isZh ? '失败' : 'Failed';
  String get statusCanceled => isZh ? '已取消' : 'Canceled';
  String resolvingTrack(String name) => isZh ? '正在解析 $name' : 'Resolving $name';
  String downloadingTrack(String name) =>
      isZh ? '正在下载 $name' : 'Downloading $name';
  String downloadingBytes(String bytes) =>
      isZh ? '已下载 $bytes' : 'Downloading $bytes';
  String downloadingPercent(String percent) =>
      isZh ? '下载中 $percent%' : 'Downloading $percent%';
  String get noOnlineMatchesFound =>
      isZh ? '没有找到在线结果' : 'No online matches found';
  String get alreadyInCache => isZh ? '已在缓存中' : 'Already in cache';
  String get downloadedToCache => isZh ? '已下载到缓存' : 'Downloaded to cache';
  String get downloadAlreadyRunning =>
      isZh ? '这首歌正在下载' : 'This song is already downloading';
  String get downloadCanceled => isZh ? '下载已取消' : 'Download canceled';
  String get playingCachedFile => isZh ? '正在播放缓存文件' : 'Playing cached file';
}
