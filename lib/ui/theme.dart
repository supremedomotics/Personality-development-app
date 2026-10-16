import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

/// Semantic tokens from docs/DESIGN_SYSTEM.md. Widgets never use raw hex.
class Tokens {
  const Tokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.ok,
    required this.border,
  });
  final Color bg, surface, text, muted, accent, onAccent, danger, ok, border;

  static const dark = Tokens(
    bg: Color(0xFF0E1116),
    surface: Color(0xFF171B22),
    text: Color(0xFFECE8DF),
    muted: Color(0xFFA8AFBA),
    accent: Color(0xFFD4B16A),
    onAccent: Color(0xFF0E1116),
    danger: Color(0xFFE5877A),
    ok: Color(0xFF7FC3A0),
    border: Color(0xFF3A4350),
  );
  static const light = Tokens(
    bg: Color(0xFFF6F3EC),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF16191F),
    muted: Color(0xFF4A515C),
    accent: Color(0xFF7A5A14),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFA8321F),
    ok: Color(0xFF1F6B47),
    border: Color(0xFF8A8F98),
  );
}

extension TokensX on BuildContext {
  Tokens get t => Theme.of(this).brightness == Brightness.dark ? Tokens.dark : Tokens.light;
}

/// System serif for display until font files are bundled (the app must not
/// fetch fonts online). Tabular figures keep scores from jittering.
const kSerif = 'serif';

ThemeData buildTheme(Tokens t, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.danger,
    onError: t.bg,
    surface: t.surface,
    onSurface: t.text,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    appBarTheme: AppBarTheme(
        backgroundColor: t.bg, foregroundColor: t.text, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.border.withValues(alpha: 0.5))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: t.accent)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.accent, width: 2)),
    ),
    textTheme: Typography.material2021().black.apply(bodyColor: t.text, displayColor: t.text).copyWith(
          headlineMedium: TextStyle(fontFamily: kSerif, fontSize: 28, height: 1.2, color: t.text, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontFamily: kSerif, fontSize: 22, height: 1.25, color: t.text, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: t.text),
          bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: t.text),
          labelMedium: TextStyle(fontSize: 12, letterSpacing: 0.4, color: t.muted),
        ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
