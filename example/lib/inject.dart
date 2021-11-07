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
  //必须是static,必然不起作用
  static void _test1(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    print(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    Function.apply(proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "_MyHomePageState",
    "methodName": "-_test2",
    "isRegex": false
  })
  //必须是static,必然不起作用
  static Future<bool> _test2(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    print(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "_MyHomePageState",
    "methodName": "+_test3",
    "isRegex": false
  })
  //必须是static,必然不起作用
  static Future<bool> _test3(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) {
    print(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    return Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
  }

  @pragma('vm:entry-point')
  @pragma("aopd:inject", {
    "importUri": "package:example/main.dart",
    "clsName": "",
    "methodName": "+_test4",
    "isRegex": false
  })
  //必须是static,必然不起作用
  static Future<bool> _test4(
      Object target,
      String functionName,
      List<dynamic> positionalParams,
      Map<String, dynamic> namedParams,
      Function proceed) async {
    print(
        "[Inject] $functionName start ${positionalParams[0]} ${positionalParams[1]} ${namedParams["key3"]}");
    bool success = await Function.apply(
        proceed, positionalParams, _transToNamedParams(namedParams));
    print("[Inject] $functionName result ${success}");
    return success;
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
