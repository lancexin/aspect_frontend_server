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

//inject package:vm/kernel_front_end.dart method compileToKernel add ProgramTransformer
Future<KernelCompilationResults> compileToKernelProxy(
  Uri? source,
  CompilerOptions options, {
  List<Uri> additionalSources = const <Uri>[],
  Uri? nativeAssets,
  bool includePlatform = false,
  List<String> deleteToStringPackageUris = const <String>[],
  bool aot = false,
  bool useGlobalTypeFlowAnalysis = false,
  bool useRapidTypeAnalysis = true,
  required Map<String, String> environmentDefines,
  bool enableAsserts = true,
  bool useProtobufTreeShakerV2 = false,
  bool minimalKernel = false,
  bool treeShakeWriteOnlyFields = false,
  String? targetOS = null,
  String? fromDillFile = null,
  //inject here
  ProgramTransformer? transformer,
}) async {
  // Replace error handler to detect if there are compilation errors.
  final errorDetector =
      new ErrorDetector(previousErrorHandler: options.onDiagnostic);
  options.onDiagnostic = errorDetector.call;

  final nativeAssetsLibrary =
      await NativeAssetsSynthesizer.synthesizeLibraryFromYamlFile(
    nativeAssets,
    errorDetector,
    nonNullableByDefaultCompiledMode: options.nnbdMode == NnbdMode.Strong
        ? NonNullableByDefaultCompiledMode.Strong
        : NonNullableByDefaultCompiledMode.Weak,
  );
  if (source == null) {
    return KernelCompilationResults.named(
      nativeAssetsLibrary: nativeAssetsLibrary,
    );
  }

  final target = options.target!;
  options.environmentDefines =
      target.updateEnvironmentDefines(environmentDefines);

  CompilerResult? compilerResult;
  if (fromDillFile != null) {
    compilerResult =
        await loadKernel(options.fileSystem, resolveInputUri(fromDillFile));
  } else {
    compilerResult = await kernelForProgram(source, options,
        additionalSources: additionalSources);
  }
  final Component? component = compilerResult?.component;
  Iterable<Uri>? compiledSources = component?.uriToSource.keys;

  Set<Library> loadedLibraries = createLoadedLibrariesSet(
      compilerResult?.loadedComponents, compilerResult?.sdkComponent,
      includePlatform: includePlatform);

  if (deleteToStringPackageUris.isNotEmpty && component != null) {
    to_string_transformer.transformComponent(
        component, deleteToStringPackageUris);
  }

  //inject here
  if (component != null) {
    transformer?.transform(component);
  }

  // Run global transformations only if component is correct.
  if ((aot || minimalKernel) && component != null) {
    await runGlobalTransformations(target, component, useGlobalTypeFlowAnalysis,
        enableAsserts, useProtobufTreeShakerV2, errorDetector,
        environmentDefines: options.environmentDefines,
        nnbdMode: options.nnbdMode,
        targetOS: targetOS,
        minimalKernel: minimalKernel,
        treeShakeWriteOnlyFields: treeShakeWriteOnlyFields,
        useRapidTypeAnalysis: useRapidTypeAnalysis);

    if (minimalKernel) {
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
