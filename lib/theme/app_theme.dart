import 'package:flutter/material.dart';

/// 全局配色，取绿联品牌绿作为主色，搭配低饱和度的浅雾背景。
abstract final class AppColors {
  static const brand = Color(0xFF16B364);
  static const brandDark = Color(0xFF0B7A46);
  static const brandInk = Color(0xFF063B23);
  static const ink = Color(0xFF10221A);
  static const muted = Color(0xFF62766B);
  static const surface = Colors.white;
  static const canvasTop = Color(0xFFF7FBF8);
  static const canvasBottom = Color(0xFFE8F2EC);
  static const line = Color(0xFFE0EAE3);
  static const fieldFill = Color(0xFFF6FAF8);
  static const danger = Color(0xFFD92D20);
  static const heroStart = Color(0xFF0A2118);
  static const heroMid = Color(0xFF0D3A26);
  static const heroEnd = Color(0xFF11573A);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    secondary: AppColors.brandDark,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.danger,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvasTop,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.fieldFill,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      hintStyle: TextStyle(color: Color(0xFF97A89D), fontSize: 14),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.brand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.danger),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.brandDark,
      selectionColor: Color(0x3316B364),
      selectionHandleColor: AppColors.brandDark,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brand,
    ),
  );
}
