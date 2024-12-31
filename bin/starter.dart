import 'dart:io';
import 'package:args/args.dart';
import 'package:aspect_frontend_server/aspect_frontend_server.dart';
import 'package:aspect_frontend_server/proxy/frontend_server_proxy.dart';

import 'package:frontend_server/frontend_server.dart' as frontend;
import 'package:frontend_server/starter.dart';

Future<void> main(List<String> args) async {
  try {
    ArgResults options = frontend.argParser.parse(args);
    stdout.writeln(
        "!!!!! this is aspect_frontend_server !!!!!! args is:\n ${args}");
    frontend.FrontendCompiler compiler = FrontendCompilerProxy(
      stdout,
      transformer: AspectAopTransformer(),
      unsafePackageSerialization: options["unsafe-package-serialization"],
      incrementalSerialization: options["incremental-serialization"],
      useDebuggerModuleNames: options['debugger-module-names'],
      emitDebugMetadata: options['experimental-emit-debug-metadata'],
      emitDebugSymbols: options['emit-debug-symbols'],
      canaryFeatures: options['dartdevc-canary'],
    );

    final int exitCode = await starter(args, compiler: compiler);
    if (exitCode != 0) {
      exit(exitCode);
    }
  } catch (error, stackTrace) {
    stdout.writeln('ERROR: $error\n $stackTrace');
    stdout.writeln(frontend.usage);
    return;
  }
}
