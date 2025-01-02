# aspect_frontend_server

AOP for Flutter(Dart)，support up to flutter 3.24.3

# One step at a time
Download frontend_server.dart.snapshot and overwrite /fvm/versions/3.24.3/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot


# Before Compile
1.  Download dart-sdk,The specific download method can be viewed: https://github.com/dart-lang/sdk/wiki/Building 

Recommended to download using dept_tools, as downloading the SDK directly from GitHub will not have the package you need in the third_party directory

1. Switch the dark sdk to the version corresponding to Flutter. Generally, the dark version corresponding to Flutter can be used interchangeably, but if Flutter has a major version upgrade, it needs to be switched to the corresponding version.
2. I use FVM to manage Flutter version. If you are not, you need to pay attention to the path of the following command


# Compile

dart compile aot-snapshot --output=frontend_server_aot_macos.dart.snapshot --target-os macos bin/starter.dart
dart compile aot-snapshot --output=frontend_server_aot_windows.dart.snapshot --target-os windows bin/starter.dart
dart compile aot-snapshot --output=frontend_server_aot_linux.dart.snapshot --target-os linux bin/starter.dart

dart compile kernel --output=dump_kernel.dart.snapshot bin/dump_kernel.dart




## Test compile aot dill
.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dartaotruntime frontend_server_aot.dart_macos.snapshot --sdk-root ~/fvm/versions/3.24.3/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --aot --tfa --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages example/.dart_tool/package_config.json --output-dill app.aot --depfile example/.dart_tool/flutter_build/31a7f421330fdca23d68f3c09767c0a5/kernel_snapshot.d package:example/main.dart

Attention：31a7f421330fdca23d68f3c09767c0a5 ,you need update this folder to you own.

## 编译运行时dill
.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dartaotruntime  frontend_server_aot.dart_macos.snapshot --sdk-root ~/fvm/versions/3.24.3/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter --no-print-incremental-dependencies -Dflutter.inspector.structuredErrors=true -DFLUTTER_WEB_AUTO_DETECT=true -Ddart.vm.profile=false -Ddart.vm.product=false --enable-asserts --track-widget-creation --packages example/.dart_tool/package_config.json --output-dill app.dill --depfile example/.dart_tool/flutter_build/31a7f421330fdca23d68f3c09767c0a5/kernel_snapshot.d package:example/main.dart

Attention：31a7f421330fdca23d68f3c09767c0a5 ,you need update this folder to you own.



## Test AOT compilation into binary
~/fvm/versions/3.24.3/bin/cache/artifacts/engine/android-arm64-release/darwin-x64/gen_snapshot --deterministic --snapshot_kind=app-aot-elf --elf=app.so --strip app.dill

## Check inject success
dart run dump_kernel.dart.snapshot app.dill injected.out.dill.txt


dart run dump_kernel.dart.snapshot  /Users/yourname/Documents/FlutterWorkspace/aspect_frontend_server/example/.dart_tool/flutter_build/31a7f421330fdca23d68f3c09767c0a5/app.dill injected.out.dill.txt

## Test compile snapshot_assembly.S 
.fvm/versions/3.24.3/bin/cache/artifacts/engine/darwin-x64-release/gen_snapshot_x64 --deterministic --snapshot_kind=app-aot-assembly --assembly=/Users/yourname/Documents/FlutterWorkspace/aspect_frontend_server/snapshot_assembly.S /Users/yourname/Documents/FlutterWorkspace/aspect_frontend_server/app.dill



# replace the frontend_server.dart.snapshot
1.Overwrite the newly compiled frontend_derver.aot.dart.snapshot to ~/fvm/versions/3.24.3/bin/cache/dart-sdk/bin/snapshots

2.Attention to replacing the corresponding version of the system. If it is macOS, it should be frontend_ server_aot_ macos.dart.snapshot,  I am a Mac system and have not tested other system versions.

# Test
cd example && flutter clean && flutter pub get && flutter run











