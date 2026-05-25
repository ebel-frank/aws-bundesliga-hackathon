import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// Displays a single earned badge with icon and name.
class BadgeAwardWidget extends StatelessWidget {
  const BadgeAwardWidget({super.key, required this.badge});

  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.arenaAccent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.arenaAccent.withValues(alpha: 0.2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _badgeIcon(badge),
            size: 28,
            color: AppColors.arenaAccent,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _badgeIcon(String badge) {
    switch (badge) {
      case 'Perfect Round':
        return Icons.stars;
      case 'Speed Demon':
        return Icons.flash_on;
      case 'Streak Master':
        return Icons.local_fire_department;
      case 'Comeback King':
        return Icons.emoji_events;
      case 'Consistent':
        return Icons.verified;
      default:
        return Icons.military_tech;
    }
  }
}
