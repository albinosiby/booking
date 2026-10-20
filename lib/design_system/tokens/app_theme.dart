import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppColors {
  static const ink = Color(0xFF0F0F0F),
      surface = Color(0xFF202020),
      lime = Color(0xFF5DD62C),
      forest = Color(0xFF337418),
      white = Color(0xFFF8F8F8);
}

class AppTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.lime,
          brightness: brightness,
        ).copyWith(
          primary: dark ? AppColors.lime : AppColors.forest,
          onPrimary: dark ? AppColors.ink : AppColors.white,
          secondary: AppColors.forest,
          onSecondary: AppColors.white,
          surface: dark ? AppColors.surface : Colors.white,
          onSurface: dark ? AppColors.white : AppColors.ink,
          error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
          outline: dark ? const Color(0xFF474747) : const Color(0xFFD7D7D7),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.ink : AppColors.white,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: TextStyle(
          fontSize: 32.sp.clamp(28, 36),
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 24.sp.clamp(22, 28),
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.55,
          color: scheme.onSurface,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r.clamp(12, 18)),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r.clamp(12, 18)),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r.clamp(12, 18)),
          borderSide: const BorderSide(color: AppColors.lime, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .75)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.ink : AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            color: scheme.onSurface,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
