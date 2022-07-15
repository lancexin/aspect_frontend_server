dart run frontend_server.dart.snapshot --sdk-root /Users/lixin/Documents/flutter_macos_stable/bin/cache/artifacts/engine/common/flutter_patched_sdk/ --target=flutter -Ddart.vm.profile=false -Ddart.vm.product=false   --output-dill app2.dill  test/aspect_frontend_server_test.dart


dart /Users/lixin/Documents/FlutterWorkspace/dart_sdk/sdk/pkg/vm/bin/dump_kernel.dart app2.dill injected.out.dill.txt