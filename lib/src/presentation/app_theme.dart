import 'package:flutter/material.dart';

/// Edit these palettes to recolor every screen, dialog and player together.
///
/// The look is a listening room. By night it is warm black lit by an amber
/// valve glow; by day it is cream paper with a dusty sky blue for the few lit
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
  });

  final Color ink, accent, onAccent, background, panel, tint, field;
  final Color text, muted, line;

  /// Colors with no ColorScheme role: record-label red, tonearm metal, the
  /// disc itself, the smoked-glass tint and the light that catches its edge.
  final Color label, brass, vinyl, glass, sheen;

  /// The room's second light when no artwork colors it; [accent] is the first.
  final Color haze;

  static const light = MusicPalette(
    ink: Color(0xFF236A8C),
    accent: Color(0xFF7FB4CE),
    onAccent: Color(0xFF0E2B3A),
    background: Color(0xFFFAF7F1),
    panel: Color(0xFFFFFDF8),
    tint: Color(0xFFD6E8F0),
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
    haze: Color(0xFF7F3626),
  );

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
  static const miniPlayerRadius = 26.0;

  /// Printed matter keeps crisp corners; glass and hardware are round.
  static const sleeveRadius = 6.0;
  static const glassRadius = 28.0;
  static const controlRadius = 14.0;
  static const miniPlayerInsets = EdgeInsets.fromLTRB(12, 8, 12, 10);
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
  static const displayFallback = ['Source Han Serif CN', 'Didot', 'serif'];
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

abstract final class MusicAppTheme {
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
          surfaceContainerLowest: p.panel,
          surfaceContainerLow: p.panel,
          surfaceContainer: p.tint,
          surfaceContainerHigh: p.field,
          surfaceContainerHighest: p.field,
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
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MusicUi.fieldRadius),
      borderSide: BorderSide.none,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      extensions: [MusicTokens(p)],
      textTheme: text,
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
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
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MusicUi.radius),
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
        fillColor: p.field,
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
        backgroundColor: p.field,
        selectedColor: p.tint,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.bodySmall?.copyWith(color: p.text),
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
