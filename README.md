# aspect_frontend_server

编译frontend_server.dart.snapshot,让其具有aop的功能


# 懒人做法,一步到位
下载frontend_server.dart.snapshot并覆盖 flutter_macos_stable/bin/cache/artifacts/engine/darwin-x64/frontend_server.dart.snapshot
和 
flutter_macos_stable/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot


# 编译之前
1. 下载最新的dart-sdk,具体下载方法可以查看https://github.com/dart-lang/sdk/wiki/Building,这里建议用depot_tools的方式下载,因为直接下载github上的sdk,third_party目录下面不会有你需要的包
2. 将dart-sdk切换到flutter对应的版本,一般情况下flutter对应的dart版本是可以通用的,但是如果flutter有大版本升级,需要切换到对应的版本.
3. 修改rebased_package_config.json中依赖库rootUri指向你现在的dart-sdk绝对路径

# 关于ide代码报错
1. 并不影响程序的编译,因为包的依赖关系是在rebased_package_config.json的,
2. 如果不想看到报错或需要代码提示功能,可以rebased_package_config.json替换.dart_tool/package_config.json

# 编译方式
dart --deterministic --no-sound-null-safety --packages=rebased_package_config.json --snapshot=frontend_server.dart.snapshot --snapshot-kind=kernel lib/starter.dart

# 测试编译
1. 生成kernel_snapshot.d,先用普通方法run一下example,在example/.dart_tool/flutter_build下面会有生成编译临时的文件

2. 执行下面命令测试(注意目录替换)):

## 编译aot dill
dart run frontend_server.dart.snapshot --sdk-root /Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --aot --tfa --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/package_config.json --output-dill app.dill --depfile /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/flutter_build/730517d7235d663c88ce8507989673e9/kernel_snapshot.d package:example/main.dart

## 编译运行时dill
dart run frontend_server.dart.snapshot --sdk-root /Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/package_config.json --output-dill app.dill --depfile /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/flutter_build/730517d7235d663c88ce8507989673e9/kernel_snapshot.d package:example/main.dart

## 测试aot编译成二进制
/Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/android-arm64-release/darwin-x64/gen_snapshot --deterministic --snapshot_kind=app-aot-elf --elf=app.so --strip app.dill


# 替换flutter中的frontend_server.dart.snapshot
将新编译的frontend_server.dart.snapshot覆盖 flutter_macos_stable/bin/cache/artifacts/engine/darwin-x64/frontend_server.dart.snapshot

# 测试运行
cd example
flutter run

### 该方法和aspectd的区别
1. aspectd不支持flutter 2.5.4以上,本项目最高支持到2.10.1,再高没有测过
2. aspectd使用前需要对flutter tools的代码进行修改,本项目只需要替换flutter sdk对应的frontend_server.dart.snapshot即可
3. aspectd的实现原理过于复杂,本项目去掉了Call,Inject等用法保留了Execute用法的同时对注入逻辑进行了简化
4. aspectd还需要aspect_impl等,本项目可以直接在主程序代码中添加注入代码,也可以用plugin的方式添加
5. 本项目不需要引入任何第三方包,用pragma注解完成对应插桩
6. 可以有限制支持hot reload,完全支持hot restart,免去了冷重启的烦恼
7. 为了性能优化inject方法限制必须是static的
8. 添加对全局所有的catch进行注入

### 为什么用pragma注解,而不是自定义注解?
本项目是在aot优化后再对字节码进行修改,aot优化后只有白名单中的注解才能被识别到,pragma是在白名单中的注解.






