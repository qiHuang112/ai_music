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
  String get discover => isZh ? '发现' : 'Discover';
  String get qqMusic => isZh ? 'QQ音乐' : 'QQ Music';
  String get neteaseMusic => isZh ? '网易云音乐' : 'NetEase Cloud Music';
  String get qqPeakCharts => isZh ? '巅峰榜' : 'Peak charts';
  String get neteaseFeaturedCharts => isZh ? '云音乐特色榜' : 'Featured charts';
  String get selectAll => isZh ? '全选' : 'Select all';
  String get clearSelection => isZh ? '取消全选' : 'Clear selection';
  String get chartEmpty => isZh ? '榜单暂无歌曲' : 'No chart entries';
  String get mvChartHint => isZh
      ? 'MV 榜展示视频排名，不能作为音频歌曲加入歌单。'
      : 'The MV chart lists videos and cannot be added as audio tracks.';
  String get chartSelectionHint =>
      isZh ? '选择歌曲后可批量加入自建歌单' : 'Select songs to add them to a playlist';
  String chartUpdated(String date) =>
      isZh ? '榜单更新：$date' : 'Chart updated: $date';
  String chartSelected(int count) => isZh ? '已选 $count 首' : '$count selected';
  String chartMatching(int completed, int total) =>
      isZh ? '正在匹配 $completed/$total 首' : 'Matching $completed/$total';
  String chartAdded(String playlist, int added, int failed) => isZh
      ? '已向「$playlist」加入 $added 首，未找到 $failed 首'
      : 'Added $added to "$playlist"; $failed not found';
  String get chartNoMatches => isZh
      ? '所选歌曲没有找到可信的同歌名、同歌手结果'
      : 'No selected songs matched title and artist';
  String chartMatchInterrupted(int completed, int total) => isZh
      ? '歌源暂不可用，匹配已暂停（已处理 $completed/$total 首），未修改歌单'
      : 'Music source unavailable; matching stopped at $completed/$total. Playlist unchanged.';
  String get searchHint => isZh ? '歌手或歌曲' : 'Artist or song';
  String get searchEmptyTitle => isZh ? '搜索音乐' : 'Search music';
  String get searchEmptyBody => isZh
      ? '输入歌手或歌曲名，下载后会保存在本机缓存里。'
      : 'Enter an artist or song name. Downloaded tracks stay in local cache.';
  String get pressBackAgainToExit =>
      isZh ? '再按一次返回桌面' : 'Press back again to exit';
  String get searchOnline => isZh ? '在线搜索' : 'Search online';
  String get importScreenshots =>
      isZh ? '导入歌单截图' : 'Import playlist screenshots';
  String get listSearchHint => isZh ? '搜索当前列表' : 'Search this list';
  String get noMatchingTracks => isZh ? '没有匹配的歌曲' : 'No matching songs';
  String get retrySearch => isZh ? '重新搜索' : 'Retry search';
  String get preparingPlayback => isZh ? '正在准备播放' : 'Preparing playback';
  String playTrackFailed(String detail) =>
      isZh ? '播放失败：$detail' : 'Playback failed: $detail';
  String get settings => isZh ? '设置' : 'Settings';
  String get downloads => isZh ? '下载' : 'Downloads';
  String get downloadManager => isZh ? '下载管理' : 'Download Manager';
  String get playlists => isZh ? '播放列表' : 'Playlists';
  String get language => isZh ? '语言' : 'Language';
  String get theme => isZh ? '换肤' : 'Theme';
  String get musicSource => isZh ? '音乐源' : 'Music Source';
  String get screenshotSearchConcurrency =>
      isZh ? '截图搜歌并发数' : 'Screenshot search concurrency';
  String screenshotSearchConcurrencyDescription(int count) =>
      isZh ? '同时搜索 $count 首，范围 1～10 首' : 'Search $count songs at once (1–10)';
  String get playlistDownloadConcurrency =>
      isZh ? '歌单下载并发数' : 'Playlist download concurrency';
  String playlistDownloadConcurrencyDescription(int count) =>
      isZh ? '同时下载 $count 首，范围 1～10 首' : 'Download $count songs at once (1–10)';
  String playlistDownloadCounts(int total, int cached) => isZh
      ? '歌曲 $total 首 · 已下载 $cached 首'
      : '$total songs · $cached downloaded';
  String get playlistDownloads => isZh ? '歌单下载' : 'Playlist downloads';
  String playlistDownloadProgress(int cached, int total, int processed) => isZh
      ? '已下载 $cached/$total 首 · 已处理 $processed 首'
      : 'Downloaded $cached/$total · processed $processed';
  String get downloadPlaylistsOnWifi =>
      isZh ? 'WiFi下默认下载' : 'Download on Wi-Fi by default';
  String get downloadPlaylistsOnWifiDescription => isZh
      ? '进入自建歌单后，按歌单顺序下载未缓存的歌曲；离开 WiFi 时暂停'
      : 'Download uncached songs in playlist order when opening a custom playlist; pause off Wi-Fi';
  String get downloadAllPlaylist => isZh ? '一键全部下载' : 'Download all';
  String get downloadingPlaylist => isZh ? '正在下载歌单' : 'Downloading playlist';
  String playlistDownloadSummary(int downloaded, int skipped, int failed) =>
      isZh
      ? '下载 $downloaded 首，已缓存 $skipped 首，失败 $failed 首'
      : 'Downloaded $downloaded, already cached $skipped, failed $failed';
  String get lanLibrary => isZh ? '局域网音乐库' : 'LAN Music Library';
  String get lanLibraryAddress => isZh ? '局域网音乐库地址' : 'LAN library address';
  String get lanLibraryDescription => isZh
      ? '从电脑上的只读音乐服务增量同步，不会删除手机已有歌曲。'
      : 'Incrementally sync from the read-only computer service without deleting phone-only music.';
  String get saveLanAddress => isZh ? '保存地址' : 'Save address';
  String get testLanConnection => isZh ? '测试连接' : 'Test connection';
  String get scanAndSync => isZh ? '扫描并同步' : 'Scan and sync';
  String get lanSyncSection => isZh ? '局域网增量同步' : 'LAN incremental sync';
  String lanSyncProgress(int completed, int total, String title) => isZh
      ? '正在同步 $completed/$total${title.isEmpty ? '' : ' · $title'}'
      : 'Syncing $completed/$total${title.isEmpty ? '' : ' · $title'}';
  String lanSyncSummary(
    int added,
    int updated,
    int skipped,
    int failed, {
    int playlistsCreated = 0,
    int playlistsUpdated = 0,
  }) => isZh
      ? '新增 $added 首 · 更新 $updated 首 · 跳过 $skipped 首 · 失败 $failed 首'
            ' · 新建 $playlistsCreated 个歌单 · 更新 $playlistsUpdated 个歌单'
      : 'Added $added · updated $updated · skipped $skipped · failed $failed'
            ' · created $playlistsCreated playlists · updated $playlistsUpdated playlists';
  String get lanPlaylistMergeFailed => isZh
      ? '歌曲已保存，但歌单整理失败，可再次同步重试。'
      : 'Songs were saved, but playlist organization failed. Retry sync.';
  String get chinese => isZh ? '中文' : 'Chinese';
  String get english => isZh ? '英文' : 'English';
  String get lightTheme => isZh ? '白色' : 'Light';
  String get darkTheme => isZh ? '黑色' : 'Dark';
  String get autoSource => isZh ? '自动 / Auto' : 'Auto';
  String get buguyy => isZh ? '布谷歪歪 / BuguYY' : 'BuguYY';
  String get flacSource => isZh ? 'FLAC / flac.music.hi.cn' : 'FLAC';
  String get autoSourceDescription => isZh
      ? '同时搜索布谷歪歪和 FLAC，合并展示可用结果。'
      : 'Search BuguYY and FLAC together, then show the merged results.';
  String get buguyyDescription =>
      isZh ? '只使用布谷歪歪搜索和下载。' : 'Search and download with BuguYY only.';
  String get flacSourceDescription => isZh
      ? '只使用 flac.music.hi.cn 搜索和下载。'
      : 'Search and download with flac.music.hi.cn only.';
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
  String get download => isZh ? '下载' : 'Download';
  String get downloadAgain => isZh ? '重新下载' : 'Download again';
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
