import 'package:get/get.dart';
import 'app_routes.dart';
import '../../modules/home/home_view.dart';
import '../../modules/home/controllers/home_binding.dart';
import '../../modules/arena/arena_lobby_view.dart';
import '../../modules/arena/arena_waiting_view.dart';
import '../../modules/arena/arena_prediction_view.dart';
import '../../modules/arena/arena_end_view.dart';
import '../../modules/arena/controllers/arena_binding.dart';
import '../../modules/fantasy/fantasy_picker_view.dart';
import '../../modules/fantasy/fantasy_live_view.dart';
import '../../modules/fantasy/controllers/fantasy_binding.dart';

class AppPages {
  static final pages = <GetPage>[
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 400),
    ),
    GetPage(
      name: AppRoutes.arenaLobby,
      page: () => const ArenaLobbyView(),
      binding: ArenaBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
    GetPage(
      name: AppRoutes.arenaWaiting,
      page: () => const ArenaWaitingView(),
      binding: ArenaBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
    GetPage(
      name: AppRoutes.arenaPrediction,
      page: () => const ArenaPredictionView(),
      binding: ArenaBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
    GetPage(
      name: AppRoutes.arenaEnd,
      page: () => const ArenaEndView(),
      binding: ArenaBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
    GetPage(
      name: AppRoutes.fantasyPicker,
      page: () => const FantasyPickerView(),
      binding: FantasyBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
    GetPage(
      name: AppRoutes.fantasyLive,
      page: () => const FantasyLiveView(),
      binding: FantasyBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 350),
    ),
  ];
}
