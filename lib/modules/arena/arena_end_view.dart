import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_colors.dart';
import 'controllers/arena_controller.dart';

class ArenaEndView extends GetView<ArenaController> {
  const ArenaEndView({super.key});

  @override
  Widget build(BuildContext context) {
    final screenshotController = ScreenshotController();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background — stadium with lights
          Positioned.fill(
            child: Image.asset(
              'assets/images/final_result_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: AppColors.background),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.45),
                    AppColors.background.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 32),
                // Shareable content — wrapped in Screenshot
                Screenshot(
                  controller: screenshotController,
                  child: Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Trophy + header
                        Image.asset(
                          'assets/images/winner-tropy.png',
                          width: 80,
                          height: 80,
                          errorBuilder: (_, __, ___) => const Text('🏆', style: TextStyle(fontSize: 56)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'GAME OVER',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 3),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Final Standings',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 28),

                // Podium — top 3
                Obx(() => _buildPodium()),

                const SizedBox(height: 28),

                // Full leaderboard card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ALL PLAYERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 2)),
                      const SizedBox(height: 12),
                      Obx(() => Column(
                            children: List.generate(controller.leaderboard.length, (i) {
                              final player = controller.leaderboard[i];
                              final rank = i + 1;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    // Rank
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _rankColor(rank),
                                      ),
                                      child: Center(child: Text('$rank', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
                                    ),
                                    const SizedBox(width: 12),
                                    // Avatar
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: player.avatarColor),
                                      child: Center(child: Text(player.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                                    ),
                                    const SizedBox(width: 12),
                                    // Name
                                    Expanded(child: Text(player.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                    // XP
                                    Text('${player.totalXP}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.arenaAccent)),
                                    const Text(' XP', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                  ],
                                ),
                              );
                            }),
                          )),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Badges section
                Obx(() {
                  if (controller.earnedBadges.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🎖️ BADGES EARNED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 2)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: controller.earnedBadges.map((badge) => _BadgeChip(badge: badge)).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                }),
                      ],
                    ),
                  ),
                ), // End of Screenshot widget

                const SizedBox(height: 20),

                // Share button
                GestureDetector(
                  onTap: () => _shareAsImage(screenshotController),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.arenaAccent,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('SHARE RESULT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Play again — goes to match list (keeps home in stack)
                TextButton(
                  onPressed: () {
                    // Reset arena controller state for a fresh game
                    controller.currentScreen.value = ArenaScreen.lobby;
                    controller.arenaPageIndex.value = 0;
                    controller.squad.value = null;
                    controller.isMatchLive.value = false;
                    controller.matchCountdownSeconds.value = 0;
                    controller.currentRoundIndex.value = 0;
                    controller.activeRound.value = null;
                    controller.rounds.clear();
                    controller.leaderboard.clear();
                    controller.earnedBadges.clear();
                    // Pop all arena routes back to home, then push arena lobby fresh
                    Get.offNamedUntil(AppRoutes.arenaLobby, (route) => route.settings.name == AppRoutes.home);
                  },
                  child: const Text('Play Again', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _buildPodium() {
    final lb = controller.leaderboard;
    if (lb.length < 3) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd place
        _PodiumSlot(player: lb[1], rank: 2, height: 80),
        const SizedBox(width: 12),
        // 1st place
        _PodiumSlot(player: lb[0], rank: 1, height: 110),
        const SizedBox(width: 12),
        // 3rd place
        _PodiumSlot(player: lb[2], rank: 3, height: 60),
      ],
    );
  }

  Future<void> _shareAsImage(ScreenshotController screenshotController) async {
    try {
      final Uint8List? imageBytes = await screenshotController.capture(
        pixelRatio: 2.0,
        delay: const Duration(milliseconds: 100),
      );
      if (imageBytes == null) return;

      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/prediction_result.png';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: '🏆 Live Prediction Arena — Check out my results! #LivePredictionArena',
        ),
      );
    } catch (e) {
      // Fallback to text share if image capture fails
      final controller = Get.find<ArenaController>();
      final lb = controller.leaderboard;
      final text = '🏆 Live Prediction Arena\n\n'
          '${lb.asMap().entries.map((e) => '${e.key + 1}. ${e.value.displayName} — ${e.value.totalXP} XP').join('\n')}\n\n'
          'Play now! #LivePredictionArena';
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return AppColors.cardBorder;
    }
  }
}

class _PodiumSlot extends StatelessWidget {
  final dynamic player;
  final int rank;
  final double height;

  const _PodiumSlot({required this.player, required this.rank, required this.height});

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final color = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isFirst) const Text('👑', style: TextStyle(fontSize: 24)),
        if (isFirst) const SizedBox(height: 4),
        // Avatar
        Container(
          width: isFirst ? 52 : 44,
          height: isFirst ? 52 : 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: player.avatarColor,
            border: Border.all(color: color, width: 2.5),
          ),
          child: Center(child: Text(player.initials, style: TextStyle(fontSize: isFirst ? 16 : 13, fontWeight: FontWeight.bold, color: Colors.white))),
        ),
        const SizedBox(height: 6),
        Text(player.displayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text('${player.totalXP} XP', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.arenaAccent)),
        const SizedBox(height: 6),
        // Podium column
        Container(
          width: 70,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, color.withValues(alpha: 0.5)],
            ),
          ),
          child: Center(child: Text('#$rank', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.arenaAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_badgeIcon(badge), size: 16, color: AppColors.arenaAccent),
          const SizedBox(width: 6),
          Text(badge, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  IconData _badgeIcon(String badge) {
    switch (badge) {
      case 'Perfect Round': return Icons.stars;
      case 'Speed Demon': return Icons.flash_on;
      case 'Streak Master': return Icons.local_fire_department;
      default: return Icons.military_tech;
    }
  }
}
