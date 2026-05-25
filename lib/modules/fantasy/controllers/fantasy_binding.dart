import 'package:get/get.dart';
import 'fantasy_controller.dart';

class FantasyBinding extends Bindings {
  @override
  void dependencies() {
    // fenix: true keeps the controller alive across route pushes within the module
    Get.lazyPut<FantasyController>(() => FantasyController(), fenix: true);
  }
}
