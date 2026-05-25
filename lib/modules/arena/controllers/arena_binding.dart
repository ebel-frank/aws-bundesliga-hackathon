import 'package:get/get.dart';
import 'arena_controller.dart';

class ArenaBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ArenaController>()) {
      Get.put<ArenaController>(ArenaController(), permanent: true);
    }
  }
}
