import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/music_settings.dart';
import 'design/ambient_backdrop.dart';

/// The looks the app can wear. Day and night are the originals.
enum MusicSkin { day, night, neon, berry, riso, aurora, silver }

/// Edit these palettes to recolor every screen, dialog and player together.
///
/// The look is a listening room. By night it is warm black lit by an amber
/// valve glow; by day it is cream paper with a fresh leaf green for the few lit
/// things.
/// Each mode has one lit color, and nothing is neutral grey or pure white.
class MusicPalette {
  const MusicPalette({
    required this.ink,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.panel,
    required this.tint,
    required this.field,
    required this.text,
    required this.muted,
    required this.line,
    required this.label,
    required this.brass,
    required this.vinyl,
    required this.glass,
    required this.sheen,
    required this.haze,
    this.skin = MusicSkin.night,
    this.gun = const Color(0xFF2B2826),
  });

  final Color ink, accent, onAccent, background, panel, tint, field;
  final Color text, muted, line;

  /// Colors with no ColorScheme role: record-label red, tonearm metal, the
  /// disc itself, the smoked-glass tint and the light that catches its edge.
  final Color label, brass, vinyl, glass, sheen;

  /// Which look this is. Textures and materials that colors alone cannot
  /// express branch on it.
  final MusicSkin skin;

  bool get neon => skin == MusicSkin.neon;

  /// The dark metal of the tonearm's pivot and counterweight.
  final Color gun;

  /// The room's second light when no artwork colors it; [accent] is the first.
  final Color haze;

  static const light = MusicPalette(
    ink: Color(0xFF47761C),
    accent: Color(0xFFA6D06F),
    onAccent: Color(0xFF1E3609),
    background: Color(0xFFFAF7F1),
    panel: Color(0xFFFFFDF8),
    tint: Color(0xFFE2F0CD),
    field: Color(0xFFF1EBDF),
    text: Color(0xFF23262B),
    muted: Color(0xFF6A6E73),
    line: Color(0xFFE6DECF),
    label: Color(0xFFD9573C),
    brass: Color(0xFFB09A68),
    vinyl: Color(0xFF14110F),
    glass: Color(0xFFFFFDF9),
    sheen: Color(0xFFFFFFFF),
    haze: Color(0xFFF3E6CE),
    skin: MusicSkin.day,
  );

  static const dark = MusicPalette(
    ink: Color(0xFFF2B866),
    accent: Color(0xFFE8A33D),
    onAccent: Color(0xFF2B1A04),
    background: Color(0xFF100E0C),
    panel: Color(0xFF1C1915),
    tint: Color(0xFF362A18),
    field: Color(0xFF27231E),
    text: Color(0xFFF4EDE0),
    muted: Color(0xFFA89E8F),
    line: Color(0xFF332D26),
    label: Color(0xFFD9573C),
    brass: Color(0xFFCDB98F),
    vinyl: Color(0xFF0B0A09),
    glass: Color(0xFF1A1613),
    sheen: Color(0xFFFFF4E0),
    haze: Color(0xFFD9573C),
  );

  /// Neon rain: a wet street under signs. Magenta is the lit color, cyan the
  /// second light, warning yellow marks favorites.
  static const neonRain = MusicPalette(
    ink: Color(0xFFFF7AB8),
    accent: Color(0xFFFF3D9A),
    onAccent: Color(0xFF2A0018),
    background: Color(0xFF0A0714),
    panel: Color(0xFF15102A),
    tint: Color(0xFF3A1242),
    field: Color(0xFF1D1638),
    text: Color(0xFFEDE9FF),
    muted: Color(0xFF9088B8),
    line: Color(0xFF2A2148),
    label: Color(0xFFF7E733),
    brass: Color(0xFFB9C4E8),
    vinyl: Color(0xFF0D0A1C),
    glass: Color(0xFF130E26),
    sheen: Color(0xFF9AF6FF),
    haze: Color(0xFF19E3F0),
    skin: MusicSkin.neon,
    gun: Color(0xFF1B1630),
  );

  /// Strawberry milk: pink-tinted milk white, pearly, with cocoa text.
  static const berry = MusicPalette(
    ink: Color(0xFFC72660),
    accent: Color(0xFFFF8FAB),
    onAccent: Color(0xFF5A0F2A),
    background: Color(0xFFFFF3F1),
    panel: Color(0xFFFFFBFA),
    tint: Color(0xFFFFD9E2),
    field: Color(0xFFFBE4E3),
    text: Color(0xFF4A2B36),
    muted: Color(0xFF8A6170),
    line: Color(0xFFF5D5D6),
    label: Color(0xFFE5484D),
    brass: Color(0xFFE0A893),
    vinyl: Color(0xFFFF9DB8),
    glass: Color(0xFFFFFFFF),
    sheen: Color(0xFFFFFFFF),
    haze: Color(0xFFFFE3A8),
    skin: MusicSkin.berry,
    gun: Color(0xFFD39A88),
  );

  /// Riso print: recycled paper and two inks, Klein blue and fluorescent
  /// orange. Nothing is glass; everything is a cut piece of paper.
  static const riso = MusicPalette(
    ink: Color(0xFF2437FF),
    accent: Color(0xFF2437FF),
    onAccent: Color(0xFFF8F5EC),
    background: Color(0xFFEFEBE0),
    panel: Color(0xFFF8F5EC),
    tint: Color(0xFFD7DCFF),
    field: Color(0xFFE2DED2),
    text: Color(0xFF14194D),
    muted: Color(0xFF5A5F86),
    line: Color(0xFFCFCABB),
    label: Color(0xFFFF5B2E),
    brass: Color(0xFFB9B4A6),
    vinyl: Color(0xFF171C5C),
    glass: Color(0xFFF8F5EC),
    sheen: Color(0xFFFFFFFF),
    haze: Color(0xFFFF5B2E),
    skin: MusicSkin.riso,
    gun: Color(0xFF14194D),
  );

  /// Aurora: a polar night, green light hanging from the sky, ice for glass.
  static const aurora = MusicPalette(
    ink: Color(0xFF7DF0CF),
    accent: Color(0xFF5FE3B3),
    onAccent: Color(0xFF022C22),
    background: Color(0xFF06141A),
    panel: Color(0xFF0E2229),
    tint: Color(0xFF12403C),
    field: Color(0xFF14303A),
    text: Color(0xFFE6F4F1),
    muted: Color(0xFF88A5A6),
    line: Color(0xFF1D3A42),
    label: Color(0xFFFF8FA3),
    brass: Color(0xFFC7D6DC),
    vinyl: Color(0xFF0B2A33),
    glass: Color(0xFF0C2028),
    sheen: Color(0xFFCFFFF4),
    haze: Color(0xFF7C5CFF),
    skin: MusicSkin.aurora,
    gun: Color(0xFF17333B),
  );

  /// Silver face: a seventies amplifier in brushed aluminium, black
  /// lettering, one signal-orange lamp.
  static const silver = MusicPalette(
    ink: Color(0xFFA63A0C),
    accent: Color(0xFFFF6A2B),
    onAccent: Color(0xFF2A0E00),
    background: Color(0xFFDBDAD6),
    panel: Color(0xFFE9E8E4),
    tint: Color(0xFFF3E5C8),
    field: Color(0xFFC9C8C4),
    text: Color(0xFF1C1D1F),
    muted: Color(0xFF5B5E63),
    line: Color(0xFFBDBCB8),
    label: Color(0xFFD62F2F),
    brass: Color(0xFFE6E7E9),
    vinyl: Color(0xFF121212),
    glass: Color(0xFF17181A),
    sheen: Color(0xFFFFFFFF),
    haze: Color(0xFFFFE2A6),
    skin: MusicSkin.silver,
    gun: Color(0xFF2E2F32),
  );

  /// The palette a saved appearance stands for.
  static MusicPalette of(AppThemePreference theme) => switch (theme) {
    AppThemePreference.light => light,
    AppThemePreference.dark => dark,
    AppThemePreference.neon => neonRain,
    AppThemePreference.berry => berry,
    AppThemePreference.riso => riso,
    AppThemePreference.aurora => aurora,
    AppThemePreference.silver => silver,
  };

  static MusicPalette lerp(MusicPalette a, MusicPalette b, double t) {
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return MusicPalette(
      ink: mix(a.ink, b.ink),
      accent: mix(a.accent, b.accent),
      onAccent: mix(a.onAccent, b.onAccent),
      background: mix(a.background, b.background),
      panel: mix(a.panel, b.panel),
      tint: mix(a.tint, b.tint),
      field: mix(a.field, b.field),
      text: mix(a.text, b.text),
      muted: mix(a.muted, b.muted),
      line: mix(a.line, b.line),
      label: mix(a.label, b.label),
      brass: mix(a.brass, b.brass),
      vinyl: mix(a.vinyl, b.vinyl),
      glass: mix(a.glass, b.glass),
      sheen: mix(a.sheen, b.sheen),
      haze: mix(a.haze, b.haze),
      skin: t < .5 ? a.skin : b.skin,
      gun: mix(a.gun, b.gun),
    );
  }
}

/// Carries the whole palette through Theme for the vinyl and glass components.
class MusicTokens extends ThemeExtension<MusicTokens> {
  const MusicTokens(this.palette);

  final MusicPalette palette;

  static MusicPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MusicTokens>()?.palette ??
        (theme.brightness == Brightness.dark
            ? MusicPalette.dark
            : MusicPalette.light);
  }

  @override
  MusicTokens copyWith({MusicPalette? palette}) =>
      MusicTokens(palette ?? this.palette);

  @override
  MusicTokens lerp(MusicTokens? other, double t) => other == null
      ? this
      : MusicTokens(MusicPalette.lerp(palette, other.palette, t));
}

/// Shared geometry. Colors belong to ColorScheme, never individual pages.
abstract final class MusicUi {
  static const pagePadding = 20.0;
  static const radius = 18.0;
  static const fieldRadius = 16.0;
  static const coverRadius = 12.0;
  static const sectionGap = 24.0;
  static const playerCoverMaxWidth = 320.0;

  /// Printed matter keeps crisp corners; glass and hardware are round.
  static const sleeveRadius = 6.0;
  static const glassRadius = 28.0;
  static const controlRadius = 14.0;
  static const miniPlayerInsets = EdgeInsets.fromLTRB(14, 6, 14, 6);
  static const pageInsets = EdgeInsets.fromLTRB(20, 16, 20, 24);
  static const horizontalInsets = EdgeInsets.symmetric(horizontal: pagePadding);
  static EdgeInsets scrollInsets(
    BuildContext context, {
    EdgeInsets base = pageInsets,
  }) =>
      base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);

  static bool compactActions(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 420 ||
      MediaQuery.textScalerOf(context).scale(14) > 18;
}

/// Shared timing. Springs answer touch; curves move layout.
abstract final class MusicMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 460);
  static const standard = Curves.easeOutCubic;
  static const emphasized = Cubic(.2, 0, 0, 1);
  static const snappy = SpringDescription(mass: 1, stiffness: 420, damping: 32);
  static const bouncy = SpringDescription(mass: 1, stiffness: 260, damping: 18);

  /// One turn of a playing record: 33⅓ rpm slowed until the label stays
  /// readable. The platter needs [spinUp] to reach it and [spinDown] to coast.
  static const revolution = Duration(seconds: 8);
  static const spinUp = Duration(milliseconds: 280);
  static const spinDown = Duration(milliseconds: 700);
  static const toneArm = Duration(milliseconds: 320);

  /// Widget tests turn this off so pumpAndSettle is not held open by a record
  /// that never stops.
  static bool perpetual = true;

  static bool allowsPerpetual(BuildContext context) =>
      perpetual && !MediaQuery.disableAnimationsOf(context);
}

/// Three voices: sleeve print (serif), system text, and the engraved lettering
/// of a hi-fi faceplate. The families ship with iOS; elsewhere the fallbacks
/// keep the same roles.
abstract final class MusicType {
  static const display = 'Bodoni 72';
  static const displayFallback = ['Didot', 'PingFang SC', 'serif'];
  static const engraved = 'DIN Alternate';
  static const engravedFallback = [
    'DIN Condensed',
    'PingFang SC',
    'sans-serif-condensed',
  ];

  /// Page mastheads and the playing song.
  static TextStyle masthead(BuildContext context, {double size = 34}) =>
      TextStyle(
        fontFamily: display,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        wordSpacing: size * .09,
        color: Theme.of(context).colorScheme.onSurface,
        shadows: switch (MusicTokens.of(context)) {
          // Neon lettering glows.
          MusicPalette(skin: MusicSkin.neon, :final accent) => [
            Shadow(color: accent.withValues(alpha: .65), blurRadius: 14),
          ],
          // Printed off-register in the second ink.
          MusicPalette(skin: MusicSkin.riso, :final haze) => [
            Shadow(color: haze, offset: Offset(size * .07, size * .07)),
          ],
          // Engraved in metal: a light lip under each stroke.
          MusicPalette(skin: MusicSkin.silver) => const [
            Shadow(color: Color(0xCCFFFFFF), offset: Offset(0, 1)),
          ],
          _ => null,
        },
      );

  /// Small capitals above a section, like the text around a record label.
  static TextStyle eyebrow(BuildContext context) => TextStyle(
    fontFamily: engraved,
    fontFamilyFallback: engravedFallback,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    color: Theme.of(context).colorScheme.primary,
  );

  /// Times, counts and quality marks: figures that must not jitter.
  static TextStyle readout(BuildContext context, {double size = 12}) =>
      TextStyle(
        fontFamily: engraved,
        fontFamilyFallback: engravedFallback,
        fontSize: size,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

/// Hands a page's content to the platform's own transition (which keeps the
/// edge-swipe back gesture) with fades added; the backdrop is not part of it.
class _BackdropTransitions extends PageTransitionsBuilder {
  const _BackdropTransitions(this.platform);

  final PageTransitionsBuilder platform;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    // Animate opacity outside the platform's snapshot. Capturing the fades
    // inside Zoom freezes a partially visible page until the route settles.
    opacity: animation.drive(CurveTween(curve: const Interval(.15, .75))),
    child: FadeTransition(
      opacity: secondaryAnimation.drive(
        Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: const Interval(0, .45))),
      ),
      child: platform.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        BackdropScope(child: child),
      ),
    ),
  );
}

abstract final class MusicAppTheme {
  static SystemUiOverlayStyle systemOverlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Material tracks every style for Latin text, which only loosens CJK.
  static TextTheme _untracked(TextTheme theme) {
    TextStyle? flat(TextStyle? style) => style?.copyWith(letterSpacing: 0);
    return TextTheme(
      displayLarge: flat(theme.displayLarge),
      displayMedium: flat(theme.displayMedium),
      displaySmall: flat(theme.displaySmall),
      headlineLarge: flat(theme.headlineLarge),
      headlineMedium: flat(theme.headlineMedium),
      headlineSmall: flat(theme.headlineSmall),
      titleLarge: flat(theme.titleLarge),
      titleMedium: flat(theme.titleMedium),
      titleSmall: flat(theme.titleSmall),
      bodyLarge: flat(theme.bodyLarge),
      bodyMedium: flat(theme.bodyMedium),
      bodySmall: flat(theme.bodySmall),
      labelLarge: flat(theme.labelLarge),
      labelMedium: flat(theme.labelMedium),
      labelSmall: flat(theme.labelSmall),
    );
  }

  static ThemeData create(Brightness brightness, {MusicPalette? palette}) {
    final p =
        palette ??
        (brightness == Brightness.dark
            ? MusicPalette.dark
            : MusicPalette.light);
    // By night, cards and fields are smoked panes the room's light shows
    // through; only the lit color stays solid, so it sits in front of
    // everything. Dialogs, sheets and menus keep the solid [p.panel].
    final dark = brightness == Brightness.dark;
    final card = dark ? p.text.withValues(alpha: .055) : p.panel;
    final well = dark ? p.text.withValues(alpha: .085) : p.field;
    final selected = dark ? p.accent.withValues(alpha: .13) : p.tint;
    final colors =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.ink,
          onPrimary: brightness == Brightness.dark
              ? p.onAccent
              : MusicPalette.light.panel,
          primaryContainer: p.accent,
          onPrimaryContainer: p.onAccent,
          secondary: p.ink,
          secondaryContainer: p.tint,
          onSecondaryContainer: p.text,
          surface: p.background,
          surfaceContainerLowest: card,
          surfaceContainerLow: card,
          surfaceContainer: selected,
          surfaceContainerHigh: well,
          surfaceContainerHighest: well,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          outlineVariant: p.line,
          surfaceTint: Colors.transparent,
        );
    final base = ThemeData(colorScheme: colors, useMaterial3: true);
    final sized = base.textTheme
        .apply(bodyColor: p.text, displayColor: p.text)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: p.muted,
          ),
        );
    // Headings speak in the sleeve-print voice everywhere: page titles,
    // section heads and dialog titles.
    TextStyle? printed(TextStyle? style) => style?.copyWith(
      fontFamily: MusicType.display,
      fontFamilyFallback: MusicType.displayFallback,
      fontWeight: FontWeight.w700,
    );
    final flat = _untracked(sized);
    final text = flat.copyWith(
      headlineSmall: printed(flat.headlineSmall),
      titleLarge: printed(flat.titleLarge),
    );
    // Some skins draw a line around every pane.
    final edge = switch (p.skin) {
      MusicSkin.neon => BorderSide(color: p.haze.withValues(alpha: .16)),
      MusicSkin.aurora => BorderSide(color: p.sheen.withValues(alpha: .11)),
      // Paper pieces are cut out with an ink line.
      MusicSkin.riso => BorderSide(color: p.text, width: 1.4),
      _ => BorderSide.none,
    };
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MusicUi.fieldRadius),
      borderSide: edge,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      extensions: [MusicTokens(p)],
      textTheme: text,
      // Pages are see-through; one [PageBackdrop] sits behind the navigator.
      scaffoldBackgroundColor: Colors.transparent,
      // Every platform the SDK knows, including ones a fork adds: a page
      // without this builder would have no background at all.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: _BackdropTransitions(
              platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
                  ? const CupertinoPageTransitionsBuilder()
                  : const ZoomPageTransitionsBuilder(),
            ),
        },
      ),
      appBarTheme: AppBarTheme(
        // The bar is see-through, so say which status-bar icons to use.
        systemOverlayStyle: systemOverlayStyle(brightness),
        backgroundColor: Colors.transparent,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: MusicUi.pagePadding,
        toolbarHeight: 64,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MusicUi.radius),
          side: edge,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink,
        textColor: p.text,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 40,
        horizontalTitleGap: 12,
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: well,
        hintStyle: text.bodyLarge?.copyWith(color: p.muted),
        prefixIconColor: p.ink,
        suffixIconColor: p.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: field,
        enabledBorder: field,
        disabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: p.ink)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          minimumSize: const Size(48, 48),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.text,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: well,
        selectedColor: p.tint,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.bodySmall?.copyWith(color: p.text),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.panel,
        rangePickerBackgroundColor: p.panel,
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.ink,
        linearTrackColor: p.field,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: p.ink,
        thumbColor: p.ink,
        secondaryActiveTrackColor: p.text.withValues(alpha: .28),
        inactiveTrackColor: p.text.withValues(alpha: .08),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        modalBackgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: p.line,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
