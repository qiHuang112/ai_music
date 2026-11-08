import 'package:flutter/material.dart' show IconData, Icons;

/// One icon family for the whole app: Material Icons, Rounded theme. Pages
/// use these names instead of picking glyphs and variants one by one, so
/// the same meaning is always drawn the same way, with the same weight.
abstract final class AppIcons {
  static const IconData sequential = Icons.playlist_play_rounded;
  static const IconData swapVertical = Icons.swap_vert_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData addPhoto = Icons.add_photo_alternate_rounded;
  static const IconData photos = Icons.photo_library_rounded;
  static const IconData record = Icons.album_rounded;
  static const IconData back = Icons.arrow_back_ios_new_rounded;
  static const IconData dropDown = Icons.arrow_drop_down_rounded;
  static const IconData forward = Icons.arrow_forward_rounded;
  static const IconData sparkles = Icons.auto_awesome_rounded;
  static const IconData chart = Icons.bar_chart_rounded;
  static const IconData bug = Icons.bug_report_rounded;
  static const IconData calendar = Icons.calendar_month_rounded;
  static const IconData cancel = Icons.cancel_rounded;
  static const IconData clearField = Icons.clear_rounded;
  static const IconData comment = Icons.chat_bubble_outline_rounded;
  static const IconData comments = Icons.forum_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData checkCircleFill = Icons.check_circle_rounded;
  static const IconData checkCircle = Icons.check_circle_outline_rounded;
  static const IconData checklist = Icons.checklist_rounded;
  static const IconData paint = Icons.palette_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronUp = Icons.expand_less_rounded;
  static const IconData chevronDown = Icons.expand_more_rounded;
  static const IconData chevronUpDown = Icons.unfold_more_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData cloudDownload = Icons.cloud_download_rounded;
  static const IconData cloud = Icons.cloud_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData contrast = Icons.contrast_rounded;
  static const IconData square = Icons.crop_square_rounded;
  static const IconData darkMode = Icons.dark_mode_rounded;
  static const IconData lightMode = Icons.light_mode_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData clearAll = Icons.delete_sweep_rounded;
  static const IconData devices = Icons.devices_rounded;
  static const IconData server = Icons.dns_rounded;
  static const IconData storage = Icons.storage_rounded;
  static const IconData scan = Icons.document_scanner_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData downloaded = Icons.download_done_rounded;
  static const IconData saveTo = Icons.save_alt_rounded;
  static const IconData reorder = Icons.drag_handle_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData warning = Icons.sync_problem_rounded;
  static const IconData heartFill = Icons.favorite_rounded;
  static const IconData heart = Icons.favorite_border_rounded;
  static const IconData filterFill = Icons.filter_alt_rounded;
  static const IconData filter = Icons.filter_alt_outlined;
  static const IconData filterList = Icons.filter_list_rounded;
  static const IconData folder = Icons.folder_open_rounded;
  static const IconData quality = Icons.high_quality_rounded;
  static const IconData history = Icons.history_rounded;
  static const IconData home = Icons.home_rounded;
  static const IconData source = Icons.hub_rounded;
  static const IconData imageSearch = Icons.image_search_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData insights = Icons.insights_rounded;
  static const IconData share = Icons.share_rounded;
  static const IconData lan = Icons.wifi_tethering_rounded;
  static const IconData language = Icons.language_rounded;
  static const IconData library = Icons.library_music_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData lyrics = Icons.lyrics_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData moreVertical = Icons.more_vert_rounded;
  static const IconData music = Icons.music_note_rounded;
  static const IconData locate = Icons.my_location_rounded;
  static const IconData network = Icons.network_check_rounded;
  static const IconData openExternal = Icons.open_in_new_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData miniWindow = Icons.picture_in_picture_alt_rounded;
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData playlistAdd = Icons.playlist_add_rounded;
  static const IconData playlistRemove = Icons.playlist_remove_rounded;
  static const IconData queue = Icons.queue_music_rounded;
  static const IconData radioOn = Icons.radio_button_checked_rounded;
  static const IconData radioOff = Icons.radio_button_unchecked_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData restart = Icons.restart_alt_rounded;
  static const IconData remove = Icons.remove_circle_outline_rounded;
  static const IconData repeatOne = Icons.repeat_one_rounded;
  static const IconData save = Icons.save_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData shuffle = Icons.shuffle_rounded;
  static const IconData next = Icons.skip_next_rounded;
  static const IconData previous = Icons.skip_previous_rounded;
  static const IconData sort = Icons.sort_rounded;
  static const IconData speed = Icons.speed_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData swap = Icons.swap_horiz_rounded;
  static const IconData sync = Icons.sync_rounded;
  static const IconData update = Icons.system_update_rounded;
  static const IconData like = Icons.thumb_up_outlined;
  static const IconData tune = Icons.tune_rounded;
  static const IconData upload = Icons.upload_file_rounded;
  static const IconData volumeLow = Icons.volume_down_rounded;
  static const IconData volumeOff = Icons.volume_off_rounded;
  static const IconData volumeHigh = Icons.volume_up_rounded;
}

/// SF Symbols for [AppIcons] in the iOS shell's native bars. Lyrics has
/// none on purpose: no system symbol reads as lyrics, so the shell draws
/// the Material glyph instead.
final appIconSymbols = <IconData, String>{
  Icons.playlist_play_rounded: 'list.number',
  Icons.swap_vert_rounded: 'arrow.up.arrow.down',
  Icons.add_rounded: 'plus',
  Icons.add_photo_alternate_rounded: 'photo.on.rectangle',
  Icons.photo_library_rounded: 'photo.on.rectangle',
  Icons.album_rounded: 'music.note',
  Icons.arrow_back_ios_new_rounded: 'chevron.backward',
  Icons.arrow_drop_down_rounded: 'chevron.down',
  Icons.arrow_forward_rounded: 'arrow.right',
  Icons.auto_awesome_rounded: 'sparkles',
  Icons.bar_chart_rounded: 'chart.bar',
  Icons.bug_report_rounded: 'ladybug',
  Icons.calendar_month_rounded: 'calendar',
  Icons.cancel_rounded: 'xmark.circle',
  Icons.clear_rounded: 'xmark.circle.fill',
  Icons.chat_bubble_outline_rounded: 'bubble.left',
  Icons.forum_rounded: 'bubble.left.and.bubble.right',
  Icons.check_rounded: 'checkmark',
  Icons.check_circle_rounded: 'checkmark.circle.fill',
  Icons.check_circle_outline_rounded: 'checkmark.circle',
  Icons.checklist_rounded: 'checkmark.square',
  Icons.palette_rounded: 'paintbrush',
  Icons.chevron_left_rounded: 'chevron.left',
  Icons.chevron_right_rounded: 'chevron.right',
  Icons.expand_less_rounded: 'chevron.up',
  Icons.expand_more_rounded: 'chevron.down',
  Icons.unfold_more_rounded: 'chevron.up.chevron.down',
  Icons.close_rounded: 'xmark',
  Icons.cloud_download_rounded: 'icloud.and.arrow.down',
  Icons.cloud_rounded: 'icloud',
  Icons.content_copy_rounded: 'doc.on.doc',
  Icons.contrast_rounded: 'circle.lefthalf.filled',
  Icons.crop_square_rounded: 'square',
  Icons.dark_mode_rounded: 'moon',
  Icons.light_mode_rounded: 'sun.max',
  Icons.delete_outline_rounded: 'trash',
  Icons.delete_sweep_rounded: 'trash.circle',
  Icons.devices_rounded: 'desktopcomputer',
  Icons.dns_rounded: 'square.stack.3d.up',
  Icons.storage_rounded: 'archivebox',
  Icons.document_scanner_rounded: 'doc.text.viewfinder',
  Icons.download_rounded: 'arrow.down.circle',
  Icons.download_done_rounded: 'arrow.down.circle.fill',
  Icons.save_alt_rounded: 'square.and.arrow.down',
  Icons.drag_handle_rounded: 'line.3.horizontal',
  Icons.edit_rounded: 'pencil',
  Icons.error_outline_rounded: 'exclamationmark.circle',
  Icons.sync_problem_rounded: 'exclamationmark.triangle',
  Icons.favorite_rounded: 'heart.fill',
  Icons.favorite_border_rounded: 'heart',
  Icons.filter_alt_rounded: 'line.3.horizontal.decrease.circle.fill',
  Icons.filter_alt_outlined: 'line.3.horizontal.decrease.circle',
  Icons.filter_list_rounded: 'line.3.horizontal.decrease',
  Icons.folder_open_rounded: 'folder',
  Icons.high_quality_rounded: 'waveform',
  Icons.history_rounded: 'clock',
  Icons.home_rounded: 'house',
  Icons.hub_rounded: 'circle.hexagongrid',
  Icons.image_search_rounded: 'photo',
  Icons.info_outline_rounded: 'info.circle',
  Icons.insights_rounded: 'waveform.path.ecg',
  Icons.share_rounded: 'square.and.arrow.up',
  Icons.wifi_tethering_rounded: 'antenna.radiowaves.left.and.right',
  Icons.language_rounded: 'globe',
  Icons.library_music_rounded: 'music.note.list',
  Icons.link_rounded: 'link',
  Icons.lock_outline_rounded: 'lock',
  Icons.more_horiz_rounded: 'ellipsis',
  Icons.more_vert_rounded: 'ellipsis',
  Icons.music_note_rounded: 'music.note',
  Icons.my_location_rounded: 'scope',
  Icons.network_check_rounded: 'wifi',
  Icons.open_in_new_rounded: 'arrow.up.right.square',
  Icons.pause_rounded: 'pause.fill',
  Icons.picture_in_picture_alt_rounded: 'rectangle.on.rectangle',
  Icons.play_arrow_rounded: 'play.fill',
  Icons.playlist_add_rounded: 'text.badge.plus',
  Icons.playlist_remove_rounded: 'text.badge.minus',
  Icons.queue_music_rounded: 'list.bullet',
  Icons.radio_button_checked_rounded: 'largecircle.fill.circle',
  Icons.radio_button_unchecked_rounded: 'circle',
  Icons.refresh_rounded: 'arrow.clockwise',
  Icons.restart_alt_rounded: 'arrow.counterclockwise',
  Icons.remove_circle_outline_rounded: 'minus.circle',
  Icons.repeat_one_rounded: 'repeat.1',
  Icons.save_rounded: 'tray.and.arrow.down',
  Icons.search_rounded: 'magnifyingglass',
  Icons.settings_rounded: 'gearshape',
  Icons.shuffle_rounded: 'shuffle',
  Icons.skip_next_rounded: 'forward.end.fill',
  Icons.skip_previous_rounded: 'backward.end.fill',
  Icons.sort_rounded: 'arrow.up.arrow.down',
  Icons.speed_rounded: 'speedometer',
  Icons.stop_rounded: 'stop.fill',
  Icons.swap_horiz_rounded: 'arrow.left.arrow.right',
  Icons.sync_rounded: 'arrow.triangle.2.circlepath',
  Icons.system_update_rounded: 'arrow.down.square',
  Icons.thumb_up_outlined: 'hand.thumbsup',
  Icons.tune_rounded: 'slider.horizontal.3',
  Icons.upload_file_rounded: 'arrow.up.doc',
  Icons.volume_down_rounded: 'speaker.wave.1.fill',
  Icons.volume_off_rounded: 'speaker.slash.fill',
  Icons.volume_up_rounded: 'speaker.wave.3.fill',
};
