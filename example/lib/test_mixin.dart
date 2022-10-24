import 'package:flutter/foundation.dart';

class BaseController {}

mixin MixinBaseController on BaseController {
  void testMixin() {
    debugPrint("testMixin");
  }
}

class BaseControllerImpl extends BaseController with MixinBaseController {
  void baseTest() {
    debugPrint("baseTest");
    testMixin();
  }
}
