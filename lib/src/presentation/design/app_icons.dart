import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart' show IconData;

/// One icon family for the whole app: the SF Symbols look that iOS draws
/// its own bars with, from Flutter's Cupertino icon font. Pages use these
/// names instead of picking Material or Cupertino glyphs one by one, so the
/// same meaning always has the same drawing on every platform.
abstract final class AppIcons {
  static const IconData add = CupertinoIcons.add;
  static const IconData addPhoto = CupertinoIcons.photo_on_rectangle;
  static const IconData photos = CupertinoIcons.photo_on_rectangle;
  static const IconData record = CupertinoIcons.music_note_2;
  static const IconData back = CupertinoIcons.back;
  static const IconData dropDown = CupertinoIcons.chevron_down;
  static const IconData forward = CupertinoIcons.arrow_right;
  static const IconData sparkles = CupertinoIcons.sparkles;
  static const IconData chart = CupertinoIcons.chart_bar;
  static const IconData bug = CupertinoIcons.ant;
  static const IconData calendar = CupertinoIcons.calendar;
  static const IconData cancel = CupertinoIcons.xmark_circle;
  static const IconData clearField = CupertinoIcons.xmark_circle_fill;
  static const IconData comment = CupertinoIcons.chat_bubble;
  static const IconData comments = CupertinoIcons.chat_bubble_2;
  static const IconData check = CupertinoIcons.checkmark;
  static const IconData checkCircleFill = CupertinoIcons.checkmark_circle_fill;
  static const IconData checkCircle = CupertinoIcons.checkmark_circle;
  static const IconData checklist = CupertinoIcons.checkmark_square;
  static const IconData paint = CupertinoIcons.paintbrush;
  static const IconData chevronLeft = CupertinoIcons.chevron_left;
  static const IconData chevronRight = CupertinoIcons.chevron_right;
  static const IconData chevronUp = CupertinoIcons.chevron_up;
  static const IconData chevronDown = CupertinoIcons.chevron_down;
  static const IconData chevronUpDown = CupertinoIcons.chevron_up_chevron_down;
  static const IconData close = CupertinoIcons.xmark;
  static const IconData cloudDownload = CupertinoIcons.cloud_download;
  static const IconData cloud = CupertinoIcons.cloud;
  static const IconData copy = CupertinoIcons.doc_on_doc;
  static const IconData contrast = CupertinoIcons.circle_lefthalf_fill;
  static const IconData square = CupertinoIcons.square;
  static const IconData darkMode = CupertinoIcons.moon;
  static const IconData lightMode = CupertinoIcons.sun_max;
  static const IconData delete = CupertinoIcons.trash;
  static const IconData clearAll = CupertinoIcons.trash_circle;
  static const IconData devices = CupertinoIcons.desktopcomputer;
  static const IconData server = CupertinoIcons.square_stack_3d_up;
  static const IconData storage = CupertinoIcons.archivebox;
  static const IconData scan = CupertinoIcons.doc_text_viewfinder;
  static const IconData download = CupertinoIcons.arrow_down_circle;
  static const IconData downloaded = CupertinoIcons.arrow_down_circle_fill;
  static const IconData saveTo = CupertinoIcons.square_arrow_down;
  static const IconData reorder = CupertinoIcons.line_horizontal_3;
  static const IconData edit = CupertinoIcons.pencil;
  static const IconData error = CupertinoIcons.exclamationmark_circle;
  static const IconData warning = CupertinoIcons.exclamationmark_triangle;
  static const IconData heartFill = CupertinoIcons.heart_fill;
  static const IconData heart = CupertinoIcons.heart;
  static const IconData filterFill =
      CupertinoIcons.line_horizontal_3_decrease_circle_fill;
  static const IconData filter =
      CupertinoIcons.line_horizontal_3_decrease_circle;
  static const IconData filterList = CupertinoIcons.line_horizontal_3_decrease;
  static const IconData folder = CupertinoIcons.folder;
  static const IconData quality = CupertinoIcons.waveform;
  static const IconData history = CupertinoIcons.clock;
  static const IconData home = CupertinoIcons.house;
  static const IconData source = CupertinoIcons.circle_grid_hex;
  static const IconData imageSearch = CupertinoIcons.photo;
  static const IconData info = CupertinoIcons.info_circle;
  static const IconData insights = CupertinoIcons.waveform_path_ecg;
  static const IconData share = CupertinoIcons.share;
  static const IconData lan = CupertinoIcons.antenna_radiowaves_left_right;
  static const IconData language = CupertinoIcons.globe;
  static const IconData library = CupertinoIcons.music_albums;
  static const IconData link = CupertinoIcons.link;
  static const IconData lock = CupertinoIcons.lock;
  static const IconData lyrics = CupertinoIcons.text_quote;
  static const IconData more = CupertinoIcons.ellipsis;
  static const IconData moreVertical = CupertinoIcons.ellipsis_vertical;
  static const IconData music = CupertinoIcons.music_note;
  static const IconData locate = CupertinoIcons.scope;
  static const IconData network = CupertinoIcons.wifi;
  static const IconData openExternal = CupertinoIcons.arrow_up_right_square;
  static const IconData pause = CupertinoIcons.pause_fill;
  static const IconData miniWindow = CupertinoIcons.rectangle_on_rectangle;
  static const IconData play = CupertinoIcons.play_fill;
  static const IconData playlistAdd = CupertinoIcons.text_badge_plus;
  static const IconData playlistRemove = CupertinoIcons.text_badge_minus;

  /// The play queue: a plain list, as in the iOS bar.
  static const IconData queue = CupertinoIcons.list_bullet;

  /// A playlist, its cover placeholder and its rows.
  static const IconData playlist = CupertinoIcons.music_note_list;

  /// Playing a list in order.
  static const IconData sequential = CupertinoIcons.list_number;
  static const IconData radioOn = CupertinoIcons.largecircle_fill_circle;
  static const IconData radioOff = CupertinoIcons.circle;
  static const IconData refresh = CupertinoIcons.arrow_clockwise;
  static const IconData restart = CupertinoIcons.arrow_counterclockwise;
  static const IconData remove = CupertinoIcons.minus_circle;
  static const IconData repeatOne = CupertinoIcons.repeat_1;
  static const IconData save = CupertinoIcons.tray_arrow_down;
  static const IconData search = CupertinoIcons.search;
  static const IconData settings = CupertinoIcons.gear_alt;
  static const IconData shuffle = CupertinoIcons.shuffle;
  static const IconData next = CupertinoIcons.forward_end_fill;
  static const IconData previous = CupertinoIcons.backward_end_fill;
  static const IconData sort = CupertinoIcons.arrow_up_arrow_down;
  static const IconData speed = CupertinoIcons.speedometer;
  static const IconData stop = CupertinoIcons.stop_fill;
  static const IconData swap = CupertinoIcons.arrow_right_arrow_left;
  static const IconData sync = CupertinoIcons.arrow_2_circlepath;
  static const IconData update = CupertinoIcons.arrow_down_square;
  static const IconData like = CupertinoIcons.hand_thumbsup;
  static const IconData tune = CupertinoIcons.slider_horizontal_3;
  static const IconData upload = CupertinoIcons.arrow_up_doc;
  static const IconData volumeLow = CupertinoIcons.speaker_1_fill;
  static const IconData volumeOff = CupertinoIcons.speaker_slash_fill;
  static const IconData volumeHigh = CupertinoIcons.speaker_3_fill;
}

/// SF Symbols for [AppIcons], so the iOS shell shows the real system
/// symbol for an icon a page puts in its bar.
final appIconSymbols = <IconData, String>{
  CupertinoIcons.add: 'plus',
  CupertinoIcons.photo_on_rectangle: 'photo.on.rectangle',
  CupertinoIcons.music_note_2: 'music.note',
  CupertinoIcons.back: 'chevron.backward',
  CupertinoIcons.chevron_down: 'chevron.down',
  CupertinoIcons.arrow_right: 'arrow.right',
  CupertinoIcons.sparkles: 'sparkles',
  CupertinoIcons.chart_bar: 'chart.bar',
  CupertinoIcons.ant: 'ladybug',
  CupertinoIcons.calendar: 'calendar',
  CupertinoIcons.xmark_circle: 'xmark.circle',
  CupertinoIcons.xmark_circle_fill: 'xmark.circle.fill',
  CupertinoIcons.chat_bubble: 'bubble.left',
  CupertinoIcons.chat_bubble_2: 'bubble.left.and.bubble.right',
  CupertinoIcons.checkmark: 'checkmark',
  CupertinoIcons.checkmark_circle_fill: 'checkmark.circle.fill',
  CupertinoIcons.checkmark_circle: 'checkmark.circle',
  CupertinoIcons.checkmark_square: 'checkmark.square',
  CupertinoIcons.paintbrush: 'paintbrush',
  CupertinoIcons.chevron_left: 'chevron.left',
  CupertinoIcons.chevron_right: 'chevron.right',
  CupertinoIcons.chevron_up: 'chevron.up',
  CupertinoIcons.chevron_up_chevron_down: 'chevron.up.chevron.down',
  CupertinoIcons.xmark: 'xmark',
  CupertinoIcons.cloud_download: 'icloud.and.arrow.down',
  CupertinoIcons.cloud: 'icloud',
  CupertinoIcons.doc_on_doc: 'doc.on.doc',
  CupertinoIcons.circle_lefthalf_fill: 'circle.lefthalf.filled',
  CupertinoIcons.square: 'square',
  CupertinoIcons.moon: 'moon',
  CupertinoIcons.sun_max: 'sun.max',
  CupertinoIcons.trash: 'trash',
  CupertinoIcons.trash_circle: 'trash.circle',
  CupertinoIcons.desktopcomputer: 'desktopcomputer',
  CupertinoIcons.square_stack_3d_up: 'square.stack.3d.up',
  CupertinoIcons.archivebox: 'archivebox',
  CupertinoIcons.doc_text_viewfinder: 'doc.text.viewfinder',
  CupertinoIcons.arrow_down_circle: 'arrow.down.circle',
  CupertinoIcons.arrow_down_circle_fill: 'arrow.down.circle.fill',
  CupertinoIcons.square_arrow_down: 'square.and.arrow.down',
  CupertinoIcons.line_horizontal_3: 'line.3.horizontal',
  CupertinoIcons.pencil: 'pencil',
  CupertinoIcons.exclamationmark_circle: 'exclamationmark.circle',
  CupertinoIcons.exclamationmark_triangle: 'exclamationmark.triangle',
  CupertinoIcons.heart_fill: 'heart.fill',
  CupertinoIcons.heart: 'heart',
  CupertinoIcons.line_horizontal_3_decrease_circle_fill:
      'line.3.horizontal.decrease.circle.fill',
  CupertinoIcons.line_horizontal_3_decrease_circle:
      'line.3.horizontal.decrease.circle',
  CupertinoIcons.line_horizontal_3_decrease: 'line.3.horizontal.decrease',
  CupertinoIcons.folder: 'folder',
  CupertinoIcons.waveform: 'waveform',
  CupertinoIcons.clock: 'clock',
  CupertinoIcons.house: 'house',
  CupertinoIcons.circle_grid_hex: 'circle.hexagongrid',
  CupertinoIcons.photo: 'photo',
  CupertinoIcons.info_circle: 'info.circle',
  CupertinoIcons.waveform_path_ecg: 'waveform.path.ecg',
  CupertinoIcons.share: 'square.and.arrow.up',
  CupertinoIcons.antenna_radiowaves_left_right:
      'antenna.radiowaves.left.and.right',
  CupertinoIcons.globe: 'globe',
  CupertinoIcons.music_albums: 'music.note.list',
  CupertinoIcons.link: 'link',
  CupertinoIcons.lock: 'lock',
  CupertinoIcons.text_quote: 'quote.bubble',
  CupertinoIcons.ellipsis: 'ellipsis',
  CupertinoIcons.ellipsis_vertical: 'ellipsis',
  CupertinoIcons.music_note: 'music.note',
  CupertinoIcons.scope: 'scope',
  CupertinoIcons.wifi: 'wifi',
  CupertinoIcons.arrow_up_right_square: 'arrow.up.right.square',
  CupertinoIcons.pause_fill: 'pause.fill',
  CupertinoIcons.rectangle_on_rectangle: 'rectangle.on.rectangle',
  CupertinoIcons.play_fill: 'play.fill',
  CupertinoIcons.text_badge_plus: 'text.badge.plus',
  CupertinoIcons.text_badge_minus: 'text.badge.minus',
  CupertinoIcons.list_bullet: 'list.bullet',
  CupertinoIcons.music_note_list: 'music.note.list',
  CupertinoIcons.list_number: 'list.number',
  CupertinoIcons.largecircle_fill_circle: 'largecircle.fill.circle',
  CupertinoIcons.circle: 'circle',
  CupertinoIcons.arrow_clockwise: 'arrow.clockwise',
  CupertinoIcons.arrow_counterclockwise: 'arrow.counterclockwise',
  CupertinoIcons.minus_circle: 'minus.circle',
  CupertinoIcons.repeat_1: 'repeat.1',
  CupertinoIcons.tray_arrow_down: 'tray.and.arrow.down',
  CupertinoIcons.search: 'magnifyingglass',
  CupertinoIcons.gear_alt: 'gearshape',
  CupertinoIcons.shuffle: 'shuffle',
  CupertinoIcons.forward_end_fill: 'forward.end.fill',
  CupertinoIcons.backward_end_fill: 'backward.end.fill',
  CupertinoIcons.arrow_up_arrow_down: 'arrow.up.arrow.down',
  CupertinoIcons.speedometer: 'speedometer',
  CupertinoIcons.stop_fill: 'stop.fill',
  CupertinoIcons.arrow_right_arrow_left: 'arrow.left.arrow.right',
  CupertinoIcons.arrow_2_circlepath: 'arrow.triangle.2.circlepath',
  CupertinoIcons.arrow_down_square: 'arrow.down.square',
  CupertinoIcons.hand_thumbsup: 'hand.thumbsup',
  CupertinoIcons.slider_horizontal_3: 'slider.horizontal.3',
  CupertinoIcons.arrow_up_doc: 'arrow.up.doc',
  CupertinoIcons.speaker_1_fill: 'speaker.wave.1.fill',
  CupertinoIcons.speaker_slash_fill: 'speaker.slash.fill',
  CupertinoIcons.speaker_3_fill: 'speaker.wave.3.fill',
};
