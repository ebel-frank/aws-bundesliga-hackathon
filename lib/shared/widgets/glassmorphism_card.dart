import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class GlassmorphismCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final double borderRadius;
  final double borderWidth;
  final Color? glowColor;
  final double glowBlurRadius;

  const GlassmorphismCard({
    super.key,
    required this.child,
    this.borderColor = AppColors.cardBorder,
    this.borderRadius = 20,
    this.borderWidth = 2,
    this.glowColor,
    this.glowBlurRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor!,
                  blurRadius: glowBlurRadius,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
