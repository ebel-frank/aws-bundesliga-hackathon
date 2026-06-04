import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../models/prediction_round_model.dart';
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
                  const SizedBox(height: 12),
                  // Missed questions banner (tap to answer for catch-up points)
                  _buildMissedQuestionsBar(context),
                  const SizedBox(height: 8),
                  // Countdown timer — only show when a question is active
                  Obx(() {
                    if (controller.activeRound.value == null) return const SizedBox.shrink();
                    return CountdownTimerWidget(seconds: controller.countdownSeconds.value);
                  }),
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

  /// A tappable banner showing how many questions the player missed. Tapping
  /// opens a sheet where each missed question can still be answered for
  /// minimum (catch-up) points, until the server resolves it.
  Widget _buildMissedQuestionsBar(BuildContext context) {
    return Obx(() {
      final count = controller.missedQuestions.length;
      if (count == 0) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => _showMissedQuestionsSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB300).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.history_toggle_off, size: 18, color: Color(0xFFFFB300)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count missed ${count == 1 ? 'question' : 'questions'} — tap to catch up',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFFFB300)),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFFFB300)),
            ],
          ),
        ),
      );
    });
  }

  void _showMissedQuestionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.bolt, size: 20, color: Color(0xFFFFB300)),
                    SizedBox(width: 8),
                    Text('Catch up on missed questions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Answer now for minimum points before they resolve.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Obx(() {
                  final missed = controller.missedQuestions;
                  if (missed.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('All caught up! 🎉', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: missed.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.cardBorder, height: 24),
                    itemBuilder: (_, i) => _MissedQuestionTile(round: missed[i], controller: controller),
                  );
                }),
              ),
            ],
          ),
        ),
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
            const SizedBox(width: 8),
            // QA history icon
            GestureDetector(
              onTap: () => _showQAHistory(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.arenaAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.question_answer_outlined, size: 18, color: AppColors.arenaAccent),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showQAHistory(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QA History',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

        return SlideTransition(
          position: slideAnimation,
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const Icon(Icons.question_answer_outlined, color: AppColors.arenaAccent, size: 22),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Your Answers',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: const Icon(Icons.close, color: AppColors.textMuted, size: 22),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: AppColors.cardBorder, height: 1),
                      // Questions list
                      Expanded(
                        child: Obx(() {
                          final rounds = controller.rounds;
                          // Touch questionResults so this rebuilds when statuses change
                          final _ = controller.questionResults.length;
                          if (rounds.isEmpty) {
                            return const Center(
                              child: Text('No questions yet', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: rounds.length,
                            separatorBuilder: (_, __) => const Divider(color: AppColors.cardBorder, height: 24),
                            itemBuilder: (_, index) {
                              final round = rounds[index];
                              final userPick = controller.userPicks[round.roundId];
                              final isAnswered = userPick != null;
                              // Resolution status from server (points-based, authoritative)
                              final resultStatus = controller.questionResults[round.roundId];
                              final correctAnswer = round.correctAnswer;
                              final isResolved = resultStatus != null || correctAnswer.isNotEmpty;
                              // Trust the server's status first; only fall back to
                              // answer-matching when no status was recorded.
                              final bool isCorrect = resultStatus != null
                                  ? resultStatus == 'correct'
                                  : (correctAnswer.isNotEmpty && userPick == correctAnswer);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Question number + status badge
                                  Row(
                                    children: [
                                      Text(
                                        'Q${index + 1}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.arenaAccent),
                                      ),
                                      const Spacer(),
                                      _statusBadge(isAnswered, isResolved, isCorrect),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Question text
                                  Text(
                                    round.questionText,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  // Options
                                  ...round.options.map((option) {
                                    final isSelected = option == userPick;
                                    final isCorrectOption = isResolved && option == correctAnswer;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                            size: 16,
                                            color: isSelected
                                                ? (isResolved ? (isCorrect ? AppColors.neonGreen : AppColors.error) : AppColors.arenaAccent)
                                                : (isCorrectOption ? AppColors.neonGreen : AppColors.textMuted),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                          if (isCorrectOption)
                                            const Icon(Icons.check_circle, size: 14, color: AppColors.neonGreen),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusBadge(bool isAnswered, bool isResolved, bool isCorrect) {
    if (!isAnswered) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
        child: const Text('SKIPPED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
      );
    }
    if (!isResolved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.arenaAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: const Text('AWAITING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.arenaAccent)),
      );
    }
    if (isCorrect) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.neonGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: const Text('CORRECT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.neonGreen)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: const Text('WRONG', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.error)),
    );
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

/// A single missed question shown in the catch-up sheet. Selecting an option
/// submits it as a late answer (minimum points) and removes it from the list.
class _MissedQuestionTile extends StatefulWidget {
  const _MissedQuestionTile({required this.round, required this.controller});

  final PredictionRoundModel round;
  final ArenaController controller;

  @override
  State<_MissedQuestionTile> createState() => _MissedQuestionTileState();
}

class _MissedQuestionTileState extends State<_MissedQuestionTile> {
  String? _selected;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                round.category.toUpperCase(),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFB300), letterSpacing: 0.8),
              ),
            ),
            const Spacer(),
            const Text('catch-up · min points', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          round.questionText,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: round.options.map((option) {
            final isSel = _selected == option;
            return GestureDetector(
              onTap: _submitted
                  ? null
                  : () {
                      setState(() {
                        _selected = option;
                        _submitted = true;
                      });
                      widget.controller.answerMissedQuestion(round.roundId, option);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Answer submitted for catch-up points'), duration: Duration(seconds: 2)),
                      );
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? AppColors.arenaAccent : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSel ? AppColors.arenaAccent : AppColors.cardBorder),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSel ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
