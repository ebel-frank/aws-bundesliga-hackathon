import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import 'controllers/arena_controller.dart';
import 'widgets/countdown_timer_widget.dart';
import 'widgets/live_chat_widget.dart';
import 'widgets/round_result_overlay_widget.dart';

class ArenaPredictionView extends StatefulWidget {
  const ArenaPredictionView({super.key});

  @override
  State<ArenaPredictionView> createState() => _ArenaPredictionViewState();
}

class _ArenaPredictionViewState extends State<ArenaPredictionView> {
  final controller = Get.find<ArenaController>();

  static const _backgrounds = [
    'assets/images/quiz_bg_1.jpg',
    'assets/images/quiz_bg_2.jpg',
    'assets/images/quiz_bg_3.avif',
    'assets/images/quiz_bg_4.jpg',
    'assets/images/quiz_bg_5.jpg',
    'assets/images/quiz_bg_6.jpg',
    'assets/images/quiz_bg_7.jpg',
    'assets/images/quiz_bg_8.jpg',
    'assets/images/quiz_bg_9.jpg',
    'assets/images/quiz_bg_10.jpg',
  ];

  int _currentBgIndex = 0;
  Timer? _bgTimer;

  @override
  void initState() {
    super.initState();
    // Rotate background every 12 seconds
    _bgTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      setState(() {
        _currentBgIndex = (_currentBgIndex + 1) % _backgrounds.length;
      });
    });
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitConfirmation(context);
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated rotating background
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: SizedBox.expand(
              key: ValueKey(_currentBgIndex),
              child: Image.asset(
                _backgrounds[_currentBgIndex],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.background),
              ),
            ),
          ),
          // Dark gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.7),
                    AppColors.background.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Top bar
                  _buildTopBar(),
                  const SizedBox(height: 20),
                  // Countdown timer
                  Obx(() => CountdownTimerWidget(seconds: controller.countdownSeconds.value)),
                  const SizedBox(height: 20),
                  // Question + options
                  Expanded(child: _buildQuestionCard()),
                  // Bottom spacing for chat overlay
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
          // Live chat & reactions overlay (positioned at bottom, moves above keyboard)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8,
            child: const LiveChatWidget(),
          ),
          // Round result overlay
          Obx(() {
            if (controller.currentScreen.value == ArenaScreen.roundResult) {
              return const RoundResultOverlayWidget();
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Game?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: const Text('You are about to cancel the game. Your progress will be lost.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay', style: TextStyle(color: AppColors.arenaAccent, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.onClose();
              Get.back();
            },
            child: const Text('Leave', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Obx(() {
      final members = controller.squad.value?.members ?? [];
      final sorted = List.of(members)..sort((a, b) => b.totalXP.compareTo(a.totalXP));

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSurface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sorted.map((player) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: player.avatarColor,
                          child: Text(
                            player.initials,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          player.displayName.length > 8
                              ? '${player.displayName.substring(0, 8)}.'
                              : player.displayName,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${player.totalXP}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.arenaAccent),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildQuestionCard() {
    return Obx(() {
      final round = controller.activeRound.value;
      if (round == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: AppColors.arenaAccent,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for next question...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Obx(() => controller.latestEventSummary.value.isNotEmpty
                  ? Text(
                      controller.latestEventSummary.value,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    )
                  : const SizedBox.shrink()),
            ],
          ),
        );
      }

      return SingleChildScrollView(
        child: Column(
          children: [
            // Category pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.arenaAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.arenaAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_categoryIcon(round.category), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(round.category.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.arenaAccent, letterSpacing: 1)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Question
            Text(
              round.questionText,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Options
            ...round.options.map((option) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AnswerButton(
                    label: option,
                    isSelected: controller.myPick.value == option,
                    isLocked: controller.hasLockedIn.value,
                    onTap: () => controller.lockInPick(option),
                  ),
                )),
          ],
        ),
      );
    });
  }

  String _categoryIcon(String category) {
    switch (category) {
      case 'goalscorer': return '⚽';
      case 'result': return '📊';
      case 'stats': return '📈';
      case 'cards': return '🟨';
      case 'overunder': return '⬆️';
      default: return '🎯';
    }
  }
}

class _AnswerButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.label,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  @override
  State<_AnswerButton> createState() => _AnswerButtonState();
}

class _AnswerButtonState extends State<_AnswerButton> {
  bool _pressed = false;
  bool get _isDisabled => !widget.isSelected && widget.isLocked;

  @override
  Widget build(BuildContext context) {
    final isChosen = widget.isSelected && widget.isLocked;

    return GestureDetector(
      onTapDown: _isDisabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: _isDisabled ? null : (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: _isDisabled ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isChosen ? AppColors.arenaAccent : AppColors.cardSurface,
            border: Border.all(
              color: isChosen ? AppColors.arenaAccent : AppColors.cardBorder,
              width: isChosen ? 2 : 1.5,
            ),
            boxShadow: isChosen
                ? [BoxShadow(color: AppColors.arenaAccent.withValues(alpha: 0.3), blurRadius: 10)]
                : null,
          ),
          child: Opacity(
            opacity: _isDisabled ? 0.35 : 1.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isChosen) ...[
                  const Icon(Icons.check_circle, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isChosen ? Colors.white : AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
