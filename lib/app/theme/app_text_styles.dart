import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract class AppTextStyles {
  static const TextStyle headline = TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: 4,
  );

  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 4,
    color: AppColors.textSecondary,
  );

  static const TextStyle chip = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
  );
}
