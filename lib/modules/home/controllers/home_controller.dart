import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../models/game_mode_model.dart';
import '../../../models/match_model.dart';
import '../../../services/api_service.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_bottom_sheet.dart';

class HomeController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // Observable state
  final RxBool isLoaded = false.obs;
  final RxInt selectedMode = (-1).obs;
  final RxBool isNavigating = false.obs;

  // Animation
  late AnimationController logoAnimController;
  late Animation<double> logoScaleAnim;
  late Animation<double> logoFadeAnim;

  // Data
  final List<GameModeModel> gameModes = [
    GameModeModel(
      id: 'arena',
      title: 'Arena',
      subtitle: 'Predict. Compete. Win.',
      description:
          'Join a squad and predict live match events in real time.',
      iconAsset: 'assets/images/quiz_bg_8.jpg',
      accentColor: AppColors.arenaAccent,
      glowColor: AppColors.arenaAccent.withValues(alpha: 0.4),
      featureTags: ['Multi-Player', 'Real-time', 'XP & Badges'],
    ),
    GameModeModel(
      id: 'fantasy',
      title: 'Fantasy',
      subtitle: 'Pick. Score. Dominate.',
      description:
          'Build your 11 from 22 players. Score points from real events.',
      iconAsset: 'assets/images/quiz_bg_2.jpg',
      accentColor: AppColors.fantasyAccent,
      glowColor: AppColors.fantasyAccent.withValues(alpha: 0.4),
      featureTags: ['Team builder', 'Real-time', 'Rankings'],
    ),
  ];

  // Upcoming matches
  final RxList<MatchModel> upcomingMatches = <MatchModel>[].obs;
  final RxBool isLoadingMatches = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initAnimations();
    _triggerEntrance();
    _loadUpcomingMatches();
  }

  void _initAnimations() {
    logoAnimController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    logoScaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: logoAnimController,
        curve: Curves.elasticOut,
      ),
    );

    logoFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: logoAnimController,
        curve: Curves.easeIn,
      ),
    );
  }

  Future<void> _triggerEntrance() async {
    await Future.delayed(const Duration(milliseconds: 300));
    logoAnimController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    isLoaded.value = true;
  }

  Future<void> _loadUpcomingMatches() async {
    isLoadingMatches.value = true;
    try {
      final matches = await ApiService.getMatches();
      upcomingMatches.value = matches;
    } catch (_) {
      upcomingMatches.value = [];
    } finally {
      isLoadingMatches.value = false;
    }
  }

  void onModeSelected(String modeId) async {
    if (isNavigating.value) return;

    isNavigating.value = true;

    // Check if user is logged in
    if (!Get.find<AuthController>().isLoggedIn.value) {
      isNavigating.value = false;
      // Show auth bottom sheet
      showAuthBottomSheet(Get.context!);
      return;
    }

    selectedMode.value = gameModes.indexWhere((mode) => mode.id == modeId);

    if (modeId == 'arena') {
      Get.toNamed('/arena/lobby');
    } else if (modeId == 'fantasy') {
      Get.toNamed('/fantasy/picker');
    }

    isNavigating.value = false;
  }

  @override
  void onClose() {
    logoAnimController.dispose();
    super.onClose();
  }
}
