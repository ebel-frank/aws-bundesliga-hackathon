import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../models/player_model.dart';
import '../../../models/player_pick_model.dart';

/// Displays the lock-in status of all squad members for the current round.
///
/// Shows each player's avatar with a green border and checkmark when they
/// have locked in their pick.
class RivalLockInRowWidget extends StatelessWidget {
  const RivalLockInRowWidget({
    super.key,
    required this.picks,
    required this.players,
  });

  final List<PlayerPickModel> picks;
  final List<PlayerModel> players;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(
          color: AppColors.cardBorder.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SQUAD STATUS',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: players.map((player) {
              final hasLocked = picks
                  .any((p) => p.userId == player.userId && p.hasLocked);
              return _PlayerStatusAvatar(
                player: player,
                hasLocked: hasLocked,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PlayerStatusAvatar extends StatelessWidget {
  const _PlayerStatusAvatar({
    required this.player,
    required this.hasLocked,
  });

  final PlayerModel player;
  final bool hasLocked;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: player.avatarColor,
                border: Border.all(
                  color: hasLocked ? AppColors.neonGreen : AppColors.cardBorder,
                  width: hasLocked ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  player.initials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (hasLocked)
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonGreen,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          player.displayName.split(' ').first,
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.textMuted,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
