import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../controllers/arena_controller.dart';

/// A compact leaderboard strip showing player rankings, XP, and streaks.
///
/// Sorted by totalXP descending. Top 3 get gold/silver/bronze rank badges.
/// Streak indicators (🔥) appear for players with 3+ consecutive correct answers.
class LeaderboardStripWidget extends StatelessWidget {
  const LeaderboardStripWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ArenaController>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.emoji_events, size: 14, color: AppColors.arenaAccent),
              SizedBox(width: 6),
              Text(
                'LEADERBOARD',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Leaderboard rows
          Obx(() {
            final sorted = List.of(controller.leaderboard)
              ..sort((a, b) => b.totalXP.compareTo(a.totalXP));

            return Column(
              children: List.generate(sorted.length, (i) {
                final player = sorted[i];
                final rank = i + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      // Rank badge
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _rankColor(rank),
                        ),
                        child: Center(
                          child: Text(
                            _rankLabel(rank),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Avatar
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: player.avatarColor,
                        ),
                        child: Center(
                          child: Text(
                            player.initials,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Display name
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Streak indicator
                      if (player.streak >= 3) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.neonGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🔥${player.streak}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.neonGreen,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // XP text
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${player.totalXP}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.arenaAccent,
                              ),
                            ),
                            const TextSpan(
                              text: ' XP',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return AppColors.cardBorder;
    }
  }

  String _rankLabel(int rank) {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '$rank';
    }
  }
}
