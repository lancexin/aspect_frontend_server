// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'package:frontend_server/frontend_server.dart' as frontend;
import 'package:vm/target/flutter.dart';

import 'package:kernel/ast.dart';
import 'utils.dart';

class MethodItem {
  final String importUri;
  final String clsName;
  final String methodName;
  final bool isStatic;
  final bool isRegex;
  final Member aopMember;

  MethodItem(
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

class MethodAopTransformer implements frontend.ProgramTransformer {
  final List<MethodItem> _aopItemList = <MethodItem>[];

  static Set<Procedure> manipulatedProcedureSet = {};

  @override
  void transform(Component component) {
    print("[MethodAopTransformer] start transform");
    _aopItemList.clear();
    manipulatedProcedureSet.clear();
    _collectAopItem(component);

    if (_aopItemList.isNotEmpty) {
      print("[MethodAopTransformer] start visitChildren");
      component.visitChildren(_MethodExecuteVisitor(_aopItemList));
    } else {
      print("[MethodAopTransformer] skip visitChildren");
    }
  }

  void _collectAopItem(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      print(
          "[MethodAopTransformer] _collectAopItem  libraries.isEmpty so return");
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
          print("[MethodAopTransformer] ${cls.name} aspectdEnabled");
          cls.members.forEach((member) {
            final MethodItem? aopItem = processMethodItemMember(member);
            if (aopItem != null) {
              _aopItemList.add(aopItem);
            }
          });
        }
      });
    }
  }

  static MethodItem? processMethodItemMember(Member member) {
    //注入的方法强制是静态方法
    for (Expression annotation in member.annotations) {
      //Release mode
      if (annotation is ConstantExpression) {
        final ConstantExpression constantExpression = annotation;
        final Constant constant = constantExpression.constant;
        if (constant is InstanceConstant) {
          final InstanceConstant instanceConstant = constant;
          final Class instanceClass = instanceConstant.classNode;
          final String? instanceImportUri =
              (instanceClass.parent as Library?)?.importUri.toString();
          bool aopMethod =
              AopUtils.isPragma(instanceClass.name, instanceImportUri);
          if (!aopMethod) {
            continue;
          }
          String annotationName =
              (instanceConstant.fieldValues.values.first as StringConstant)
                  .value;
          if (annotationName != AopUtils.kImportUriAopInjectName) {
            continue;
          }
          List<ConstantMapEntry> list =
              (instanceConstant.fieldValues.values.last as MapConstant).entries;

          if (list.length != 4) {
            continue;
          }

          if (!(list[0].value is StringConstant &&
              list[1].value is StringConstant &&
              list[2].value is StringConstant &&
              list[3].value is BoolConstant)) {
            continue;
          }

          String importUri = (list[0].value as StringConstant).value;
          String clsName = (list[1].value as StringConstant).value;
          String methodName = (list[2].value as StringConstant).value;
          bool isRegex = (list[3].value as BoolConstant).value;
          bool isStatic = false;
          if (methodName
              .startsWith(AopUtils.kAopAnnotationInstanceMethodPrefix)) {
            methodName = methodName
                .substring(AopUtils.kAopAnnotationInstanceMethodPrefix.length);
          } else if (methodName
              .startsWith(AopUtils.kAopAnnotationStaticMethodPrefix)) {
            methodName = methodName
                .substring(AopUtils.kAopAnnotationStaticMethodPrefix.length);
            isStatic = true;
          } else {
            continue;
          }
          return MethodItem(
              importUri: importUri,
              clsName: clsName,
              methodName: methodName,
              isStatic: isStatic,
              aopMember: member,
              isRegex: isRegex);
        }
      } else if (annotation is ConstructorInvocation) {
        final ConstructorInvocation constructorInvocation = annotation;
        final Class? cls =
            constructorInvocation.targetReference.node?.parent as Class?;
        final Library? clsParentLib = cls?.parent as Library?;
        bool aopMethod =
            AopUtils.isPragma(cls!.name, clsParentLib?.importUri.toString());
        if (!aopMethod) {
          continue;
        }
        final StringLiteral stringName =
            constructorInvocation.arguments.positional[0] as StringLiteral;
        final String name = stringName.value;
        if (name != AopUtils.kImportUriAopInjectName) {
          aopMethod = false;
          continue;
        }

        final MapLiteral invocation1 =
            constructorInvocation.arguments.positional[1] as MapLiteral;

        final StringLiteral stringLiteral0 =
            invocation1.entries[0].value as StringLiteral;
        final String importUri = stringLiteral0.value;
        final StringLiteral stringLiteral1 =
            invocation1.entries[1].value as StringLiteral;
        final String clsName = stringLiteral1.value;
        final StringLiteral stringLiteral2 =
            invocation1.entries[2].value as StringLiteral;
        String methodName = stringLiteral2.value;
        bool isRegex = false;

        final BoolLiteral boolLiteral =
            invocation1.entries[3].value as BoolLiteral;
        isRegex = boolLiteral.value;

        bool isStatic = false;
        if (methodName
            .startsWith(AopUtils.kAopAnnotationInstanceMethodPrefix)) {
          methodName = methodName
              .substring(AopUtils.kAopAnnotationInstanceMethodPrefix.length);
        } else if (methodName
            .startsWith(AopUtils.kAopAnnotationStaticMethodPrefix)) {
          methodName = methodName
              .substring(AopUtils.kAopAnnotationStaticMethodPrefix.length);
          isStatic = true;
        }
        return MethodItem(
            importUri: importUri,
            clsName: clsName,
            methodName: methodName,
            isStatic: isStatic,
            aopMember: member,
            isRegex: isRegex);
      }
    }
    return null;
  }
}

class _MethodExecuteVisitor extends RecursiveVisitor<void> {
  final List<MethodItem> _aopItemList;

  _MethodExecuteVisitor(this._aopItemList);

  @override
  void visitLibrary(Library library) {
    String importUri = library.importUri.toString();

    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      MethodItem aopItem = _aopItemList[i];
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
  void visitClass(Class node) {
    String clsName = node.name;

    Library originalLibrary = node.enclosingLibrary;
    if (node.isAnonymousMixin && node.isEliminatedMixin) {
      print(
          "[MethodAopTransformer] ${node.name} isAnonymousMixin:${originalLibrary.importUri.toString()}}");
    }
    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      MethodItem aopItem = _aopItemList[i];

      if ((aopItem.isRegex && RegExp(aopItem.clsName).hasMatch(clsName)) ||
          (!aopItem.isRegex && clsName == aopItem.clsName) &&
              originalLibrary.importUri.toString() == aopItem.importUri) {
        matches = true;
        break;
      }
    }

    if (matches) {
      print(
          "[MethodAopTransformer] visitClass match ${node.parent.runtimeType.toString()} ${node.name}");
      node.visitChildren(this);
    }
  }

  @override
  void visitExtension(Extension node) {
    String clsName = node.name;
    Library originalLibrary = node.parent as Library;
    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      MethodItem aopItem = _aopItemList[i];
      if ((aopItem.isRegex && RegExp(aopItem.clsName).hasMatch(clsName)) ||
          (!aopItem.isRegex && clsName == aopItem.clsName) &&
              originalLibrary.importUri.toString() == aopItem.importUri) {
        matches = true;
        break;
      }
    }
    if (matches) {
      print(
          "[MethodAopTransformer] visitExtension extension match ${node.parent.runtimeType.toString()} ${node.name}");
      node.visitChildren(this);
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
      originalLibrary = originalClass.enclosingLibrary;
    }

    String? clsName = null;
    String? importUri = null;
    if (needCompareClass) {
      clsName = originalClass?.name;
      importUri = originalLibrary?.importUri.toString();
    }

    MethodItem? matchedAopItem = null;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && matchedAopItem == null; i++) {
      MethodItem aopItem = _aopItemList[i];
      if ((aopItem.isRegex &&
              RegExp(aopItem.methodName).hasMatch(procedureName)) ||
          (!aopItem.isRegex && procedureName == aopItem.methodName)) {
        if (needCompareClass) {
          if (((aopItem.isRegex &&
                      clsName != null &&
                      RegExp(aopItem.clsName).hasMatch(clsName)) ||
                  (!aopItem.isRegex && aopItem.clsName == clsName)) &&
              aopItem.importUri == importUri) {
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

    try {
      if (node.isStatic) {
        if (node.parent is Library) {
          transformInstanceMethodProcedure(
              node.parent as Library, matchedAopItem, node);
        } else if (node.parent is Class && node.parent?.parent is Library) {
          transformInstanceMethodProcedure(
              node.parent?.parent as Library, matchedAopItem, node);
        } else {
          print(
              "[MethodAopTransformer] error ${node.parent.runtimeType.toString()} ${node.name.text}");
        }
      } else {
        if (node.parent != null) {
          transformInstanceMethodProcedure(
              node.parent?.parent as Library, matchedAopItem, node);
        } else {
          print(
              "[MethodAopTransformer] error node.parent == null ${node.name.text}");
        }
      }
    } catch (error, stack) {
      print(
          "[MethodAopTransformer] ${error.toString()} \n ${stack.toString()}");
    }
  }

  bool isInjectBlock(
      Block? block, Procedure injectProcedure, Procedure originProcedure) {
    if (block == null) {
      return false;
    }
    if (block.statements.length != 1) {
      return false;
    }
    Expression? expression;
    if (block.statements.first is ReturnStatement) {
      expression = (block.statements.first as ReturnStatement).expression;
    } else if (block.statements.first is ExpressionStatement) {
      expression = (block.statements.first as ExpressionStatement).expression;
    } else {
      return false;
    }

    if (expression is StaticInvocation) {
      if (expression.arguments.positional.length != 5) {
        print(
            "[MethodAopTransformer] arguments is not 5 so return ${expression.arguments.positional.length}");
        return false;
      }
      if (expression.arguments.positional[1] is StringLiteral &&
          expression.arguments.positional[2] is ListLiteral &&
          expression.arguments.positional[3] is MapLiteral &&
          expression.arguments.positional[4] is FunctionExpression) {
        if ((expression.arguments.positional[1] as StringLiteral).value ==
            originProcedure.name.text) {
          return true;
        }
        return false;
      }
      return false;
    } else {
      print(
          "[MethodAopTransformer] expression is not StaticInvocation so return ");
      return false;
    }
  }

  // Block? getInjectBlock(Block? block, Procedure originalProcedure) {
  //   if (block == null) {
  //     return block;
  //   }
  //   if (block.statements.length != 1) {
  //     return block;
  //   }
  //   Expression? expression;
  //   if (block.statements.first is ReturnStatement) {
  //     expression = (block.statements.first as ReturnStatement).expression;
  //   } else if (block.statements.first is ExpressionStatement) {
  //     expression = (block.statements.first as ExpressionStatement).expression;
  //   } else {
  //     return block;
  //   }

  //   if (expression is StaticInvocation) {
  //     if (expression.arguments.positional.length != 5) {
  //       print(
  //           "[MethodAopTransformer] arguments is not 5 so return ${expression.arguments.positional.length}");
  //       return block;
  //     }
  //     if (expression.arguments.positional[1] is StringLiteral &&
  //         expression.arguments.positional[2] is ListLiteral &&
  //         expression.arguments.positional[3] is MapLiteral &&
  //         expression.arguments.positional[4] is FunctionExpression) {
  //       if ((expression.arguments.positional[1] as StringLiteral).value ==
  //           originalProcedure.name.text) {
  //         block = (expression.arguments.positional[4] as FunctionExpression)
  //             .function
  //             .body as Block?;
  //         block = getInjectBlock(block, originalProcedure);
  //       }
  //       return block;
  //     }
  //     return block;
  //   } else {
  //     print(
  //         "[MethodAopTransformer] expression is not StaticInvocation so return ");
  //     return block;
  //   }
  // }

  void transformInstanceMethodProcedure(Library? originalLibrary,
      MethodItem aopItem, Procedure originalProcedure) {
    if (MethodAopTransformer.manipulatedProcedureSet
        .contains(originalProcedure)) {
      //如果已经处理完过，就直接返回
      return;
    }
    MethodAopTransformer.manipulatedProcedureSet.add(originalProcedure);
    //FunctionNode 中定义了方法的参数和、body、返回值类型等
    final FunctionNode functionNode = originalProcedure.function;

    //当前方法的处理逻辑
    Block? bodyStatements = functionNode.body as Block?;
    if (bodyStatements == null) {
      print(
          "[MethodAopTransformer] bodyStatements ${originalProcedure.name.toString()} is null so return");
      return;
    }
    //bodyStatements = getInjectBlock(bodyStatements, originalProcedure);
    //检查当前方法是否已经被注入
    if (isInjectBlock(
        bodyStatements, aopItem.aopMember as Procedure, originalProcedure)) {
      print(
          "[MethodAopTransformer] isInjectBlock1 ${originalProcedure.name.toString()} so return");
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
        "[AspectAopTransformer] inject ${originalProcedure.name.toString()} success ");
  }
}
