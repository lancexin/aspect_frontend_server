// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'dart:io';

import 'package:frontend_server/frontend_server.dart' as frontend;

import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';
import 'utils.dart';

class MethodItem {
  final String importUri;
  final String clsName;
  final String methodName;
  final bool isStatic;
  final bool isRegex;
  final Member aopMember;
  final bool isGetter;

  MethodItem(
      {required this.importUri,
      required this.clsName,
      required this.methodName,
      required this.isStatic,
      required this.aopMember,
      required this.isGetter,
      required this.isRegex});

  @override
  String toString() {
    return 'AopItem{importUri: $importUri, clsName: $clsName, methodName: $methodName, isStatic: $isStatic, isGetter: $isGetter, isRegex: $isRegex, aopMember: $aopMember';
  }
}

class MethodAopTransformer implements frontend.ProgramTransformer {
  final List<MethodItem> _aopItemList = <MethodItem>[];

  static Set<Procedure> manipulatedProcedureSet = {};

  @override
  void transform(Component component) {
    stdout.writeln("[MethodAopTransformer] start transform");
    _aopItemList.clear();
    manipulatedProcedureSet.clear();
    _collectAopItem(component);

    if (_aopItemList.isNotEmpty) {
      stdout.writeln("[MethodAopTransformer] start visitChildren");
      component.visitChildren(_MethodExecuteVisitor(_aopItemList));
    } else {
      stdout.writeln("[MethodAopTransformer] skip visitChildren");
    }
  }

  void _collectAopItem(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      stdout.writeln(
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
          stdout.writeln("[MethodAopTransformer] ${cls.name} aspectdEnabled");
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

          if (!(list.length == 4 &&
                  list[0].value is StringConstant &&
                  list[1].value is StringConstant &&
                  list[2].value is StringConstant &&
                  list[3].value is BoolConstant) &&
              !(list.length == 5 &&
                  list[0].value is StringConstant &&
                  list[1].value is StringConstant &&
                  list[2].value is StringConstant &&
                  list[3].value is BoolConstant &&
                  list[4].value is BoolConstant)) {
            continue;
          }

          String importUri = (list[0].value as StringConstant).value;
          String clsName = (list[1].value as StringConstant).value;
          String methodName = (list[2].value as StringConstant).value;
          bool isRegex = (list[3].value as BoolConstant).value;
          bool isGetter = list.length == 5
              ? (list[4].value as BoolConstant?)?.value ?? false
              : false;
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
              isGetter: isGetter,
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

        bool isGetter = invocation1.entries == 5
            ? (invocation1.entries[4].value as BoolLiteral?)?.value ?? false
            : false;

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
            isGetter: isGetter,
            isRegex: isRegex);
      }
    }
    return null;
  }
}

class _MethodExecuteVisitor extends RecursiveVisitor {
  final List<MethodItem> _aopItemList;

  _MethodExecuteVisitor(this._aopItemList);

  @override
  void visitLibrary(Library library) {
    library.visitChildren(this);
  }

  @override
  void visitClass(Class node) {
    String clsName = node.name;

    Library originalLibrary = node.enclosingLibrary;

    if (node.isAnonymousMixin && node.isEliminatedMixin) {
      if (node.implementedTypes.isNotEmpty) {
        originalLibrary =
            node.implementedTypes.first.classNode.enclosingLibrary;
        clsName = node.implementedTypes.first.classNode.name;
      }
      //stdout.writeln(
      //    "[MethodAopTransformer] visitClass isAnonymousMixin ${node.name} ${originalLibrary.importUri.toString()}}");
    }
    bool matches = false;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      MethodItem aopItem = _aopItemList[i];

      if (((aopItem.isRegex && RegExp(aopItem.clsName).hasMatch(clsName)) ||
              (!aopItem.isRegex && clsName == aopItem.clsName)) &&
          originalLibrary.importUri.toString() == aopItem.importUri) {
        matches = true;
        break;
      }
    }

    if (matches) {
      stdout.writeln(
          "[MethodAopTransformer] visitClass match ${originalLibrary.importUri} ${node.name}");
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
      bool classMatched =
          (aopItem.isRegex && RegExp(aopItem.clsName).hasMatch(clsName)) ||
              (!aopItem.isRegex && clsName == aopItem.clsName);
      bool libraryMatched =
          originalLibrary.importUri.toString() == aopItem.importUri;
      if (classMatched && libraryMatched) {
        matches = true;
        break;
      }
    }
    if (matches) {
      stdout.writeln(
          "[MethodAopTransformer] visitExtension extension match ${node.parent.runtimeType.toString()} ${node.name} ${originalLibrary}");
      node.visitChildren(this);
    }
  }

  @override
  void visitProcedure(Procedure node) {
    String procedureName = node.name.text;
    bool needCompareClass = false;
    Class? originalClass = null;
    Library originalLibrary = node.enclosingLibrary;
    if (node.parent is Class) {
      needCompareClass = true;
      originalClass = node.parent as Class;
    }

    String? clsName = null;
    String importUri = originalLibrary.importUri.toString();
    if (needCompareClass) {
      clsName = originalClass?.name;
    }

    if (needCompareClass &&
        originalClass != null &&
        originalClass.isAnonymousMixin &&
        originalClass.isEliminatedMixin) {
      if (originalClass.implementedTypes.isNotEmpty) {
        clsName = originalClass.implementedTypes.first.classNode.name;
        importUri = originalClass
            .implementedTypes.first.classNode.enclosingLibrary.importUri
            .toString();
        //stdout.writeln(
        //    "[MethodAopTransformer] visitProcedure isAnonymousMixin so transform it clasName[${originalClass.name} to $clsName] importUri[${originalLibrary?.importUri.toString()} to $importUri]");
      }
    }

    MethodItem? matchedAopItem = null;
    int aopItemInfoListLen = _aopItemList.length;
    for (int i = 0; i < aopItemInfoListLen && matchedAopItem == null; i++) {
      MethodItem aopItem = _aopItemList[i];

      bool methodMatched = (aopItem.isRegex &&
              RegExp(aopItem.methodName).hasMatch(procedureName)) ||
          (!aopItem.isRegex && procedureName == aopItem.methodName);
      bool libraryMatched = aopItem.importUri == importUri;
      bool getterMatched = aopItem.isGetter == node.isGetter;
      if (libraryMatched && methodMatched && getterMatched) {
        if (needCompareClass) {
          bool classMatched = (aopItem.isRegex &&
                  clsName != null &&
                  RegExp(aopItem.clsName).hasMatch(clsName)) ||
              (!aopItem.isRegex && aopItem.clsName == clsName);
          if (classMatched) {
            matchedAopItem = aopItem;
            break;
          }
        } else {
          matchedAopItem = aopItem;
          break;
        }
      } else {
        //stdout.writeln(
        //    "[MethodAopTransformer] visitProcedure $procedureName not match ${importUri}");
      }
    }
    if (matchedAopItem == null) {
      if ((originalClass?.isAnonymousMixin ?? false) &&
          (originalClass?.isEliminatedMixin ?? false)) {
        //stdout.writeln(
        //    "[MethodAopTransformer] visitProcedure isAnonymousMixin so transform it clasName[${originalClass?.name} to $clsName] importUri[${originalLibrary?.importUri.toString()} to $importUri]");
        //stdout.writeln(
        //    "[MethodAopTransformer] visitProcedure notMatch ${originalLibrary?.importUri.toString()}|${originalClass?.name}|$procedureName");
      }
      return;
    } else {
      stdout.writeln(
          "[MethodAopTransformer] visitProcedure match ${originalLibrary?.importUri.toString()}|${originalClass?.name}|$procedureName");
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
          stdout.writeln(
              "[MethodAopTransformer] visitProcedure error ${node.parent.runtimeType.toString()} ${node.name.text}");
        }
      } else {
        if (node.parent != null) {
          transformInstanceMethodProcedure(
              node.parent?.parent as Library, matchedAopItem, node);
        } else {
          stdout.writeln(
              "[MethodAopTransformer] visitProcedure error node.parent == null ${node.name.text}");
        }
      }
    } catch (error, stack) {
      stdout.writeln(
          "[MethodAopTransformer] visitProcedure ${error.toString()} \n ${stack.toString()}");
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
        stdout.writeln(
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
      stdout.writeln(
          "[MethodAopTransformer] expression is not StaticInvocation so return ");
      return false;
    }
  }

  bool isInjectBlock3(ReturnStatement? block, Procedure injectProcedure,
      Procedure originProcedure) {
    if (block == null) {
      return false;
    }

    Expression? expression = block.expression;

    if (expression is StaticInvocation) {
      if (expression.arguments.positional.length != 5) {
        stdout.writeln(
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
      stdout.writeln(
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
  //       stdout.writeln(
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
  //     stdout.writeln(
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
    Block? bodyStatements;

    if (functionNode.body is Block) {
      bodyStatements = functionNode.body as Block;
    } else if (functionNode.body is ReturnStatement) {
      bodyStatements = Block([functionNode.body!]);
    }
    if (bodyStatements == null) {
      stdout.writeln(
          "[MethodAopTransformer] bodyStatements ${originalProcedure.name.toString()} is ${functionNode.body.runtimeType.toString()} so return");
      return;
    }
    //bodyStatements = getInjectBlock(bodyStatements, originalProcedure);
    //检查当前方法是否已经被注入
    if (isInjectBlock(
        bodyStatements, aopItem.aopMember as Procedure, originalProcedure)) {
      stdout.writeln(
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
      //这里需要适配 release 和 debug 模式
      // if (originalProcedure.isExtensionMember &&
      //     originArguments.positional.isNotEmpty) {
      //   Expression first = originArguments.positional.first;
      //   stdout.writeln(
      //       "isExtensionMember ${first.runtimeType} ${first.toStringInternal()}");
      //   redirectArguments.positional.add(originArguments.positional.first);
      //   //originArguments.positional.removeAt(0);
      // } else {

      // }
      redirectArguments.positional.add(NullLiteral());
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

    //如果返回类型是 Future 或者FutureOrType,强制转换成 dynamic
    if (shouldReturn && functionNode.returnType is FutureOrType ||
        (functionNode.returnType is InterfaceType &&
            (functionNode.returnType as InterfaceType)
                    .classNode
                    .enclosingLibrary
                    .importUri
                    .toString() ==
                'dart:async' &&
            (functionNode.returnType as InterfaceType).classNode.name ==
                'Future')) {
      stdout.writeln(
          "${originalProcedure.name.toString()} return type is FutureOrType ${functionNode.returnType.toStringInternal()}");
      //这里还有第二种做法，强制返回 Future<dynamic>
      functionNode.returnType = DynamicType();
      functionNode.emittedValueType = DynamicType();
    }
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
        dartAsyncMarker: functionNode.dartAsyncMarker,
        emittedValueType: functionNode.emittedValueType);
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
        "[AspectAopTransformer] inject ${originalProcedure.name.toString()}${originalProcedure.isGetter ? ":get" : ""}  success ");
  }
}
