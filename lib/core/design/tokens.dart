// ChatterLoop design tokens — mirrors webapp/src/reusables/design/theme.css.
// Two themes (light + dark), brand blue, Inter family, soft surfaces.

import 'package:flutter/material.dart';

class CLColors {
  // Brand
  static const brand = Color(0xFF1C7DEF);
  static const brand600 = Color(0xFF1769D1);
  static const brand700 = Color(0xFF1257B0);
  static const brandSoftLight = Color(0xFFE7F0FE);
  static const brand300 = Color(0xFF9CC2FF);

  // Accents
  static const green = Color(0xFF20BD7C);
  static const greenSoftLight = Color(0xFFE2F7EE);
  static const gold = Color(0xFFE69500);
  static const goldSoftLight = Color(0xFFFFF2DB);
  static const pink = Color(0xFFFF5B6B);
  static const pinkSoftLight = Color(0xFFFFE6E9);
  static const online = Color(0xFF2ECC71);

  // Calling - matches webapp/src/styles/styles.css's calls_v2 rules
  // exactly (.div_video_blocks's background, .btn_call_controls_enable's
  // background, .btn_call_controls_end's background) rather than reusing
  // the general palette above, since the call screen is intentionally
  // styled to look identical to webapp's call window regardless of theme.
  static const callTile = Color(0xFF3D4043);
  static const callControlOff = Color(0xFF888888);
  static const callEnd = Color(0xFFFF0000);

  // Light surfaces
  static const bgLight = Color(0xFFEEF1F5);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFF6F8FB);
  static const surface3Light = Color(0xFFECEFF3);
  static const inputLight = Color(0xFFEEF1F5);
  static const borderLight = Color(0xFFE3E6EB);
  static const border2Light = Color(0xFFD7DBE2);
  static const textLight = Color(0xFF14161A);
  static const text2Light = Color(0xFF5B606B);
  static const text3Light = Color(0xFF8B909B);

  // Dark surfaces
  static const bgDark = Color(0xFF0B0E14);
  static const surfaceDark = Color(0xFF151A23);
  static const surface2Dark = Color(0xFF1B2230);
  static const surface3Dark = Color(0xFF222A3A);
  static const inputDark = Color(0xFF1B2230);
  static const borderDark = Color(0xFF262F3F);
  static const border2Dark = Color(0xFF313C50);
  static const textDark = Color(0xFFE8EBF1);
  static const text2Dark = Color(0xFF99A1B1);
  static const text3Dark = Color(0xFF6B7488);
}

/// The app's type scale. Every piece of UI text picks a step from here instead
/// of an ad-hoc literal.
///
/// The steps are the ones the redesigned Notifications screen established, and
/// the rest of the app was unified onto them - before this the app used ~21
/// distinct sizes (9, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15,
/// 16, 17, 18, 19, 20, 22, 24, 26, 40), most of them one-offs that only
/// differed from a neighbour by half a point.
///
/// Sizes only, deliberately not whole TextStyles: weight and colour vary
/// independently of size at every step (a [title] is w700 on `p.text` in a row
/// but w600 on `p.text2` in a chip), so bundling them would need a token per
/// combination rather than per step.
///
/// EMOJI are deliberately NOT tokenized. A mood glyph or a reaction is content
/// sized to its container, not text in the hierarchy, so those keep literals.
class CLType {
  // ─── Body scale ──────────────────────────────────────────────────────────

  /// A section heading inside a screen - "Activity", "Group chats", "People".
  static const double sectionTitle = 15;

  /// A row's or card's primary line: a person's name, a conversation title.
  /// Also the step for text the user actually READS at length - a message
  /// bubble, a post caption, a diary entry - and for text they type into a
  /// field. Those want the largest comfortable body step, not the densest.
  static const double title = 14;

  /// Default running text.
  static const double body = 13.5;

  /// Denser running text - for rows that must also fit an action beside it.
  static const double bodySm = 13;

  /// Buttons, chips and inline links ("See all 38").
  static const double label = 12.5;

  /// The secondary line under a title - handles, counts, descriptions.
  static const double caption = 12;

  /// Timestamps and badge counts; the smallest step that stays readable.
  static const double meta = 11;

  // ─── Display scale ───────────────────────────────────────────────────────
  // Above the body scale, for text that IS a screen's heading rather than
  // content inside one.

  /// Every screen title, app-wide: the tab bar's header, each AppBar, dialog
  /// titles, empty-state headings. Deliberately ONE size - an ordinary screen
  /// and a pushed detail screen reading at the same weight is most of what
  /// makes them feel like the same app. Also the size the mobile design
  /// specifies for a top bar.
  static const double screenTitle = 17;

  /// A line that owns its whole screen - the wordmark and headings on the auth
  /// screens, a caller's name mid-call.
  static const double hero = 24;

  /// The marketing headline on the brand panel, and the single giant avatar
  /// initial on the incoming-call screen.
  static const double display = 40;
}

class CLRadii {
  static const xs = 8.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

class CLSpacing {
  static const railWidth = 76.0;
  static const headerHeight = 60.0;
  static const bottomnavHeight = 60.0;
}

/// Per-theme palette accessed via Theme.of(context).extension<CLPalette>()
@immutable
class CLPalette extends ThemeExtension<CLPalette> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color surfaceHover;
  final Color input;
  final Color border;
  final Color border2;
  final Color text;
  final Color text2;
  final Color text3;
  final Color brand;
  final Color brandSoft;
  final Color green;
  final Color greenSoft;
  final Color gold;
  final Color goldSoft;
  final Color pink;
  final Color pinkSoft;
  final Color online;
  final LinearGradient rail;
  final Color railIcon;
  final Color railIconActive;
  final Color railActiveBg;

  const CLPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.surfaceHover,
    required this.input,
    required this.border,
    required this.border2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.brand,
    required this.brandSoft,
    required this.green,
    required this.greenSoft,
    required this.gold,
    required this.goldSoft,
    required this.pink,
    required this.pinkSoft,
    required this.online,
    required this.rail,
    required this.railIcon,
    required this.railIconActive,
    required this.railActiveBg,
  });

  static const light = CLPalette(
    bg: CLColors.bgLight,
    surface: CLColors.surfaceLight,
    surface2: CLColors.surface2Light,
    surface3: CLColors.surface3Light,
    surfaceHover: Color(0xFFF0F2F6),
    input: CLColors.inputLight,
    border: CLColors.borderLight,
    border2: CLColors.border2Light,
    text: CLColors.textLight,
    text2: CLColors.text2Light,
    text3: CLColors.text3Light,
    brand: CLColors.brand,
    brandSoft: CLColors.brandSoftLight,
    green: CLColors.green,
    greenSoft: CLColors.greenSoftLight,
    gold: CLColors.gold,
    goldSoft: CLColors.goldSoftLight,
    pink: CLColors.pink,
    pinkSoft: CLColors.pinkSoftLight,
    online: CLColors.online,
    rail: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [CLColors.brand, Color(0xFF1466CF)],
    ),
    railIcon: Color(0xCCFFFFFF),
    railIconActive: CLColors.brand,
    railActiveBg: Color(0xFFFFFFFF),
  );

  static const dark = CLPalette(
    bg: CLColors.bgDark,
    surface: CLColors.surfaceDark,
    surface2: CLColors.surface2Dark,
    surface3: CLColors.surface3Dark,
    surfaceHover: Color(0xFF1E2532),
    input: CLColors.inputDark,
    border: CLColors.borderDark,
    border2: CLColors.border2Dark,
    text: CLColors.textDark,
    text2: CLColors.text2Dark,
    text3: CLColors.text3Dark,
    brand: CLColors.brand,
    brandSoft: Color(0x293C8BFF),
    green: CLColors.green,
    greenSoft: Color(0x2920BD7C),
    gold: CLColors.gold,
    goldSoft: Color(0x29E69500),
    pink: CLColors.pink,
    pinkSoft: Color(0x29FF5B6B),
    online: CLColors.online,
    rail: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF14233B), Color(0xFF0F1A2E)],
    ),
    railIcon: Color(0x9DFFFFFF),
    railIconActive: Color(0xFFFFFFFF),
    railActiveBg: Color(0x383C8BFF),
  );

  @override
  CLPalette copyWith() => this;

  @override
  CLPalette lerp(ThemeExtension<CLPalette>? other, double t) {
    if (other is! CLPalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// Helper to read the palette from any BuildContext.
CLPalette cl(BuildContext context) =>
    Theme.of(context).extension<CLPalette>() ?? CLPalette.light;

/// The Chatterloop wordmark asset for the current theme. The `-dark` variant
/// reads on dark surfaces - matches webapp's
/// `theme === "dark" ? ChatterLoopDarkImg : ChatterLoopImg`.
String clLogoAsset(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/chatterloop-dark.png'
        : 'assets/images/chatterloop.png';

ThemeData buildCLTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? CLPalette.dark : CLPalette.light;
  final base =
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: p.brand,
      secondary: p.green,
      surface: p.surface,
      error: p.pink,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: p.text,
      displayColor: p.text,
    ),
    iconTheme: IconThemeData(color: p.text2),
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      // Set explicitly, or every AppBar falls back to Material's titleLarge
      // (22) - which made a pushed screen's header noticeably bigger than the
      // tab bar's own header on the screen it was pushed from. One screen-title
      // size, everywhere.
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: CLType.screenTitle,
        fontWeight: FontWeight.w700,
        color: p.text,
      ),
    ),
  );
}
