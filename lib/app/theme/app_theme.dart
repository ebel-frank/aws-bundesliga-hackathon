import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

abstract class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineLarge: AppTextStyles.headline,
          titleLarge: AppTextStyles.title,
          titleMedium: AppTextStyles.subtitle,
          bodyMedium: AppTextStyles.body,
          bodySmall: AppTextStyles.caption,
          labelSmall: AppTextStyles.overline,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.electricBlue,
          surface: AppColors.cardSurface,
          error: AppColors.error,
        ),
      );
}
