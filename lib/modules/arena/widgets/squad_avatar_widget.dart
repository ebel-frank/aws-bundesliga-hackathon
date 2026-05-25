import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../models/player_model.dart';

class SquadAvatarWidget extends StatelessWidget {
  final PlayerModel? player;
  final double size;

  const SquadAvatarWidget({
    super.key,
    this.player,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return player != null ? _buildFilledSlot() : _buildEmptySlot();
  }

  Widget _buildFilledSlot() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar circle with optional host crown
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: player!.avatarColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.arenaAccent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.arenaAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  player!.initials,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            // Host crown badge
            if (player!.isHost)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.arenaAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('👑', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Display name
        SizedBox(
          width: size,
          child: Text(
            player!.displayName,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySlot() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.cardBorder,
              width: 1.5,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.person_add_outlined,
              size: 20,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Waiting...',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
