import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../controllers/arena_controller.dart';
import 'countdown_timer_widget.dart';

/// The main prediction challenge card displaying the question, countdown timer,
/// and answer option buttons.
class PredictionCardWidget extends StatelessWidget {
  const PredictionCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ArenaController>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.arenaAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.arenaAccent.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category badge pill
            Obx(() {
              final category = controller.activeRound.value?.category ?? '';
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.arenaAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.arenaAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _categoryIcon(category),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.arenaAccent,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // Question text
            Obx(() => Text(
                  controller.activeRound.value?.questionText ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                )),

            const SizedBox(height: 20),

            // Countdown timer
            Center(
              child: Obx(() => CountdownTimerWidget(
                    seconds: controller.countdownSeconds.value,
                  )),
            ),

            const SizedBox(height: 20),

            // Answer option buttons
            Obx(() {
              final options = controller.activeRound.value?.options ?? [];
              return Column(
                children: options.map((option) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnswerOptionButton(
                      label: option,
                      isSelected: controller.myPick.value == option,
                      isLocked: controller.hasLockedIn.value,
                      onTap: () => controller.lockInPick(option),
                    ),
                  );
                }).toList(),
              );
            }),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _categoryIcon(String category) {
    switch (category) {
      case 'goalscorer':
        return '⚽';
      case 'result':
        return '📊';
      case 'stats':
        return '📈';
      case 'cards':
        return '🟨';
      case 'overunder':
        return '⬆️';
      default:
        return '🎯';
    }
  }
}

/// A single answer option button with selected/locked/disabled states.
class _AnswerOptionButton extends StatefulWidget {
  const _AnswerOptionButton({
    required this.label,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  State<_AnswerOptionButton> createState() => _AnswerOptionButtonState();
}

class _AnswerOptionButtonState extends State<_AnswerOptionButton> {
  bool _isTapDown = false;

  bool get _isDisabled => !widget.isSelected && widget.isLocked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _isDisabled ? null : (_) => setState(() => _isTapDown = true),
      onTapUp: _isDisabled ? null : (_) => setState(() => _isTapDown = false),
      onTapCancel: _isDisabled ? null : () => setState(() => _isTapDown = false),
      onTap: _isDisabled ? null : widget.onTap,
      child: AnimatedScale(
        scale: _isTapDown ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _backgroundColor,
            gradient: _gradient,
            border: Border.all(
              color: _borderColor,
              width: widget.isSelected && widget.isLocked ? 2 : 1.5,
            ),
            boxShadow: widget.isSelected && widget.isLocked
                ? [
                    BoxShadow(
                      color: AppColors.arenaAccent.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: _isDisabled ? 0.3 : 1.0,
            child: Center(child: _buildContent()),
          ),
        ),
      ),
    );
  }

  Color get _backgroundColor {
    if (widget.isSelected && widget.isLocked) return Colors.transparent;
    return AppColors.cardSurface;
  }

  LinearGradient? get _gradient {
    if (widget.isSelected && widget.isLocked) {
      return LinearGradient(
        colors: [
          AppColors.arenaAccent.withValues(alpha: 0.2),
          AppColors.electricBlue.withValues(alpha: 0.2),
        ],
      );
    }
    return null;
  }

  Color get _borderColor {
    if (widget.isSelected && widget.isLocked) return AppColors.arenaAccent;
    return AppColors.cardBorder;
  }

  Widget _buildContent() {
    if (widget.isSelected && widget.isLocked) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 14, color: AppColors.arenaAccent),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.arenaAccent,
            ),
          ),
        ],
      );
    }

    return Text(
      widget.label,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }
}
