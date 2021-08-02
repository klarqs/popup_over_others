import 'package:get/get.dart';

import 'main.dart';

class SplashScreenController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    Future.delayed(
      Duration(
        seconds: 3,
      ),
      () => Get.off(
        ListPage(true),
      ),
    );
  }
}
