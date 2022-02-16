# aspect_frontend_server

编译frontend_server.dart.snapshot,让其具有aop的功能


# 懒人做法,一步到位

下载frontend_server.dart.snapshot并覆盖 flutter_macos_stable/bin/cache/artifacts/engine/darwin-x64/frontend_server.dart.snapshot

# 编译之前
1. 下载最新的dart-sdk,下载地址:https://github.com/dart-lang/sdk
2. 将dart-sdk切换到 2.14.4: git checkout 2.14.4
3. 修改rebased_package_config.json,rootUri指向dart-sdk
4. 有些third_party目录下的包可能没有,这需要修改成host对应的地址在flutter_macos_stable/.pub-cache/hosted

# 关于ide代码报错
1. 并不影响程序的编译,因为包的依赖关系是在rebased_package_config.json的,
2. 如果不想看到报错或需要代码提示功能,可以rebased_package_config.json替换.dart_tool/package_config.json

# 编译方式
dart --deterministic --no-sound-null-safety --packages=rebased_package_config.json --snapshot=frontend_server.dart.snapshot --snapshot-kind=kernel lib/starter.dart

# 测试编译
1. 生成kernel_snapshot.d,先用普通方法run一下example,在example/.dart_tool/flutter_build下面会有生成编译临时的文件

2. 执行下面命令测试(注意目录替换)):

编译aot dill
dart run frontend_server.dart.snapshot --sdk-root /Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --aot --tfa --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/package_config.json --output-dill app.dill --depfile /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/flutter_build/b0fee5c86b6ccb9c75440c36f0f7cea4/kernel_snapshot.d package:example/main.dart

编译运行时dill
dart run frontend_server.dart.snapshot --sdk-root /Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --verbose --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/package_config.json --output-dill app.dill --depfile /Users/lixin/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/flutter_build/b0fee5c86b6ccb9c75440c36f0f7cea4/kernel_snapshot.d package:example/main.dart

测试aot编译成二进制
/Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/android-arm64-release/darwin-x64/gen_snapshot --deterministic --snapshot_kind=app-aot-elf --elf=app.so --strip app.dill


# 替换flutter中的frontend_server.dart.snapshot
将新编译的frontend_server.dart.snapshot覆盖 flutter_macos_stable/bin/cache/artifacts/engine/darwin-x64/frontend_server.dart.snapshot

# 测试运行
cd example
flutter run

### 该方法和aspectd的区别
1. aspectd不支持flutter 2.5.4,本项目是基于flutter 2.5.4测试
2. aspectd的编译需要对dart sdk中的vm进行修改,本项目不需要
3. aspectd使用前需要对flutter tools的代码进行修改,本项目只需要替换flutter sdk对应的frontend_server.dart.snapshot即可
4. aspectd的实现原理过于复杂,本项目去掉了Call,Inject等用法保留了Execute用法的同时对注入逻辑进行了简化
5. aspectd还需要aspect_impl等,本项目可以直接在主程序代码中添加注入代码,也可以用plugin的方式添加
6. 本项目不需要引入任何第三方包,用pragma注解完成对应插桩
7. 可以有限制支持hot reload,完全支持hot restart,免去了冷重启的烦恼
8. 为了性能优化inject方法限制必须是static的

### 为什么用pragma注解,而不是自定义注解?
本项目是在aot优化后再对字节码进行修改,aot优化后只有白名单中的注解才能被识别到,pragma是在白名单中的注解.






