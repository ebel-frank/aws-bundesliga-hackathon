import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../models/player_model.dart';

/// Victory podium showing top 3 players with gradient columns.
/// 2nd place (left), 1st place (center, tallest, crown), 3rd place (right).
class PodiumWidget extends StatelessWidget {
  const PodiumWidget({super.key, required this.leaderboard});

  final List<PlayerModel> leaderboard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 2nd place
          _PodiumColumn(
            rank: 2,
            player: leaderboard.length > 1 ? leaderboard[1] : null,
            height: 70,
            gradientColors: const [Color(0xFFC0C0C0), Color(0xFF808080)],
          ),
          const SizedBox(width: 8),
          // 1st place
          _PodiumColumn(
            rank: 1,
            player: leaderboard.isNotEmpty ? leaderboard[0] : null,
            height: 100,
            gradientColors: const [Color(0xFFFFD700), Color(0xFFFF8C00)],
            showCrown: true,
          ),
          const SizedBox(width: 8),
          // 3rd place
          _PodiumColumn(
            rank: 3,
            player: leaderboard.length > 2 ? leaderboard[2] : null,
            height: 45,
            gradientColors: const [Color(0xFFCD7F32), Color(0xFF8B4513)],
          ),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.rank,
    required this.player,
    required this.height,
    required this.gradientColors,
    this.showCrown = false,
  });

  final int rank;
  final PlayerModel? player;
  final double height;
  final List<Color> gradientColors;
  final bool showCrown;

  String get _rankEmoji {
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

  @override
  Widget build(BuildContext context) {
    if (player == null) {
      return const SizedBox(width: 80);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Crown for 1st place
        if (showCrown)
          const Text('👑', style: TextStyle(fontSize: 28))
        else
          const SizedBox.shrink(),
        const SizedBox(height: 4),
        // Avatar
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: player!.avatarColor,
            border: Border.all(
              color: gradientColors.first,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: Text(
              player!.initials,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Display name
        Text(
          player!.displayName,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        // XP text
        Text(
          '${player!.totalXP} XP',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.arenaAccent,
          ),
        ),
        const SizedBox(height: 6),
        // Podium column
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
          ),
          child: Center(
            child: Text(
              _rankEmoji,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ],
    );
  }
}
