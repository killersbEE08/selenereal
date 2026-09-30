import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Midnight & Gilt" design tokens.
///
/// A deep ink base (not pure black, so the art keeps its glow), one cool accent (lavender) for
/// interaction/selection and one warm accent (antique gold) reserved for the primary action and
/// Premium. Everything else is neutral, so the illustrations carry the colour instead of the chrome.
class AppColors {
  // Surfaces
  static const bg = Color(0xFF0A0916);
  static const bgTop = Color(0xFF191338);
  static const card = Color(0xE6121027);
  static const cardElevated = Color(0xFF1B1836);
  static const field = Color(0xFF110F24);
  static const border = Color(0x1FFFFFFF); // 12% hairline
  static const borderStrong = Color(0x33FFFFFF);

  // Accents
  static const glow = Color(0xFFC8B8FF); // lavender: selection, links, focus
  static const primary = Color(0xFF9784F2);
  static const primaryAlt = Color(0xFF5E4FC4);
  static const magenta = Color(0xFFF2A7C3); // soft rose, used sparingly
  static const gold = Color(0xFFE7C27D);
  static const goldDeep = Color(0xFFC9964E);
  static const onGold = Color(0xFF1B1430); // text/icons on gold

  // Text
  static const text = Color(0xFFF6F3FF);
  static const textSecondary = Color(0xFFB9B2D6);
  // ≥ 4.5:1 on bg, card and cardElevated (WCAG AA for small text).
  static const textMuted = Color(0xFF8F88AE);

  // Semantic / palm lines
  static const heart = Color(0xFFF28DA9);
  static const head = Color(0xFF7FB8F5);
  static const life = Color(0xFFF2B872);
  static const fate = Color(0xFFB9A2F7);
  static const success = Color(0xFF6FD6A8);
  static const warning = Color(0xFFF2B872);
  static const error = Color(0xFFF2788F);

  /// Primary call-to-action: warm gilt. Always paired with [onGold] text.
  static const cta = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF5DDAA), Color(0xFFDDAE66)]);

  /// Secondary emphasis (chat bubbles, active step): lavender → violet.
  static const violet = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA995F7), Color(0xFF6452CF)]);

  static const headingGradient = LinearGradient(colors: [Color(0xFFF7E6C4), Color(0xFFE2B36A)]);

  static const background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1440), Color(0xFF0D0B1E), bg],
    stops: [0, 0.42, 1],
  );

  static Color lineColor(String name) => switch (name) {
        'heart' => heart,
        'head' => head,
        'life' => life,
        _ => fate,
      };
}

class AppRadius {
  static const card = 22.0;
  static const nav = 30.0;
}

/// Display type: Fraunces (soft optical serif, a little mystical, very legible).
/// UI/body type: Plus Jakarta Sans (warm humanist sans that pairs with rounded line icons).
class AppType {
  static TextStyle display({double size = 34, FontWeight weight = FontWeight.w600, Color color = AppColors.text, FontStyle? style, double? height}) =>
      GoogleFonts.fraunces(fontSize: size, fontWeight: weight, color: color, fontStyle: style, height: height ?? 1.08, letterSpacing: -0.4);

  static TextStyle ui({double size = 14, FontWeight weight = FontWeight.w500, Color color = AppColors.text, double? height, double? spacing}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  /// Small caps-style overline ("STEP 2 OF 4", "TODAY").
  static TextStyle overline({Color color = AppColors.textMuted}) => ui(size: 11, weight: FontWeight.w700, color: color, spacing: 1.6);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final body = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.glow,
      onPrimary: AppColors.onGold,
      secondary: AppColors.gold,
      onSecondary: AppColors.onGold,
      surface: AppColors.cardElevated,
      error: AppColors.error,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: AppColors.gold, selectionColor: AppColors.glow.withValues(alpha: 0.35), selectionHandleColor: AppColors.gold),
    textTheme: body.copyWith(
      displaySmall: AppType.display(size: 38),
      headlineSmall: AppType.display(size: 25),
      titleLarge: AppType.ui(size: 19, weight: FontWeight.w700),
      titleMedium: AppType.ui(size: 16, weight: FontWeight.w700),
      bodyLarge: AppType.ui(size: 15.5, weight: FontWeight.w400, height: 1.5),
      bodyMedium: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
      bodySmall: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
      labelLarge: AppType.ui(size: 15, weight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      hintStyle: AppType.ui(size: 14.5, weight: FontWeight.w400, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.glow, 1.4),
      // On-brand validation styling instead of Material's default flat red.
      errorBorder: border(AppColors.error, 1.2),
      focusedErrorBorder: border(AppColors.error, 1.6),
      errorStyle: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.error),
      errorMaxLines: 2,
      helperStyle: AppType.ui(size: 12, weight: FontWeight.w400, color: AppColors.textMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
      contentTextStyle: AppType.ui(size: 14, color: AppColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF13112A),
      showDragHandle: true,
      dragHandleColor: AppColors.borderStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF16132F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: AppType.display(size: 22),
      contentTextStyle: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.glow, textStyle: AppType.ui(size: 14, weight: FontWeight.w600))),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold, linearTrackColor: AppColors.border),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.gold : Colors.transparent),
      checkColor: WidgetStateProperty.all(AppColors.onGold),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onGold : AppColors.textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.gold : AppColors.field),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : AppColors.borderStrong),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: const Color(0xFF16132F),
      headerBackgroundColor: const Color(0xFF1D1940),
      dayForegroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onGold : AppColors.text),
      dayBackgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.gold : Colors.transparent),
      todayForegroundColor: WidgetStateProperty.all(AppColors.gold),
      todayBorder: const BorderSide(color: AppColors.gold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    // Keep the time picker on-brand in dark mode (birth-time entry) instead of the default M3 purple.
    timePickerTheme: TimePickerThemeData(
      backgroundColor: const Color(0xFF16132F),
      hourMinuteColor: AppColors.field,
      hourMinuteTextColor: AppColors.text,
      dialHandColor: AppColors.gold,
      dialBackgroundColor: AppColors.field,
      dialTextColor: AppColors.text,
      dayPeriodColor: AppColors.gold.withValues(alpha: 0.22),
      dayPeriodTextColor: AppColors.text,
      dayPeriodBorderSide: const BorderSide(color: AppColors.border),
      entryModeIconColor: AppColors.textSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.borderStrong),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.cardElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
      textStyle: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.text),
    ),
    focusColor: AppColors.glow.withValues(alpha: 0.16),
    splashColor: AppColors.glow.withValues(alpha: 0.10),
    highlightColor: Colors.white.withValues(alpha: 0.03),
  );
}
