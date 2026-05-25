import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import 'controllers/arena_controller.dart';
import 'widgets/room_code_widget.dart';
import 'widgets/squad_avatar_widget.dart';

class ArenaWaitingView extends GetView<ArenaController> {
  const ArenaWaitingView({super.key});

  @override
  Widget build(BuildContext context) {
    // Start the match countdown when this view mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.matchCountdownSeconds.value == 0 &&
          !controller.isMatchLive.value) {
        controller.startMatchCountdown(seconds: 10);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Top bar
              Row(
                children: [
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '🛡️ SQUAD LOBBY',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Match countdown / Live status
              Obx(() => _buildMatchStatus()),

              // Room code display
              Obx(
                () => controller.squad.value!.isPrivate
                    ? RoomCodeWidget(
                        code: controller.squad.value?.roomCode ?? '------',
                      )
                    : SizedBox.shrink(),
              ),
              Obx(
                () => controller.squad.value!.isPrivate
                    ? Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: const Text(
                          'Share this code with your squad',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    )
                    : SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              // Players header
              Obx(
                () => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'PLAYERS (${controller.squad.value?.members.length ?? 0}/6)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Player grid
              Obx(() {
                final members = controller.squad.value?.members ?? [];
                return GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.75,
                  children: List.generate(6, (index) {
                    final player = index < members.length
                        ? members[index]
                        : null;
                    return SquadAvatarWidget(player: player);
                  }),
                );
              }),
              const Spacer(),
              // Action button area
              Obx(() {
                final isHost = _isCurrentUserHost();
                final isLive = controller.isMatchLive.value;

                if (isHost && isLive) {
                  return _buildStartButton();
                } else if (!isLive) {
                  return _buildCountdownWaiting();
                } else {
                  return _buildWaitingForHost();
                }
              }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchStatus() {
    if (controller.isMatchLive.value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.neonGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'MATCH IS LIVE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.neonGreen,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
    }

    // Countdown to match start
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.arenaAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'MATCH STARTS IN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${controller.matchCountdownSeconds.value}s',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppColors.arenaAccent,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Get ready to predict!',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  bool _isCurrentUserHost() {
    final squad = controller.squad.value;
    if (squad == null) return false;
    if (squad.members.isEmpty) return false;
    return squad.members.first.isHost;
  }

  Widget _buildStartButton() {
    final members = controller.squad.value?.members ?? [];
    final isEnabled = members.length >= 2;

    return GestureDetector(
      onTap: isEnabled ? () => controller.startGame() : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppColors.arenaAccent, AppColors.electricBlue],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.arenaAccent.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              '⚡ START GAME',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownWaiting() {
    return const Column(
      children: [
        Text(
          'Waiting for match to start...',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        SizedBox(height: 8),
        LinearProgressIndicator(
          color: AppColors.arenaAccent,
          backgroundColor: AppColors.cardBorder,
        ),
      ],
    );
  }

  Widget _buildWaitingForHost() {
    return const Column(
      children: [
        Text(
          'Match is live! Waiting for host to start the game...',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        LinearProgressIndicator(
          color: AppColors.neonGreen,
          backgroundColor: AppColors.cardBorder,
        ),
      ],
    );
  }
}
