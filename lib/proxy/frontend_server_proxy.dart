// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: implementation_imports, constant_identifier_names

// front_end/src imports below that require lint `ignore_for_file` are a
// temporary state of things until frontend team builds better api that would
// replace api used below. This api was made private in an effort to discourage
// further use.

import 'dart:async';
import 'dart:io' show File, IOSink, stdout;

import 'package:args/args.dart';
import 'package:dev_compiler/dev_compiler.dart'
    show
        DevCompilerTarget,
        ExpressionCompiler,
        ProgramCompiler,
        parseModuleFormat;
import 'package:front_end/src/api_unstable/vm.dart';
import 'package:front_end/src/api_unstable/ddc.dart' as ddc
    show IncrementalCompiler;
import 'package:kernel/ast.dart' show Library, LibraryDependency, Procedure;
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/kernel.dart'
    show Component, loadComponentSourceFromBytes, writeComponentToText;
import 'package:kernel/target/targets.dart' show targets, TargetFlags;
import 'package:vm/incremental_compiler.dart' show IncrementalCompiler;
import 'package:package_config/package_config.dart';
import 'package:vm/kernel_front_end.dart';
// For possible --target-os values.
import 'package:frontend_server/frontend_server.dart';

import 'package:frontend_server/src/uuid.dart';
import 'package:frontend_server/src/javascript_bundle.dart';
import 'package:front_end/src/api_prototype/macros.dart' as macros
    show isMacroLibraryUri;

import 'kernel_front_end_proxy.dart';

class FrontendCompilerProxy extends FrontendCompiler {
  FrontendCompilerProxy(
    super.outputStream, {
    super.printerFactory,
    super.transformer,
    super.unsafePackageSerialization,
    super.incrementalSerialization = true,
    super.useDebuggerModuleNames = false,
    super.emitDebugMetadata = false,
    super.emitDebugSymbols = false,
    super.canaryFeatures = false,
  }) : _outputStream = outputStream ?? stdout;

  final StringSink _outputStream;

  /// Initialized in [compile].
  late List<Uri> _additionalSources;
  late bool _assumeInitializeFromDillUpToDate;
  late CompilerOptions _compilerOptions;
  late FileSystem _fileSystem;
  late IncrementalCompiler _generator;
  late String _initializeFromDill;
  late String _kernelBinaryFilename;
  late String _kernelBinaryFilenameIncremental;
  late String _kernelBinaryFilenameFull;
  late Uri _mainSource;
  late ArgResults _options;
  late bool _printIncrementalDependencies;
  late ProcessedOptions _processedOptions;

  /// Initialized in [compile] from options, or (re)set in [setNativeAssets].
  Uri? _nativeAssets;

  /// Cached compilation of [_nativeAssets].
  ///
  /// Managed by [_compileNativeAssets] and [setNativeAssets].
  Library? _nativeAssetsLibrary;

  /// Initialized in [writeJavaScriptBundle].
  IncrementalJavaScriptBundler? _bundler;

  void _installDartdevcTarget() {
    targets['dartdevc'] = (TargetFlags flags) => new DevCompilerTarget(flags);
  }

  @override
  Future<bool> compile(
    String entryPoint,
    ArgResults options, {
    IncrementalCompiler? generator,
  }) async {
    stdout.writeln('start compile');
    _options = options;
    _fileSystem = createFrontEndFileSystem(
        options['filesystem-scheme'], options['filesystem-root'],
        allowHttp: options['enable-http-uris']);
    _mainSource = resolveInputUri(entryPoint);
    _additionalSources =
        (options['source'] as List<String>).map(resolveInputUri).toList();
    final String? nativeAssets = options['native-assets'] as String?;
    if (_nativeAssets == null && nativeAssets != null) {
      _nativeAssets = resolveInputUri(nativeAssets);
    }
    _kernelBinaryFilenameFull = _options['output-dill'] ?? '$entryPoint.dill';
    _kernelBinaryFilenameIncremental = _options['output-incremental-dill'] ??
        (_options['output-dill'] != null
            ? '${_options['output-dill']}.incremental.dill'
            : '$entryPoint.incremental.dill');
    _kernelBinaryFilename = _kernelBinaryFilenameFull;
    _initializeFromDill =
        _options['initialize-from-dill'] ?? _kernelBinaryFilenameFull;
    _assumeInitializeFromDillUpToDate =
        _options['assume-initialize-from-dill-up-to-date'] ?? false;
    _printIncrementalDependencies = _options['print-incremental-dependencies'];
    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    final Uri sdkRoot = _ensureFolderPath(options['sdk-root']);
    final String platformKernelDill =
        options['platform'] ?? 'platform_strong.dill';
    final String? packagesOption = _options['packages'];
    final bool soundNullSafety = _options['sound-null-safety'];
    if (!soundNullSafety) {
      print('Error: --no-sound-null-safety is not supported.');
      return false;
    }
    final CompilerOptions compilerOptions = new CompilerOptions()
      ..sdkRoot = sdkRoot
      ..fileSystem = _fileSystem
      ..packagesFileUri =
          packagesOption != null ? resolveInputUri(packagesOption) : null
      ..sdkSummary = sdkRoot.resolve(platformKernelDill)
      ..verbose = options['verbose']
      ..embedSourceText = options['embed-source-text']
      ..explicitExperimentalFlags = parseExperimentalFlags(
          parseExperimentalArguments(options['enable-experiment']),
          onError: (msg) => errors.add(msg))
      ..onDiagnostic = _onDiagnostic
      ..verbosity = Verbosity.parseArgument(options['verbosity'],
          onError: (msg) => errors.add(msg));
    _compilerOptions = compilerOptions;

    if (options.wasParsed('libraries-spec')) {
      compilerOptions.librariesSpecificationUri =
          resolveInputUri(options['libraries-spec']);
    }

    if (options.wasParsed('filesystem-root')) {
      if (_options['output-dill'] == null) {
        print('When --filesystem-root is specified it is required to specify'
            ' --output-dill option that points to physical file system location'
            ' of a target dill file.');
        return false;
      }
    }

    final Map<String, String> environmentDefines = {};
    if (!parseCommandLineDefines(
        options['define'], environmentDefines, usage)) {
      return false;
    }

    if (options['aot']) {
      if (!options['link-platform']) {
        print('Error: --no-link-platform option cannot be used with --aot');
        return false;
      }
      if (options['split-output-by-packages']) {
        print('Error: --split-output-by-packages option cannot be used '
            'with --aot');
        return false;
      }
      if (options['incremental']) {
        print('Error: --incremental option cannot be used with --aot');
        return false;
      }
      if (options['import-dill'] != null) {
        print('Error: --import-dill option cannot be used with --aot');
        return false;
      }
    }

    if (options['target-os'] != null) {
      if (!options['aot']) {
        print('Error: --target-os option must be used with --aot');
        return false;
      }
    }

    if (options['support-mirrors'] == true) {
      if (options['aot']) {
        print('Error: --support-mirrors option cannot be used with --aot');
        return false;
      }
      if (options['minimal-kernel']) {
        print('Error: --support-mirrors option cannot be used with '
            '--minimal-kernel');
        return false;
      }
    }

    if (options['incremental']) {
      if (options['from-dill'] != null) {
        print('Error: --from-dill option cannot be used with --incremental');
        return false;
      }
    }

    // Initialize additional supported kernel targets.
    _installDartdevcTarget();
    compilerOptions.target = createFrontEndTarget(
      options['target'],
      trackWidgetCreation: options['track-widget-creation'],
      supportMirrors: options['support-mirrors'] ??
          !(options['aot'] || options['minimal-kernel']),
    );
    if (compilerOptions.target == null) {
      print('Failed to create front-end target ${options['target']}.');
      return false;
    }

    final String? importDill = options['import-dill'];
    if (importDill != null) {
      compilerOptions.additionalDills = <Uri>[
        Uri.base.resolveUri(new Uri.file(importDill))
      ];
    }

    _processedOptions = new ProcessedOptions(options: compilerOptions);

    KernelCompilationResults? results;
    IncrementalSerializer? incrementalSerializer;
    if (options['incremental']) {
      _compilerOptions.environmentDefines =
          _compilerOptions.target!.updateEnvironmentDefines(environmentDefines);

      _compilerOptions.omitPlatform = false;
      _generator =
          generator ?? _createGenerator(new Uri.file(_initializeFromDill));
      await invalidateIfInitializingFromDill();
      IncrementalCompilerResult compilerResult =
          await _runWithPrintRedirection(() => _generator.compile());
      Component component = compilerResult.component;

      //inject here
      transformer?.transform(component);
      await _compileNativeAssets();

      results = new KernelCompilationResults.named(
        component: component,
        nativeAssetsLibrary: _nativeAssetsLibrary,
        classHierarchy: compilerResult.classHierarchy,
        coreTypes: compilerResult.coreTypes,
        // TODO(https://dartbug.com/55246): track macro deps when available.
        compiledSources: component.uriToSource.keys
            .where((uri) => !macros.isMacroLibraryUri(uri)),
      );

      incrementalSerializer = _generator.incrementalSerializer;
    } else {
      if (options['link-platform']) {
        // TODO(aam): Remove linkedDependencies once platform is directly
        // embedded into VM snapshot and http://dartbug.com/30111 is fixed.
        compilerOptions.additionalDills = <Uri>[
          sdkRoot.resolve(platformKernelDill)
        ];
      }
      results = await _runWithPrintRedirection(() => compileToKernelProxy(
            new KernelCompilationArguments(
                source: _mainSource,
                options: compilerOptions,
                additionalSources: _additionalSources,
                nativeAssets: _nativeAssets,
                includePlatform: options['link-platform'],
                deleteToStringPackageUris:
                    options['delete-tostring-package-uri'],
                keepClassNamesImplementing:
                    options['keep-class-names-implementing'],
                aot: options['aot'],
                targetOS: options['target-os'],
                useGlobalTypeFlowAnalysis: options['tfa'],
                useRapidTypeAnalysis: options['rta'],
                environmentDefines: environmentDefines,
                enableAsserts: options['enable-asserts'],
                useProtobufTreeShakerV2: options['protobuf-tree-shaker-v2'],
                minimalKernel: options['minimal-kernel'],
                treeShakeWriteOnlyFields:
                    options['tree-shake-write-only-fields'],
                fromDillFile: options['from-dill']),
            transformer,
          ));
    }
    if (results!.component != null) {
      //transformer?.transform(results.component!);

      // await _runWithPrintRedirection(() async {
      //   var path = "inject.out.txt";
      //   print("writeComponentToText path is $path");
      //   writeComponentToText(results!.component!, path: path);
      // });

      if (_compilerOptions.target!.name == 'dartdevc') {
        await writeJavaScriptBundle(results, _kernelBinaryFilename,
            options['filesystem-scheme'], options['dartdevc-module-format'],
            fullComponent: true);
      }
      await writeDillFile(
        results,
        _kernelBinaryFilename,
        filterExternal: importDill != null || options['minimal-kernel'],
        incrementalSerializer: incrementalSerializer,
      );

      _outputStream.writeln(boundaryKey);
      final Iterable<Uri> compiledSources = results.compiledSources!;
      await _outputDependenciesDelta(compiledSources);
      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      final String? depfile = options['depfile'];
      if (depfile != null) {
        // TODO(https://dartbug.com/55246): track macro deps when available.
        await writeDepfile(compilerOptions.fileSystem, compiledSources,
            _kernelBinaryFilename, depfile);
      }

      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else {
      _outputStream.writeln(boundaryKey);
    }
    results = null; // Fix leak: Probably variation of http://dartbug.com/36983.
    return errors.isEmpty;
  }

  Future<T> _runWithPrintRedirection<T>(Future<T> Function() f) {
    return runZoned(() => new Future<T>(f),
        zoneSpecification: new ZoneSpecification(
            print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
                _outputStream.writeln(line)));
  }

  void _onDiagnostic(DiagnosticMessage message) {
    switch (message.severity) {
      case Severity.error:
      case Severity.internalProblem:
        errors.addAll(message.plainTextFormatted);
        break;
      case Severity.warning:
      case Severity.info:
        break;
      case Severity.context:
      case Severity.ignored:
        throw 'Unexpected severity: ${message.severity}';
    }
    if (Verbosity.shouldPrint(_compilerOptions.verbosity, message)) {
      printDiagnosticMessage(message, _outputStream.writeln);
    }
  }

  /// Compiles [_nativeAssets] into [_nativeAssetsLibrary].
  ///
  /// [compile] and [recompileDelta] invoke this, and bundles the cached
  /// [_nativeAssetsLibrary] in the dill file.
  Future<void> _compileNativeAssets() async {
    final Uri? nativeAssets = _nativeAssets;
    if (nativeAssets == null || _nativeAssetsLibrary != null) {
      return;
    }

    final KernelCompilationResults results = await _runWithPrintRedirection(
      () => compileToKernelProxy(
          new KernelCompilationArguments(
            options: _compilerOptions,
            nativeAssets: _nativeAssets,
          ),
          transformer),
    );
    _nativeAssetsLibrary = results.nativeAssetsLibrary;
  }

  IncrementalCompiler _createGenerator(Uri? initializeFromDillUri) {
    return new IncrementalCompiler(
        _compilerOptions, [_mainSource, ..._additionalSources],
        initializeFromDillUri: initializeFromDillUri,
        incrementalSerialization: incrementalSerialization);
  }

  Uri _ensureFolderPath(String path) {
    String uriPath = new Uri.file(path).toString();
    if (!uriPath.endsWith('/')) {
      uriPath = '$uriPath/';
    }
    return Uri.base.resolve(uriPath);
  }

  Future<void> _outputDependenciesDelta(Iterable<Uri> compiledSources) async {
    if (!_printIncrementalDependencies) {
      return;
    }
    Set<Uri> uris = {};
    for (Uri uri in compiledSources) {
      // Skip empty or corelib dependencies.
      if (uri.isScheme('org-dartlang-sdk')) continue;
      uris.add(uri);
    }
    for (Uri uri in uris) {
      if (previouslyReportedDependencies.contains(uri)) {
        continue;
      }
      try {
        _outputStream.writeln('+${await asFileUri(_fileSystem, uri)}');
      } on FileSystemException {
        // Ignore errors from invalid import uris.
      }
    }
    for (Uri uri in previouslyReportedDependencies) {
      if (uris.contains(uri)) {
        continue;
      }
      try {
        _outputStream.writeln('-${await asFileUri(_fileSystem, uri)}');
      } on FileSystemException {
        // Ignore errors from invalid import uris.
      }
    }
    previouslyReportedDependencies = uris;
  }

  Future<void> writeDillFile(
    KernelCompilationResults results,
    String filename, {
    bool filterExternal = false,
    IncrementalSerializer? incrementalSerializer,
  }) async {
    final Component component = results.component!;
    final Library? nativeAssetsLibrary = results.nativeAssetsLibrary;

    final IOSink sink = new File(filename).openWrite();

    final Set<Library> loadedLibraries = results.loadedLibraries;
    final BinaryPrinter printer = filterExternal
        ? new BinaryPrinter(sink,
            libraryFilter: (lib) => !loadedLibraries.contains(lib),
            includeSources: false)
        : printerFactory.newBinaryPrinter(sink);

    sortComponent(component);

    if (incrementalSerializer != null) {
      incrementalSerializer.writePackagesToSinkAndTrimComponent(
          component, sink);
    } else if (unsafePackageSerialization == true) {
      writePackagesToSinkAndTrimComponent(component, sink);
    }

    printer.writeComponentFile(component);

    if (nativeAssetsLibrary != null) {
      final BinaryPrinter printer = new BinaryPrinter(sink);
      printer.writeComponentFile(new Component(
        libraries: [nativeAssetsLibrary],
        mode: nativeAssetsLibrary.nonNullableByDefaultCompiledMode,
      ));
    }
    await sink.close();

    if (_options['split-output-by-packages']) {
      await writeOutputSplitByPackages(
          _mainSource, _compilerOptions, results, filename);
    }

    final String? manifestFilename = _options['far-manifest'];
    if (manifestFilename != null) {
      final String output = _options['output-dill'];
      final String? dataDir = _options.options.contains('component-name')
          ? _options['component-name']
          : _options['data-dir'];
      await createFarManifest(output, dataDir, manifestFilename);
    }
  }

  Future<void> invalidateIfInitializingFromDill() async {
    if (_assumeInitializeFromDillUpToDate) return;
    if (_kernelBinaryFilename != _kernelBinaryFilenameFull) return;
    // If the generator is initialized, it's not going to initialize from dill
    // again anyway, so there's no reason to spend time invalidating what should
    // be invalidated by the normal approach anyway.
    if (_generator.initialized) return;

    final File f = new File(_initializeFromDill);
    if (!f.existsSync()) return;

    Component component;
    try {
      component = loadComponentSourceFromBytes(f.readAsBytesSync());
    } catch (e) {
      // If we cannot load the dill file we shouldn't initialize from it.
      _generator = _createGenerator(null);
      return;
    }

    nextUri:
    for (Uri uri in component.uriToSource.keys) {
      if ('$uri' == '') continue nextUri;

      final List<int> oldBytes = component.uriToSource[uri]!.source;
      FileSystemEntity entity;
      try {
        entity = _compilerOptions.fileSystem.entityForUri(uri);
      } catch (_) {
        // Ignore errors that might be caused by non-file uris.
        continue nextUri;
      }

      bool exists;
      try {
        exists = await entity.exists();
      } catch (e) {
        exists = false;
      }

      if (!exists) {
        _generator.invalidate(uri);
        continue nextUri;
      }
      final List<int> newBytes = await entity.readAsBytes();
      if (oldBytes.length != newBytes.length) {
        _generator.invalidate(uri);
        continue nextUri;
      }
      for (int i = 0; i < oldBytes.length; ++i) {
        if (oldBytes[i] != newBytes[i]) {
          _generator.invalidate(uri);
          continue nextUri;
        }
      }
    }
  }

  @override
  Future<bool> compileNativeAssetsOnly(
    ArgResults options, {
    IncrementalCompiler? generator,
  }) async {
    _fileSystem = createFrontEndFileSystem(
      options['filesystem-scheme'],
      options['filesystem-root'],
      allowHttp: options['enable-http-uris'],
    );
    _options = options;
    final String? nativeAssets = options['native-assets'] as String?;
    if (_nativeAssets == null && nativeAssets != null) {
      _nativeAssets = resolveInputUri(nativeAssets);
    }
    if (_nativeAssets == null) {
      print(
        'Error: When --native-assets-only is specified it is required to'
        ' specify --native-assets option that points to physical file system'
        ' location of a source native_assets.yaml file.',
      );
      return false;
    }
    if (_options['output-dill'] == null) {
      print(
        'Error: When --native-assets-only is specified it is required to'
        ' specify --output-dill option that points to physical file system'
        ' location of a target dill file.',
      );
      return false;
    }
    _kernelBinaryFilename = _options['output-dill'];
    final CompilerOptions compilerOptions = new CompilerOptions();
    _compilerOptions = compilerOptions;

    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    await _compileNativeAssets();
    await writeDillFileNativeAssets(
      _nativeAssetsLibrary!,
      _kernelBinaryFilename,
    );
    _outputStream.writeln(boundaryKey);
    _outputStream.writeln('+${await asFileUri(_fileSystem, _nativeAssets!)}');
    _outputStream
        .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
    return true;
  }

  @override
  Future<bool> setNativeAssets(String nativeAssets) async {
    _nativeAssetsLibrary = null; // Purge compiled cache.
    _nativeAssets = resolveInputUri(nativeAssets);
    return true;
  }

  Future<void> writeJavaScriptBundle(KernelCompilationResults results,
      String filename, String fileSystemScheme, String moduleFormat,
      {required bool fullComponent}) async {
    PackageConfig packageConfig = await loadPackageConfigUri(
        _compilerOptions.packagesFileUri ??
            new File('.dart_tool/package_config.json').absolute.uri);
    final Component component = results.component!;

    final IncrementalJavaScriptBundler bundler =
        _bundler ??= new IncrementalJavaScriptBundler(
      _compilerOptions.fileSystem,
      results.loadedLibraries,
      fileSystemScheme,
      useDebuggerModuleNames: useDebuggerModuleNames,
      emitDebugMetadata: emitDebugMetadata,
      moduleFormat: moduleFormat,
      canaryFeatures: canaryFeatures,
    );
    if (fullComponent) {
      await bundler.initialize(component, _mainSource, packageConfig);
    } else {
      await bundler.invalidate(
          component,
          _generator.lastKnownGoodResult!.component,
          _mainSource,
          packageConfig);
    }

    // Create JavaScript bundler.
    final File sourceFile = new File('$filename.sources');
    final File manifestFile = new File('$filename.json');
    final File sourceMapsFile = new File('$filename.map');
    final File metadataFile = new File('$filename.metadata');
    final File symbolsFile = new File('$filename.symbols');
    if (!sourceFile.parent.existsSync()) {
      sourceFile.parent.createSync(recursive: true);
    }

    final IOSink sourceFileSink = sourceFile.openWrite();
    final IOSink manifestFileSink = manifestFile.openWrite();
    final IOSink sourceMapsFileSink = sourceMapsFile.openWrite();
    final IOSink? metadataFileSink =
        emitDebugMetadata ? metadataFile.openWrite() : null;
    final IOSink? symbolsFileSink =
        emitDebugSymbols ? symbolsFile.openWrite() : null;
    final Map<String, ProgramCompiler> kernel2JsCompilers =
        await bundler.compile(
            results.classHierarchy!,
            results.coreTypes!,
            packageConfig,
            sourceFileSink,
            manifestFileSink,
            sourceMapsFileSink,
            metadataFileSink,
            symbolsFileSink);
    cachedProgramCompilers.addAll(kernel2JsCompilers);
    await Future.wait([
      sourceFileSink.close(),
      manifestFileSink.close(),
      sourceMapsFileSink.close(),
      if (metadataFileSink != null) metadataFileSink.close(),
      if (symbolsFileSink != null) symbolsFileSink.close(),
    ]);
  }

  Future<void> writeDillFileNativeAssets(
    Library nativeAssetsLibrary,
    String filename,
  ) async {
    final IOSink sink = new File(filename).openWrite();
    final BinaryPrinter printer = new BinaryPrinter(sink);
    printer.writeComponentFile(new Component(
      libraries: [nativeAssetsLibrary],
      mode: nativeAssetsLibrary.nonNullableByDefaultCompiledMode,
    ));
    await sink.close();
  }

  @override
  Future<void> recompileDelta({String? entryPoint}) async {
    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    await invalidateIfInitializingFromDill();
    if (entryPoint != null) {
      _mainSource = resolveInputUri(entryPoint);
    }
    errors.clear();

    IncrementalCompilerResult deltaProgramResult = await _generator
        .compile(entryPoints: [_mainSource, ..._additionalSources]);
    Component deltaProgram = deltaProgramResult.component;
    transformer?.transform(deltaProgram);

    await _compileNativeAssets();

    KernelCompilationResults results = new KernelCompilationResults.named(
      component: deltaProgram,
      classHierarchy: deltaProgramResult.classHierarchy,
      coreTypes: deltaProgramResult.coreTypes,
      compiledSources: deltaProgram.uriToSource.keys,
      nativeAssetsLibrary: _nativeAssetsLibrary,
    );

    if (_compilerOptions.target!.name == 'dartdevc') {
      await writeJavaScriptBundle(results, _kernelBinaryFilename,
          _options['filesystem-scheme'], _options['dartdevc-module-format'],
          fullComponent: false);
    } else {
      await writeDillFile(results, _kernelBinaryFilename,
          incrementalSerializer: _generator.incrementalSerializer);
    }

    _outputStream.writeln(boundaryKey);
    await _outputDependenciesDelta(results.compiledSources!);
    _outputStream
        .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
    _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
  }

  @override
  Future<void> compileExpression(
      String expression,
      List<String> definitions,
      List<String> definitionTypes,
      List<String> typeDefinitions,
      List<String> typeBounds,
      List<String> typeDefaults,
      String libraryUri,
      String? klass,
      String? method,
      int offset,
      String? scriptUri,
      bool isStatic) async {
    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    Procedure? procedure = await _generator.compileExpression(
        expression,
        definitions,
        definitionTypes,
        typeDefinitions,
        typeBounds,
        typeDefaults,
        libraryUri,
        klass,
        method,
        offset,
        scriptUri,
        isStatic);
    if (procedure != null) {
      Component component = createExpressionEvaluationComponent(procedure);

      //inject here
      transformer?.transform(component);
      final IOSink sink = new File(_kernelBinaryFilename).openWrite();
      sink.add(serializeComponent(component));
      await sink.close();
      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else {
      _outputStream.writeln(boundaryKey);
    }
  }

  @override
  Future<void> compileExpressionToJs(
      String libraryUri,
      String? scriptUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) async {
    _generator.accept();
    errors.clear();

    if (_bundler == null) {
      reportError('JavaScript bundler is null');
      return;
    }
    if (!cachedProgramCompilers.containsKey(moduleName)) {
      reportError('Cannot find kernel2js compiler for $moduleName.');
      return;
    }

    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');

    _processedOptions.ticker
        .logMs('Compiling expression to JavaScript in $moduleName');

    final ProgramCompiler kernel2jsCompiler =
        cachedProgramCompilers[moduleName]!;
    IncrementalCompilerResult compilerResult = _generator.lastKnownGoodResult!;
    Component component = compilerResult.component;

    //inject here
    transformer?.transform(component);
    component.computeCanonicalNames();

    _processedOptions.ticker.logMs('Computed component');

    final ExpressionCompiler expressionCompiler = new ExpressionCompiler(
      _compilerOptions,
      parseModuleFormat(_options['dartdevc-module-format'] as String),
      errors,
      _generator.generator as ddc.IncrementalCompiler,
      kernel2jsCompiler,
      component,
    );

    final String? procedure = await expressionCompiler.compileExpressionToJs(
        libraryUri, scriptUri, line, column, jsFrameValues, expression);

    final String result = errors.isNotEmpty ? errors[0] : procedure!;

    // TODO(annagrin): kernelBinaryFilename is too specific
    // rename to _outputFileName?
    await new File(_kernelBinaryFilename).writeAsString(result);

    _processedOptions.ticker.logMs('Compiled expression to JavaScript');

    _outputStream
        .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');

    // TODO(annagrin): do we need to add asserts/error reporting if
    // initial compilation didn't happen and _kernelBinaryFilename
    // is different from below?
    if (procedure != null) {
      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    }
  }

  @override
  void reportError(String msg) {
    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    _outputStream.writeln(msg);
    _outputStream.writeln(boundaryKey);
  }

  void writePackagesToSinkAndTrimComponent(
      Component deltaProgram, Sink<List<int>> ioSink) {
    List<Library> packageLibraries = <Library>[];
    List<Library> libraries = <Library>[];
    deltaProgram.computeCanonicalNames();

    for (Library lib in deltaProgram.libraries) {
      Uri uri = lib.importUri;
      if (uri.isScheme("package")) {
        packageLibraries.add(lib);
      } else {
        libraries.add(lib);
      }
    }
    deltaProgram.libraries
      ..clear()
      ..addAll(libraries);

    Map<String, List<Library>> newPackages = <String, List<Library>>{};
    Set<List<int>> alreadyAdded = <List<int>>{};

    void addDataAndDependentData(List<int> data, Uri uri) {
      if (alreadyAdded.add(data)) {
        ioSink.add(data);
        // Now also add all dependencies.
        for (Uri dep in cachedPackageDependencies[uri]!) {
          addDataAndDependentData(cachedPackageLibraries[dep]!, dep);
        }
      }
    }

    for (Library lib in packageLibraries) {
      List<int>? data = cachedPackageLibraries[lib.fileUri];
      if (data != null) {
        addDataAndDependentData(data, lib.fileUri);
      } else {
        String package = lib.importUri.pathSegments.first;
        (newPackages[package] ??= <Library>[]).add(lib);
      }
    }

    for (String package in newPackages.keys) {
      List<Library> libraries = newPackages[package]!;
      Component singleLibrary = new Component(
          libraries: libraries,
          uriToSource: deltaProgram.uriToSource,
          nameRoot: deltaProgram.root);
      singleLibrary.setMainMethodAndMode(null, false, deltaProgram.mode);
      ByteSink byteSink = new ByteSink();
      final BinaryPrinter printer = printerFactory.newBinaryPrinter(byteSink);
      printer.writeComponentFile(singleLibrary);

      // Record things this package blob dependent on.
      Set<Uri> libraryUris = <Uri>{};
      for (Library lib in libraries) {
        libraryUris.add(lib.fileUri);
      }
      Set<Uri> deps = <Uri>{};
      for (Library lib in libraries) {
        for (LibraryDependency dep in lib.dependencies) {
          Library dependencyLibrary = dep.importedLibraryReference.asLibrary;
          if (!dependencyLibrary.importUri.isScheme("package")) continue;
          Uri dependencyLibraryUri =
              dep.importedLibraryReference.asLibrary.fileUri;
          if (libraryUris.contains(dependencyLibraryUri)) continue;
          deps.add(dependencyLibraryUri);
        }
      }

      List<int> data = byteSink.builder.takeBytes();
      for (Library lib in libraries) {
        cachedPackageLibraries[lib.fileUri] = data;
        cachedPackageDependencies[lib.fileUri] = new List<Uri>.of(deps);
      }
      ioSink.add(data);
    }
  }

  @override
  void acceptLastDelta() {
    _generator.accept();
  }

  @override
  Future<void> rejectLastDelta() async {
    final String boundaryKey = generateV4UUID();
    _outputStream.writeln('result $boundaryKey');
    await _generator.reject();
    _outputStream.writeln(boundaryKey);
  }

  @override
  void invalidate(Uri uri) {
    _generator.invalidate(uri);
  }

  @override
  void resetIncrementalCompiler() {
    _generator.resetDeltaState();
    _kernelBinaryFilename = _kernelBinaryFilenameFull;
  }
}
