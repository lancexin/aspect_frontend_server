import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

//普通方法拦截
@pragma("aopd:aspect")
@pragma('vm:entry-point')
class Inject {
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "_MyHomePageState",
    "methodName": "-_test1",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static void _injectTest1(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    Function.apply(proceed, positionalParams, _transToNamedParams(namedParams));
  }

  //普通方法拦截,带返回值
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "_MyHomePageState",
    "methodName": "-_test2",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<bool> _injectTest2(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  //普通静态方法拦截,带返回值
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "_MyHomePageState",
    "methodName": "+_test3",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<bool> _injectTest3(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  //非类中的方法拦截
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "",
    "methodName": "+_test4",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<bool> _injectTest4(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    bool success = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result $success");
    return success;
  }

  //非类中的方法拦截
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "",
    "methodName": "+_testtry",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<bool> _injectTesttry(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    bool success = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result $success");
    return success;
  }

  //非类中的方法拦截
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "DialogExt",
    "methodName": "-DialogExt|showNotice",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<bool> _injectShowNotice(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${namedParams["title"]} ${namedParams["message"]}");
    bool success = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result $success");
    return success;
  }

  // //全局catch拦截
  // @pragma('vm:entry-point')
  // @pragma("aopd:trycatch")
  // //必须是static,不然不起作用
  // static void injectTrycatch(
  //   String? functionName,
  //   Object exception,
  //   StackTrace? stackTrace,
  // ) async {
  //   var info = {
  //     "message":
  //         "程序运行错误: $functionName | ${exception.toString()},详情: ${stackTrace?.toString()}",
  //   };
  //   debugPrint(info["message"].toString());
  // }

  //Extension里方法拦截
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "ExtensionHomePageState",
    "methodName": "-ExtensionHomePageState|_test5",
    "isRegex": false
  })
  //必须是static,不然不起作用
  //这里需要注意Extension的注入和普通方法不同,methodName的写法也与普遍的不同
  //Extension中的方法第一个positionalParams[0]所代表的参数是它扩展的实例本身
  static Future<bool> _injectTest5(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0].runtimeType.toString()} ${positionalParams[1]} ${positionalParams[2]} ${namedParams["key3"]}");
    bool success = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result $success");
    return success;
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:flutter/src/gestures/binding.dart",
    "clsName": "GestureBinding",
    "methodName": "-dispatchEvent",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static dynamic dispatchEvent(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    PointerEvent event = positionalParams[0];
    debugPrint('dispatchEvent - start ${event.kind.name}');
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  //Mixin里方法拦截的例子
  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "Test6Mixin",
    "methodName": "-_test6",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static void _injectTest6(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    Function.apply(proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "MixinHomePageState2",
    "methodName": "-_test7",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static void _injectTest7(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    Function.apply(proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "RepositoryImpl",
    "methodName": "-getAppVersion",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<int> _injectGetAppVersion(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint("[Inject] $functionName start: ${namedParams["packageName"]}");
    int result = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result: $result");
    return result;
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "BaseRepository",
    "methodName": "-getAppVersion2",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<int> _injectGetAppVersion2(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint("[Inject] $functionName start: ${namedParams["packageName"]}");
    int result = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] $functionName result: $result");
    return result;
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "RepositoryImpl",
    "methodName": "-getAppVersion2",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static Future<int> _injectGetAppVersion22(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] _injectGetAppVersion22 start: ${namedParams["packageName"]}");
    int result = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    debugPrint("[Inject] _injectGetAppVersion22 result: $result");
    return result;
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/test_mixin.dart",
    "clsName": "MixinBaseController",
    "methodName": "-testMixin",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static dynamic testMixin(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint("[Inject] testMixin start");

    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/test_mixin.dart",
    "clsName": "BaseControllerImpl",
    "methodName": "-baseTest",
    "isRegex": false
  })
  //必须是static,不然不起作用
  static dynamic baseTest(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    debugPrint(
        "[Inject] baseTest start: ${target.runtimeType.toString()} $functionName ");

    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  static Map<Symbol, dynamic> _transToNamedParams(
      Map<String, dynamic> namedParams) {
    Map<Symbol, dynamic> maps = {};
    namedParams.forEach((key, value) {
      maps[Symbol(key)] = value;
    });
    return maps;
  }
}
