import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_colors.dart';
import '../../models/match_model.dart';
import '../../services/auth_service.dart';
import '../auth/auth_bottom_sheet.dart';
import '../auth/auth_controller.dart';
import 'controllers/home_controller.dart';
import 'widgets/background_widget.dart';
import 'widgets/mode_card_widget.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const RepaintBoundary(child: BackgroundWidget()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildHeader(),
                  const SizedBox(height: 28),
                  _buildScoreSection(),
                  const SizedBox(height: 28),
                  _buildChallengeCards(),
                  const SizedBox(height: 28),
                  _buildUpcomingMatches(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top header: greeting + action icons
  Widget _buildHeader() {
    final authController = Get.find<AuthController>();

    return Obx(() {
      final loggedIn = authController.isLoggedIn.value;
      final name = loggedIn && AuthService.displayName.isNotEmpty
          ? AuthService.displayName.split(' ').first
          : 'Player';

      return Row(
        children: [
          // Avatar
          GestureDetector(
            onTap: () {
              if (!loggedIn) {
                showAuthBottomSheet(Get.context!);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.arenaAccent,
                    AppColors.fantasyAccent,
                  ],
                ),
                border: Border.all(
                  color: AppColors.cardBorder,
                  width: 2,
                ),
              ),
              child: Center(
                child: loggedIn
                    ? Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          // Action icons
          _buildIconButton(Icons.notifications_none_rounded),
        ],
      );
    });
  }

  Widget _buildIconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardSurface.withValues(alpha: 0.5),
            AppColors.cardBorder.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 20),
    );
  }

  /// Score and badges section
  Widget _buildScoreSection() {
    return Row(
      children: [
        // Score
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Score',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '520',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'pts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Badges / matches won
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: '50 / 150 ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: 'matches won',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Image.asset('assets/images/diamond-badge.png', width: 28, height: 28),
                const SizedBox(width: 6),
                Image.asset('assets/images/gold-badge.png', width: 32, height: 32),
                const SizedBox(width: 6),
                Image.asset('assets/images/bronze-badge.png', width: 30, height: 30),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Two challenge cards side by side
  Widget _buildChallengeCards() {
    return Obx(
      () => AnimatedOpacity(
        opacity: controller.isLoaded.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Row(
          children: controller.gameModes
              .asMap()
              .entries
              .map(
                (entry) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: entry.key == 0 ? 8 : 0,
                      left: entry.key == 1 ? 8 : 0,
                    ),
                    child: ModeCardWidget(
                      mode: entry.value,
                      animationDelay: Duration(
                        milliseconds: 150 * entry.key,
                      ),
                      isSelected:
                          controller.selectedMode.value == entry.key,
                      onTap: () => controller.onModeSelected(
                        entry.value.id,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// Upcoming matches — horizontal scroll list
  Widget _buildUpcomingMatches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'Upcoming Matches ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: '(Bundesliga)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: Text(
                'View all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.arenaAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Match cards — horizontal scroll
        SizedBox(
          height: 160,
          child: Obx(() {
            if (controller.isLoadingMatches.value) {
              return _buildMatchShimmer();
            }
            if (controller.upcomingMatches.isEmpty) {
              return const Center(
                child: Text(
                  'No upcoming matches',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.upcomingMatches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _UpcomingMatchCard(
                  match: controller.upcomingMatches[index],
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMatchShimmer() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.cardSurface,
        highlightColor: AppColors.cardBorder,
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }
}

/// A single upcoming match card showing team badges, date, and time.
class _UpcomingMatchCard extends StatelessWidget {
  final MatchModel match;

  const _UpcomingMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Team color bars
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.arenaAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'vs',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hotPink,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Team badges and time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Home team
              Column(
                children: [
                  _buildTeamBadge(match.homeTeamBadge),
                  const SizedBox(height: 4),
                  Text(
                    match.homeTeam,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "FC",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              // Date & time
              Column(
                children: [
                  Text(
                    match.matchDate,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    match.matchTime,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              // Away team
              Column(
                children: [
                  _buildTeamBadge(match.awayTeamBadge),
                  const SizedBox(height: 4),
                  Text(
                    match.awayTeam,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "FC",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeamBadge(String assetPath) {
    if (assetPath.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardBorder,
        ),
        child: const Icon(Icons.shield, size: 20, color: AppColors.textMuted),
      );
    }
    return SvgPicture.asset(
      assetPath,
      width: 40,
      height: 40,
    );
  }
}
