// @dart = 2.9

import 'dart:async';
import 'dart:io' hide FileSystemEntity;

import 'package:args/args.dart';
import 'package:dev_compiler/dev_compiler.dart'
    show
        DevCompilerTarget,
        ExpressionCompiler,
        parseModuleFormat,
        ProgramCompiler;

import 'package:front_end/src/api_unstable/vm.dart';
import 'package:front_end/widget_cache.dart';
import 'package:kernel/ast.dart' show Library, Procedure, LibraryDependency;
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/kernel.dart'
    show Component, loadComponentSourceFromBytes;
import 'package:kernel/target/targets.dart' show targets, TargetFlags;
import 'package:package_config/package_config.dart';
import 'package:usage/uuid/uuid.dart';

import 'package:vm/incremental_compiler.dart' show IncrementalCompiler;

import 'package:frontend_server/src/javascript_bundle.dart';
import 'package:frontend_server/src/strong_components.dart';

import 'package:frontend_server/frontend_server.dart';
import 'kernel_front_end_proxy.dart';

class FrontendCompilerProxy extends FrontendCompiler {
  StringSink _outputStream;
  BinaryPrinterFactory printerFactory;

  bool _printIncrementalDependencies;

  CompilerOptions _compilerOptions;
  ProcessedOptions _processedOptions;
  FileSystem _fileSystem;
  Uri _mainSource;
  List<Uri> _additionalSources;
  ArgResults _options;

  IncrementalCompiler _generator;
  JavaScriptBundler _bundler;

  WidgetCache _widgetCache;

  String _kernelBinaryFilename;
  String _kernelBinaryFilenameIncremental;
  String _kernelBinaryFilenameFull;
  String _initializeFromDill;
  bool _assumeInitializeFromDillUpToDate;

  Set<Uri> previouslyReportedDependencies = Set<Uri>();

  FrontendCompilerProxy(this._outputStream,
      {BinaryPrinterFactory printerFactory,
      ProgramTransformer transformer,
      bool unsafePackageSerialization,
      bool incrementalSerialization = true,
      bool useDebuggerModuleNames = false,
      bool emitDebugMetadata = false,
      bool emitDebugSymbols = false})
      : super(_outputStream,
            transformer: transformer,
            unsafePackageSerialization: unsafePackageSerialization,
            incrementalSerialization: incrementalSerialization,
            useDebuggerModuleNames: unsafePackageSerialization,
            emitDebugMetadata: emitDebugMetadata,
            emitDebugSymbols: emitDebugSymbols);

  _onDiagnostic(DiagnosticMessage message) {
    // TODO(https://dartbug.com/44867): The frontend server should take a
    // verbosity argument and put that in CompilerOptions and use it here.
    bool printMessage;
    switch (message.severity) {
      case Severity.error:
      case Severity.internalProblem:
        printMessage = true;
        errors.addAll(message.plainTextFormatted);
        break;
      case Severity.warning:
        printMessage = true;
        break;
      case Severity.info:
        printMessage = false;
        break;
      case Severity.context:
      case Severity.ignored:
        throw 'Unexpected severity: ${message.severity}';
    }
    if (printMessage) {
      printDiagnosticMessage(message, _outputStream.writeln);
    }
  }

  void _installDartdevcTarget() {
    targets['dartdevc'] = (TargetFlags flags) => DevCompilerTarget(flags);
  }

  @override
  Future<bool> compile(
    String entryPoint,
    ArgResults options, {
    IncrementalCompiler generator,
  }) async {
    _options = options;
    _fileSystem = createFrontEndFileSystem(
        options['filesystem-scheme'], options['filesystem-root'],
        allowHttp: options['enable-http-uris']);
    _mainSource = resolveInputUri(entryPoint);
    _additionalSources =
        (options['source'] as List<String>).map(resolveInputUri).toList();
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
    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    final Uri sdkRoot = _ensureFolderPath(options['sdk-root']);
    final String platformKernelDill =
        options['platform'] ?? 'platform_strong.dill';
    final String packagesOption = _options['packages'];
    final bool nullSafety = _options['sound-null-safety'];
    final CompilerOptions compilerOptions = CompilerOptions()
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
      ..nnbdMode = (nullSafety == true) ? NnbdMode.Strong : NnbdMode.Weak
      ..onDiagnostic = _onDiagnostic;

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
        print(
            'Error: --split-output-by-packages option cannot be used with --aot');
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

    if (nullSafety == null &&
        compilerOptions.globalFeatures.nonNullable.isEnabled) {
      await autoDetectNullSafetyMode(_mainSource, compilerOptions);
    }

    // Initialize additional supported kernel targets.
    _installDartdevcTarget();
    compilerOptions.target = createFrontEndTarget(
      options['target'],
      trackWidgetCreation: options['track-widget-creation'],
      nullSafety: compilerOptions.nnbdMode == NnbdMode.Strong,
      supportMirrors: options['support-mirrors'] ??
          !(options['aot'] || options['minimal-kernel']),
      compactAsync: options['compact-async'] ?? false /*options['aot']*/,
    );
    if (compilerOptions.target == null) {
      print('Failed to create front-end target ${options['target']}.');
      return false;
    }

    final String importDill = options['import-dill'];
    if (importDill != null) {
      compilerOptions.additionalDills = <Uri>[
        Uri.base.resolveUri(Uri.file(importDill))
      ];
    }

    _compilerOptions = compilerOptions;
    _processedOptions = ProcessedOptions(options: compilerOptions);

    KernelCompilationResults results;
    IncrementalSerializer incrementalSerializer;
    if (options['incremental']) {
      _compilerOptions.environmentDefines =
          _compilerOptions.target.updateEnvironmentDefines(environmentDefines);

      _compilerOptions.omitPlatform = false;
      _generator = generator ?? _createGenerator(Uri.file(_initializeFromDill));
      await invalidateIfInitializingFromDill();
      IncrementalCompilerResult compilerResult =
          await _runWithPrintRedirection(() => _generator.compile());
      Component component = compilerResult.component;
      results = KernelCompilationResults(
          component,
          const {},
          compilerResult.classHierarchy,
          compilerResult.coreTypes,
          component.uriToSource.keys);

      incrementalSerializer = _generator.incrementalSerializer;
      if (options['flutter-widget-cache']) {
        _widgetCache = WidgetCache(component);
      }
    } else {
      if (options['link-platform']) {
        // TODO(aam): Remove linkedDependencies once platform is directly embedded
        // into VM snapshot and http://dartbug.com/30111 is fixed.
        compilerOptions.additionalDills = <Uri>[
          sdkRoot.resolve(platformKernelDill)
        ];
      }
      results = await _runWithPrintRedirection(() => compileToKernelProxy(
          _mainSource, compilerOptions,
          additionalSources: _additionalSources,
          includePlatform: options['link-platform'],
          deleteToStringPackageUris: options['delete-tostring-package-uri'],
          aot: options['aot'],
          useGlobalTypeFlowAnalysis: options['tfa'],
          useRapidTypeAnalysis: options['rta'],
          environmentDefines: environmentDefines,
          enableAsserts: options['enable-asserts'],
          useProtobufTreeShakerV2: options['protobuf-tree-shaker-v2'],
          minimalKernel: options['minimal-kernel'],
          treeShakeWriteOnlyFields: options['tree-shake-write-only-fields'],
          transformer: transformer,
          fromDillFile: options['from-dill']));
    }
    if (results.component != null) {
      //transformer?.transform(results.component);
      if (options['incremental']) {
        transformer?.transform(results.component);
      }

      if (_compilerOptions.target.name == 'dartdevc') {
        await writeJavascriptBundle(results, _kernelBinaryFilename,
            options['filesystem-scheme'], options['dartdevc-module-format']);
      }
      await writeDillFile(results, _kernelBinaryFilename,
          filterExternal: importDill != null || options['minimal-kernel'],
          incrementalSerializer: incrementalSerializer);

      _outputStream.writeln(boundaryKey);
      await _outputDependenciesDelta(results.compiledSources);
      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      final String depfile = options['depfile'];
      if (depfile != null) {
        await writeDepfile(compilerOptions.fileSystem, results.compiledSources,
            _kernelBinaryFilename, depfile);
      }

      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else {
      _outputStream.writeln(boundaryKey);
    }
    results = null; // Fix leak: Probably variation of http://dartbug.com/36983.
    return errors.isEmpty;
  }

  void _outputDependenciesDelta(Iterable<Uri> compiledSources) async {
    if (!_printIncrementalDependencies) {
      return;
    }
    Set<Uri> uris = Set<Uri>();
    for (Uri uri in compiledSources) {
      // Skip empty or corelib dependencies.
      if (uri == null || uri.isScheme('org-dartlang-sdk')) continue;
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

  /// Write a JavaScript bundle containg the provided component.
  Future<void> writeJavascriptBundle(KernelCompilationResults results,
      String filename, String fileSystemScheme, String moduleFormat) async {
    var packageConfig = await loadPackageConfigUri(
        _compilerOptions.packagesFileUri ?? File('.packages').absolute.uri);
    var soundNullSafety = _compilerOptions.nnbdMode == NnbdMode.Strong;
    final Component component = results.component;
    // Compute strongly connected components.
    final strongComponents = StrongComponents(component,
        results.loadedLibraries, _mainSource, _compilerOptions.fileSystem);
    await strongComponents.computeModules();

    // Create JavaScript bundler.
    final File sourceFile = File('$filename.sources');
    final File manifestFile = File('$filename.json');
    final File sourceMapsFile = File('$filename.map');
    final File metadataFile = File('$filename.metadata');
    final File symbolsFile = File('$filename.symbols');
    if (!sourceFile.parent.existsSync()) {
      sourceFile.parent.createSync(recursive: true);
    }
    _bundler = JavaScriptBundler(
        component, strongComponents, fileSystemScheme, packageConfig,
        useDebuggerModuleNames: useDebuggerModuleNames,
        emitDebugMetadata: emitDebugMetadata,
        emitDebugSymbols: emitDebugSymbols,
        moduleFormat: moduleFormat,
        soundNullSafety: soundNullSafety);
    final sourceFileSink = sourceFile.openWrite();
    final manifestFileSink = manifestFile.openWrite();
    final sourceMapsFileSink = sourceMapsFile.openWrite();
    final metadataFileSink =
        emitDebugMetadata ? metadataFile.openWrite() : null;
    final symbolsFileSink = emitDebugSymbols ? symbolsFile.openWrite() : null;
    final kernel2JsCompilers = await _bundler.compile(
        results.classHierarchy,
        results.coreTypes,
        results.loadedLibraries,
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

  writeDillFile(KernelCompilationResults results, String filename,
      {bool filterExternal: false,
      IncrementalSerializer incrementalSerializer}) async {
    final Component component = results.component;
    final IOSink sink = File(filename).openWrite();
    final Set<Library> loadedLibraries = results.loadedLibraries;
    final BinaryPrinter printer = filterExternal
        ? BinaryPrinter(sink,
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
    await sink.close();

    if (_options['split-output-by-packages']) {
      await writeOutputSplitByPackages(
          _mainSource, _compilerOptions, results, filename);
    }

    final String manifestFilename = _options['far-manifest'];
    if (manifestFilename != null) {
      final String output = _options['output-dill'];
      final String dataDir = _options.options.contains('component-name')
          ? _options['component-name']
          : _options['data-dir'];
      await createFarManifest(output, dataDir, manifestFilename);
    }
  }

  Future<Null> invalidateIfInitializingFromDill() async {
    if (_assumeInitializeFromDillUpToDate) return null;
    if (_kernelBinaryFilename != _kernelBinaryFilenameFull) return null;
    // If the generator is initialized, it's not going to initialize from dill
    // again anyway, so there's no reason to spend time invalidating what should
    // be invalidated by the normal approach anyway.
    if (_generator.initialized) return null;

    final File f = File(_initializeFromDill);
    if (!f.existsSync()) return null;

    Component component;
    try {
      component = loadComponentSourceFromBytes(f.readAsBytesSync());
    } catch (e) {
      // If we cannot load the dill file we shouldn't initialize from it.
      _generator = _createGenerator(null);
      return null;
    }

    nextUri:
    for (Uri uri in component.uriToSource.keys) {
      if (uri == null || '$uri' == '') continue nextUri;

      final List<int> oldBytes = component.uriToSource[uri].source;
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
  Future<Null> recompileDelta({String entryPoint}) async {
    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    await invalidateIfInitializingFromDill();
    if (entryPoint != null) {
      _mainSource = resolveInputUri(entryPoint);
    }
    errors.clear();

    IncrementalCompilerResult deltaProgramResult = await _generator
        .compile(entryPoints: [_mainSource, ..._additionalSources]);
    Component deltaProgram = deltaProgramResult.component;
    if (deltaProgram != null && transformer != null) {
      transformer.transform(deltaProgram);
    }

    KernelCompilationResults results = KernelCompilationResults(
        deltaProgram,
        const {},
        deltaProgramResult.classHierarchy,
        deltaProgramResult.coreTypes,
        deltaProgram.uriToSource.keys);

    if (_compilerOptions.target.name == 'dartdevc') {
      await writeJavascriptBundle(results, _kernelBinaryFilename,
          _options['filesystem-scheme'], _options['dartdevc-module-format']);
    } else {
      await writeDillFile(results, _kernelBinaryFilename,
          incrementalSerializer: _generator.incrementalSerializer);
    }
    _updateWidgetCache(deltaProgram);

    _outputStream.writeln(boundaryKey);
    await _outputDependenciesDelta(results.compiledSources);
    _outputStream
        .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
    _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
  }

  @override
  Future<Null> compileExpression(
      String expression,
      List<String> definitions,
      List<String> definitionTypes,
      List<String> typeDefinitions,
      List<String> typeBounds,
      List<String> typeDefaults,
      String libraryUri,
      String klass,
      String method,
      bool isStatic) async {
    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    Procedure procedure = await _generator.compileExpression(
        expression,
        definitions,
        definitionTypes,
        typeDefinitions,
        typeBounds,
        typeDefaults,
        libraryUri,
        klass,
        method,
        isStatic);
    if (procedure != null) {
      Component component = createExpressionEvaluationComponent(procedure);
      final IOSink sink = File(_kernelBinaryFilename).openWrite();
      sink.add(serializeComponent(component));
      await sink.close();
      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else {
      _outputStream.writeln(boundaryKey);
    }
  }

  /// Program compilers per module.
  ///
  /// Produced suring initial compilation of the module to JavaScript,
  /// cached to be used for expression compilation in [compileExpressionToJs].
  final Map<String, ProgramCompiler> cachedProgramCompilers = {};

  @override
  Future<Null> compileExpressionToJs(
      String libraryUri,
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

    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');

    _processedOptions.ticker
        .logMs('Compiling expression to JavaScript in $moduleName');

    final kernel2jsCompiler = cachedProgramCompilers[moduleName];
    IncrementalCompilerResult compilerResult = _generator.lastKnownGoodResult;
    Component component = compilerResult.component;
    component.computeCanonicalNames();

    _processedOptions.ticker.logMs('Computed component');

    final expressionCompiler = new ExpressionCompiler(
      _compilerOptions,
      parseModuleFormat(_options['dartdevc-module-format'] as String),
      errors,
      _generator.generator,
      kernel2jsCompiler,
      component,
    );

    final procedure = await expressionCompiler.compileExpressionToJs(
        libraryUri, line, column, jsFrameValues, expression);

    final result = errors.length > 0 ? errors[0] : procedure;

    // TODO(annagrin): kernelBinaryFilename is too specific
    // rename to _outputFileName?
    await File(_kernelBinaryFilename).writeAsString(result);

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
    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    _outputStream.writeln(msg);
    _outputStream.writeln(boundaryKey);
  }

  /// Map of already serialized dill data. All uris in a serialized component
  /// maps to the same blob of data. Used by
  /// [writePackagesToSinkAndTrimComponent].
  Map<Uri, List<int>> cachedPackageLibraries = Map<Uri, List<int>>();

  /// Map of dependencies for already serialized dill data.
  /// E.g. if blob1 dependents on blob2, but only using a single file from blob1
  /// that does not dependent on blob2, blob2 would not be included leaving the
  /// dill file in a weird state that could cause the VM to crash if asked to
  /// forcefully compile everything. Used by
  /// [writePackagesToSinkAndTrimComponent].
  Map<Uri, List<Uri>> cachedPackageDependencies = Map<Uri, List<Uri>>();

  writePackagesToSinkAndTrimComponent(
      Component deltaProgram, Sink<List<int>> ioSink) {
    if (deltaProgram == null) return;

    List<Library> packageLibraries = <Library>[];
    List<Library> libraries = <Library>[];
    deltaProgram.computeCanonicalNames();

    for (var lib in deltaProgram.libraries) {
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

    Map<String, List<Library>> newPackages = Map<String, List<Library>>();
    Set<List<int>> alreadyAdded = Set<List<int>>();

    addDataAndDependentData(List<int> data, Uri uri) {
      if (alreadyAdded.add(data)) {
        ioSink.add(data);
        // Now also add all dependencies.
        for (Uri dep in cachedPackageDependencies[uri]) {
          addDataAndDependentData(cachedPackageLibraries[dep], dep);
        }
      }
    }

    for (Library lib in packageLibraries) {
      List<int> data = cachedPackageLibraries[lib.fileUri];
      if (data != null) {
        addDataAndDependentData(data, lib.fileUri);
      } else {
        String package = lib.importUri.pathSegments.first;
        newPackages[package] ??= <Library>[];
        newPackages[package].add(lib);
      }
    }

    for (String package in newPackages.keys) {
      List<Library> libraries = newPackages[package];
      Component singleLibrary = Component(
          libraries: libraries,
          uriToSource: deltaProgram.uriToSource,
          nameRoot: deltaProgram.root);
      singleLibrary.setMainMethodAndMode(null, false, deltaProgram.mode);
      ByteSink byteSink = ByteSink();
      final BinaryPrinter printer = printerFactory.newBinaryPrinter(byteSink);
      printer.writeComponentFile(singleLibrary);

      // Record things this package blob dependent on.
      Set<Uri> libraryUris = Set<Uri>();
      for (Library lib in libraries) {
        libraryUris.add(lib.fileUri);
      }
      Set<Uri> deps = Set<Uri>();
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
        cachedPackageDependencies[lib.fileUri] = List<Uri>.from(deps);
      }
      ioSink.add(data);
    }
  }

  @override
  void acceptLastDelta() {
    _generator.accept();
    _widgetCache?.reset();
  }

  @override
  Future<void> rejectLastDelta() async {
    final String boundaryKey = Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    await _generator.reject();
    _outputStream.writeln(boundaryKey);
  }

  @override
  void invalidate(Uri uri) {
    _generator.invalidate(uri);
    _widgetCache?.invalidate(uri);
  }

  @override
  void resetIncrementalCompiler() {
    _generator.resetDeltaState();
    _widgetCache?.reset();
    _kernelBinaryFilename = _kernelBinaryFilenameFull;
  }

  IncrementalCompiler _createGenerator(Uri initializeFromDillUri) {
    return IncrementalCompiler(
        _compilerOptions, [_mainSource, ..._additionalSources],
        initializeFromDillUri: initializeFromDillUri,
        incrementalSerialization: incrementalSerialization);
  }

  /// If the flutter widget cache is enabled, check if a single class was modified.
  ///
  /// The resulting class name is written as a String to
  /// `_kernelBinaryFilename`.widget_cache, or else the file is deleted
  /// if it exists.
  ///
  /// Should not run if a full component is requested.
  void _updateWidgetCache(Component partialComponent) {
    if (_widgetCache == null || _generator.fullComponent) {
      return;
    }
    final String singleModifiedClassName =
        _widgetCache.checkSingleWidgetTypeModified(
      _generator.lastKnownGoodResult?.component,
      partialComponent,
      _generator.lastKnownGoodResult?.classHierarchy,
    );
    final File outputFile = File('$_kernelBinaryFilename.widget_cache');
    if (singleModifiedClassName != null) {
      outputFile.writeAsStringSync(singleModifiedClassName);
    } else if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }

  Uri _ensureFolderPath(String path) {
    String uriPath = Uri.file(path).toString();
    if (!uriPath.endsWith('/')) {
      uriPath = '$uriPath/';
    }
    return Uri.base.resolve(uriPath);
  }

  /// Runs the given function [f] in a Zone that redirects all prints into
  /// [_outputStream].
  Future<T> _runWithPrintRedirection<T>(Future<T> f()) {
    return runZoned(() => Future<T>(f),
        zoneSpecification: ZoneSpecification(
            print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
                _outputStream.writeln(line)));
  }
}
