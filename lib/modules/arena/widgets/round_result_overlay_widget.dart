import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../controllers/arena_controller.dart';
import 'xp_burst_widget.dart';

/// Full-screen overlay showing round results: correct/wrong indicator,
/// XP earned, bonus pills, and correct answer reveal.
class RoundResultOverlayWidget extends StatelessWidget {
  const RoundResultOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ArenaController>();
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Center(
          child: Obx(() {
            final isDeferred = controller.isDeferred.value;
            final wasCorrect = controller.wasCorrect.value;
            final borderColor = isDeferred
                ? AppColors.arenaAccent
                : (wasCorrect ? AppColors.neonGreen : AppColors.error);

            return Container(
              width: screenWidth - 48,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: borderColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: isDeferred
                    ? _buildDeferredContent(controller)
                    : _buildResolvedContent(controller, wasCorrect),
              ),
            );
          }),
        ),
      ),
    );
  }
  Widget _buildDeferredContent(ArenaController controller) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 64,
          color: AppColors.arenaAccent,
        ),
        const SizedBox(height: 16),
        const Text(
          '✓ Answer Recorded!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.arenaAccent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          controller.myPick.value.isNotEmpty
              ? 'Your pick: ${controller.myPick.value}'
              : 'No answer submitted',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Results at match end 🏁',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildResolvedContent(ArenaController controller, bool wasCorrect) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // XP Burst
        XpBurstWidget(isCorrect: wasCorrect),
        const SizedBox(height: 16),
        // Result text
        Text(
          wasCorrect ? '✓ Correct!' : '✗ Wrong',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: wasCorrect ? AppColors.neonGreen : AppColors.error,
          ),
        ),
        const SizedBox(height: 8),
        // Correct answer reveal
        Text(
          'Answer: ${controller.activeRound.value?.correctAnswer ?? ""}',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        // XP earned
        Text(
          '+${controller.xpEarnedThisRound.value} XP',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.arenaAccent,
          ),
        ),
        const SizedBox(height: 12),
        // Bonus pills
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (controller.speedBonusEarned.value)
              _BonusPill(
                text: '⚡ Fast Answer',
                color: AppColors.neonGreen,
              ),
            if (controller.speedBonusEarned.value &&
                controller.newStreak.value >= 3)
              const SizedBox(width: 8),
            if (controller.newStreak.value >= 3)
              _BonusPill(
                text: '🔥 ${controller.newStreak.value}× Streak',
                color: const Color(0xFFFFB300),
              ),
          ],
        ),
      ],
    );
  }
}

class _BonusPill extends StatelessWidget {
  const _BonusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
