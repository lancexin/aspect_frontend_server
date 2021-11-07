import 'package:frontend_server/frontend_server.dart' as frontend;

import 'package:kernel/ast.dart';
import 'utils.dart';

class AopItem {
  final String importUri;
  final String clsName;
  final String methodName;
  final bool isStatic;
  final bool isRegex;
  final Member aopMember;

  AopItem(
      {required this.importUri,
      required this.clsName,
      required this.methodName,
      required this.isStatic,
      required this.aopMember,
      required this.isRegex});

  @override
  String toString() {
    return 'AopItem{importUri: $importUri, clsName: $clsName, methodName: $methodName, isStatic: $isStatic, isRegex: $isRegex, aopMember: $aopMember';
  }
}

class AspectAopTransformer implements frontend.ProgramTransformer {
  final List<AopItem> _aopItemList = <AopItem>[];

  @override
  void transform(Component component) {
    print("[AspectAopTransformer] start transform");
    _aopItemList.clear();
    _collectAopItem(component);

    if (_aopItemList.isNotEmpty) {
      print("[AspectAopTransformer] start visitChildren");
      component.visitChildren(_AopExecuteVisitor(_aopItemList));
    } else {
      print("[AspectAopTransformer] skip visitChildren");
    }
  }

  void _collectAopItem(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      print(
          "[AspectAopTransformer] _collectAopItem  libraries.isEmpty so return");
      return;
    }
    _resolveAopProcedures(libraries);
  }

  void _resolveAopProcedures(Iterable<Library> libraries) {
    for (Library library in libraries) {
      final List<Class> classes = library.classes;
      classes.forEach((cls) {
        bool aspectdEnabled = AopUtils.isClassEnableAspect(cls);
        if (aspectdEnabled) {
          print("[AspectAopTransformer] ${cls.name} aspectdEnabled");
          cls.members.forEach((member) {
            final AopItem? aopItem = AopUtils.processAopMember(member);
            if (aopItem != null) {
              print(
                  "[AspectAopTransformer] aopItemList add ${aopItem.toString()}");
              _aopItemList.add(aopItem);
            }
          });
        }
      });
    }
  }
}

class _AopExecuteVisitor extends RecursiveVisitor<void> {
  final List<AopItem> _aopItemList;

  _AopExecuteVisitor(this._aopItemList);

  @override
  void visitLibrary(Library library) {
    String importUri = library.importUri.toString();

    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      AopItem aopItem = _aopItemList[i];
      if ((aopItem.isRegex && RegExp(aopItem.importUri).hasMatch(importUri)) ||
          (!aopItem.isRegex && importUri == aopItem.importUri)) {
        matches = true;
        break;
      }
    }
    if (matches) {
      library.visitChildren(this);
    }
  }

  @override
  void visitClass(Class cls) {
    String clsName = cls.name;
    Library originalLibrary = cls.parent as Library;
    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      AopItem aopItem = _aopItemList[i];
      if ((aopItem.isRegex && RegExp(aopItem.clsName).hasMatch(clsName)) ||
          (!aopItem.isRegex && clsName == aopItem.clsName) &&
              originalLibrary.importUri.toString() == aopItem.importUri) {
        matches = true;
        break;
      }
    }
    if (matches) {
      cls.visitChildren(this);
    }
  }

  @override
  void visitProcedure(Procedure node) {
    String procedureName = node.name.text;
    bool needCompareClass = false;
    Class? originalClass = null;
    Library? originalLibrary = null;
    if (node.parent is Class) {
      needCompareClass = true;
      originalClass = node.parent as Class;
      originalLibrary = originalClass.parent as Library;
    }
    String? clsName = null;
    String? importUri = null;
    if (needCompareClass) {
      clsName = originalClass?.name;
      importUri = originalLibrary?.importUri.toString();
    }

    AopItem? matchedAopItem = null;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && matchedAopItem == null; i++) {
      AopItem aopItem = _aopItemList[i];
      if ((aopItem.isRegex &&
              RegExp(aopItem.methodName).hasMatch(procedureName)) ||
          (!aopItem.isRegex && procedureName == aopItem.methodName)) {
        if (needCompareClass) {
          if (aopItem.clsName == clsName && aopItem.importUri == importUri) {
            matchedAopItem = aopItem;
            break;
          }
        } else {
          matchedAopItem = aopItem;
          break;
        }
      }
    }
    if (matchedAopItem == null) {
      return;
    }
    print(
        "[AspectAopTransformer] visitProcedure matched ${matchedAopItem.toString()}");

    try {
      if (node.isStatic) {
        if (node.parent is Library) {
          transformInstanceMethodProcedure(
              node.parent as Library, matchedAopItem, node);
        } else if (node.parent is Class && node.parent?.parent is Library) {
          transformInstanceMethodProcedure(
              node.parent?.parent as Library, matchedAopItem, node);
        }
      } else {
        if (node.parent != null) {
          transformInstanceMethodProcedure(
              node.parent?.parent as Library, matchedAopItem, node);
        }
      }
    } catch (error, stack) {
      print(
          "[AspectAopTransformer] ${error.toString()} \n ${stack.toString()}");
    }
  }

  void transformInstanceMethodProcedure(
      Library? originalLibrary, AopItem aopItem, Procedure originalProcedure) {
    if (AopUtils.manipulatedProcedureSet.contains(originalProcedure)) {
      //如果已经处理完过，就直接返回
      return;
    }
    //FunctionNode 中定义了方法的参数和、body、返回值类型等
    final FunctionNode functionNode = originalProcedure.function;

    //当前方法的处理逻辑
    Block? bodyStatements = functionNode.body as Block?;
    if (bodyStatements == null) {
      return;
    }

    //是否需要返回
    final bool shouldReturn =
        !(originalProcedure.function.returnType is VoidType);
    //将aspect相关的包导入源码文件
    AopUtils.insertLibraryDependency(
        originalLibrary!, aopItem.aopMember.parent!.parent as Library?);
    //获取原方法的参数
    Arguments originArguments =
        AopUtils.argumentsFromFunctionNode(functionNode);

    String functionName = originalProcedure.name.text;
    //创建调用静态方法的参数
    final Arguments redirectArguments = Arguments.empty();

    //target
    if (originalProcedure.isStatic) {
      redirectArguments.positional.add(StringLiteral(functionName));
    } else {
      redirectArguments.positional.add(ThisExpression());
    }

    //functionName
    redirectArguments.positional.add(StringLiteral(functionName));
    //positionalParams
    redirectArguments.positional.add(ListLiteral(originArguments.positional));
    //namedParams
    final List<MapLiteralEntry> entries = <MapLiteralEntry>[];
    for (NamedExpression namedExpression in originArguments.named) {
      //这里用SymbolLiteral貌似无效,退而求其次用StringLiteral
      entries.add(MapLiteralEntry(
          StringLiteral(namedExpression.name), namedExpression.value));
    }
    redirectArguments.positional.add(MapLiteral(entries));
    //proceed
    final FunctionNode newFunctionNode = FunctionNode(bodyStatements,
        typeParameters: AopUtils.deepCopyASTNodes<TypeParameter>(
            functionNode.typeParameters),
        positionalParameters: functionNode.positionalParameters,
        namedParameters: functionNode.namedParameters,
        requiredParameterCount: functionNode.requiredParameterCount,
        returnType: shouldReturn
            ? AopUtils.deepCopyASTNode(functionNode.returnType)
            : const VoidType(),
        asyncMarker: functionNode.asyncMarker,
        dartAsyncMarker: functionNode.dartAsyncMarker);
    FunctionExpression newFunctionExpression =
        FunctionExpression(newFunctionNode);
    redirectArguments.positional.add(newFunctionExpression);
    //创建静态方法调用
    final StaticInvocation callExpression =
        StaticInvocation(aopItem.aopMember as Procedure, redirectArguments);
    Block block = AopUtils.createProcedureBodyWithExpression(
        callExpression, shouldReturn);
    //将原本的处理流程替换成注入后的流程
    functionNode.body = block;
    print(
        "[AspectAopTransformer] inject ${originalProcedure.name.toString()} success");
  }
}
