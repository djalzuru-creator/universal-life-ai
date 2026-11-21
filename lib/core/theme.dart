import 'package:flutter/material.dart';

/// Colores de la marca Aguilera Valencia (oscuro con morado neón).
abstract final class Brand {
  static const bg = Color(0xFF0A0614);
  static const panel = Color(0xFF160D2A);
  static const panel2 = Color(0xFF1C1135);
  static const line = Color(0xFF2E1D52);
  static const line2 = Color(0xFF4C2A86);
  static const fg = Color(0xFFF3ECFF);
  static const muted = Color(0xFFA99BC9);
  static const dim = Color(0xFF7A6C9C);
  static const violet = Color(0xFFA855F7);
  static const violet2 = Color(0xFF7C3AED);
  static const magenta = Color(0xFFD946EF);
  static const pink = Color(0xFFF472B6);
  static const gold = Color(0xFFFBBF24);
  static const ok = Color(0xFF34D399);
  static const bad = Color(0xFFFB7185);

  static const neon = LinearGradient(colors: [violet2, magenta]);

  /// Fondo con resplandor morado arriba, como en la referencia.
  static const backdrop = BoxDecoration(
    color: bg,
    gradient: RadialGradient(
      center: Alignment(0.1, -1.2),
      radius: 1.2,
      colors: [Color(0xFF2A0F55), bg],
    ),
  );

  static List<BoxShadow> glow([Color c = violet, double a = .35]) => [
    BoxShadow(color: c.withValues(alpha: a), blurRadius: 18),
  ];
}

/// La app usa siempre el tema oscuro de la marca.
ThemeData buildTheme([Brightness _ = Brightness.dark]) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brand.violet,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Brand.violet,
        onPrimary: Colors.white,
        secondary: Brand.magenta,
        tertiary: Brand.pink,
        surface: Brand.panel,
        onSurface: Brand.fg,
        onSurfaceVariant: Brand.muted,
        surfaceContainerLowest: Brand.bg,
        surfaceContainerLow: Brand.panel,
        surfaceContainer: Brand.panel,
        surfaceContainerHigh: Brand.panel2,
        surfaceContainerHighest: Brand.panel2,
        outline: Brand.dim,
        outlineVariant: Brand.line,
        error: Brand.bad,
        errorContainer: const Color(0xFF4A1530),
        onErrorContainer: const Color(0xFFFFD6DE),
        primaryContainer: const Color(0xFF3B1475),
        onPrimaryContainer: const Color(0xFFF5D0FE),
        secondaryContainer: const Color(0xFF3A1350),
        onSecondaryContainer: const Color(0xFFF5D0FE),
      );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: Brand.line),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Brand.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Brand.fg,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Brand.fg,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: Brand.panel,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    listTileTheme: const ListTileThemeData(iconColor: Brand.violet),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.magenta, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Brand.dim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.violet2,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Brand.violet),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.magenta,
      foregroundColor: Colors.white,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.panel,
      selectedColor: Brand.violet2,
      side: const BorderSide(color: Brand.line2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Brand.line2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.panel2,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Brand.panel2,
      contentTextStyle: TextStyle(color: Brand.fg),
      actionTextColor: Brand.pink,
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: Brand.line),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.violet : null,
      ),
    ),
  );
}
