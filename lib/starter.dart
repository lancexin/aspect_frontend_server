library aspect_frontend_server;
// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:io';
import 'package:args/args.dart';

import 'package:frontend_server/frontend_server.dart' as frontend;
import 'transformers.dart';

Future<void> main(List<String> args) async {
  try {
    ArgResults options = frontend.argParser.parse(args);
    frontend.FrontendCompiler compiler = frontend.FrontendCompiler(stdout,
        printerFactory: frontend.BinaryPrinterFactory(),
        //添加注入逻辑
        transformer: AspectAopTransformer(),
        unsafePackageSerialization: options['unsafe-package-serialization'],
        incrementalSerialization: options['incremental-serialization'],
        useDebuggerModuleNames: options['debugger-module-names'],
        emitDebugMetadata: options['experimental-emit-debug-metadata'],
        emitDebugSymbols: options['emit-debug-symbols']);
    final int exitCode = await frontend.starter(args, compiler: compiler);
    if (exitCode != 0) {
      exit(exitCode);
    }
  } catch (error) {
    print('ERROR: $error\n');
    print(frontend.usage);
    return;
  }
}
