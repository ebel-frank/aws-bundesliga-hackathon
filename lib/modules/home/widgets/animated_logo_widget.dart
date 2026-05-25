import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../controllers/home_controller.dart';

class AnimatedLogoWidget extends StatelessWidget {
  const AnimatedLogoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeController>();

    return ScaleTransition(
      scale: controller.logoScaleAnim,
      child: FadeTransition(
        opacity: controller.logoFadeAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LIVE PREDICTION',
              style: AppTextStyles.overline,
            ),
            const SizedBox(height: 4),
            Shimmer.fromColors(
              baseColor: AppColors.textPrimary,
              highlightColor: AppColors.electricBlueGlow,
              child: const Text(
                'ARENA',
                style: AppTextStyles.headline,
              ),
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, fraction, child) {
                return Container(
                  width: 120 * fraction,
                  height: 2,
                  color: AppColors.electricBlue,
                );
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Fan Squad × Bundesliga',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}
