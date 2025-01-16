import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

//普通方法拦截
@pragma("aopd:aspect")
@pragma('vm:entry-point')
class Inject {
  @pragma('vm:entry-point')
  static Map<Symbol, dynamic> _transToNamedParams(
      Map<dynamic, dynamic> namedParams) {
    Map<Symbol, dynamic> maps = {};
    namedParams.forEach((key, value) {
      maps[Symbol(key)] = value;
    });
    return maps;
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": ".",
    "methodName": "-.",
    "isRegex": true
  })
  //必须是static,不然不起作用,
  //isRegex =true时我们不知道方法的签名，编译时混淆 --obfuscate
  //就会出错，建议isRegex =true，不要用在混淆的时候
  static dynamic _injectAllMethod(
      Object target,
      String functionName,
      List positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint("[Inject All] $functionName ");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": ".",
    "methodName": "+.",
    "isRegex": true
  })
  //必须是static,不然不起作用
  static dynamic _injectAllMethodStatic(
      Object target,
      String functionName,
      List positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint("[Inject All Static] $functionName ");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": ".",
    "methodName": "-.",
    "isRegex": true,
    "isGetter": true
  })
  //必须是static,不然不起作用
  static dynamic _injectAllMethodGetter(
      Object target,
      String functionName,
      List positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint("[Inject All Getter] $functionName ");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": ".",
    "methodName": "+.",
    "isRegex": true,
    "isGetter": true,
  })
  //必须是static,不然不起作用
  static dynamic _injectAllMethodGetterStatic(
      Object target,
      String functionName,
      List positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    debugPrint("[Inject All Getter Static] $functionName ");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }
}
