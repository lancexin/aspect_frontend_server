// ignore_for_file: import_of_legacy_library_into_null_safe

import 'package:frontend_server/frontend_server.dart';
import "package:vm/kernel_front_end.dart";
export 'package:vm/kernel_front_end.dart';
import 'package:front_end/src/api_unstable/vm.dart'
    show
        CompilerOptions,
        CompilerResult,
        NnbdMode,
        kernelForProgram,
        resolveInputUri;

import 'package:kernel/ast.dart'
    show Component, Library, NonNullableByDefaultCompiledMode;
import 'package:vm/native_assets/synthesizer.dart';
import 'package:vm/transformations/to_string_transformer.dart'
    as to_string_transformer;

import 'package:front_end/src/api_prototype/macros.dart' as macros
    show isMacroLibraryUri;

//inject package:vm/kernel_front_end.dart method compileToKernel add ProgramTransformer
Future<KernelCompilationResults> compileToKernelProxy(
  KernelCompilationArguments args,
  //inject here
  ProgramTransformer? transformer,
) async {
  final options = args.options!;

  // Replace error handler to detect if there are compilation errors.
  final errorDetector =
      new ErrorDetector(previousErrorHandler: options.onDiagnostic);
  options.onDiagnostic = errorDetector.call;

  final nativeAssetsLibrary =
      await NativeAssetsSynthesizer.synthesizeLibraryFromYamlFile(
          args.nativeAssets, errorDetector);
  if (args.source == null) {
    return KernelCompilationResults.named(
      nativeAssetsLibrary: nativeAssetsLibrary,
    );
  }

  final target = options.target!;
  options.environmentDefines =
      target.updateEnvironmentDefines(args.environmentDefines);

  CompilerResult? compilerResult;
  final fromDillFile = args.fromDillFile;
  if (fromDillFile != null) {
    compilerResult =
        await loadKernel(options.fileSystem, resolveInputUri(fromDillFile));
  } else {
    compilerResult = await kernelForProgram(args.source!, options,
        additionalSources: args.additionalSources);
  }
  final Component? component = compilerResult?.component;
  //inject here
  if (component != null) {
    print("start inject here");
    transformer?.transform(component);
    print("end inject here");
  }

  // TODO(https://dartbug.com/55246): track macro deps when available.
  Iterable<Uri>? compiledSources = component?.uriToSource.keys
      .where((uri) => !macros.isMacroLibraryUri(uri));

  Set<Library> loadedLibraries = createLoadedLibrariesSet(
      compilerResult?.loadedComponents, compilerResult?.sdkComponent,
      includePlatform: args.includePlatform);

  if (args.deleteToStringPackageUris.isNotEmpty && component != null) {
    to_string_transformer.transformComponent(
        component, args.deleteToStringPackageUris);
  }

  // Run global transformations only if component is correct.
  if ((args.aot || args.minimalKernel) && component != null) {
    await runGlobalTransformations(target, component, errorDetector, args);

    if (args.minimalKernel) {
      // compiledSources is component.uriToSource.keys.
      // Make a copy of compiledSources to detach it from
      // component.uriToSource which is cleared below.
      compiledSources = compiledSources!.toList();

      component.metadata.clear();
      component.uriToSource.clear();
    }
  }

  // Restore error handler (in case 'options' are reused).
  options.onDiagnostic = errorDetector.previousErrorHandler;

  return KernelCompilationResults.named(
    component: component,
    nativeAssetsLibrary: nativeAssetsLibrary,
    loadedLibraries: loadedLibraries,
    classHierarchy: compilerResult?.classHierarchy,
    coreTypes: compilerResult?.coreTypes,
    compiledSources: compiledSources,
  );
}
