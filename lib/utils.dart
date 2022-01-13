import 'package:kernel/ast.dart';

import 'transformer.dart';

class AopUtils {
  static final String kImportUriAopAspect = 'dart:core';
  static final String kImportUriAopAspectName = 'aopd:aspect';
  static final String kImportUriAopInjectName = 'aopd:inject';

  static final String kAopAnnotationClassAspect = 'pragma';

  static final String kAopAnnotationInstanceMethodPrefix = '-';
  static final String kAopAnnotationStaticMethodPrefix = '+';

  static Set<Procedure> manipulatedProcedureSet = {};

  static bool isPragma(String name, String? importUri) {
    if (name == kAopAnnotationClassAspect && importUri == kImportUriAopAspect) {
      return true;
    }
    return false;
  }

  //Generic Operation
  static void insertLibraryDependency(Library library, Library? dependLibrary) {
    for (LibraryDependency dependency in library.dependencies) {
      if (dependency.importedLibraryReference.node == dependLibrary) {
        return;
      }
    }
    library.dependencies.add(LibraryDependency.import(dependLibrary!));
  }

  static Block createProcedureBodyWithExpression(
      Expression? expression, bool shouldReturn) {
    final Block bodyStatements = Block(<Statement>[]);
    if (shouldReturn) {
      bodyStatements.addStatement(ReturnStatement(expression));
    } else {
      bodyStatements.addStatement(ExpressionStatement(expression!));
    }
    return bodyStatements;
  }

  static dynamic deepCopyASTNode(dynamic node,
      {bool isReturnType = false, bool ignoreGenerics = false}) {
    if (node is TypeParameter) {
      if (ignoreGenerics)
        return TypeParameter(node.name, node.bound, node.defaultType);
    }
    if (node is VariableDeclaration) {
      return VariableDeclaration(
        node.name,
        initializer: node.initializer,
        type: deepCopyASTNode(node.type),
        flags: node.flags,
        isFinal: node.isFinal,
        isConst: node.isConst,
        isLate: node.isLate,
        isRequired: node.isRequired,
        isInitializingFormal: node.isInitializingFormal,
        isCovariantByDeclaration: node.isCovariantByDeclaration,
        isLowered: node.isLowered,
      );
    }
    if (node is TypeParameterType) {
      if (isReturnType || ignoreGenerics) {
        return const DynamicType();
      }
      return TypeParameterType(deepCopyASTNode(node.parameter),
          node.nullability, deepCopyASTNode(node.promotedBound));
    }
    if (node is FunctionType) {
      return FunctionType(
          deepCopyASTNodes(node.positionalParameters),
          deepCopyASTNode(node.returnType, isReturnType: true),
          Nullability.legacy,
          namedParameters: deepCopyASTNodes(node.namedParameters),
          typeParameters: deepCopyASTNodes(node.typeParameters),
          requiredParameterCount: node.requiredParameterCount,
          typedefType: deepCopyASTNode(node.typedefType,
              ignoreGenerics: ignoreGenerics));
    }
    if (node is TypedefType) {
      return TypedefType(node.typedefNode, Nullability.legacy,
          deepCopyASTNodes(node.typeArguments, ignoreGeneric: ignoreGenerics));
    }
    return node;
  }

  static List<T> deepCopyASTNodes<T>(List<T> nodes,
      {bool ignoreGeneric = false}) {
    final List<T> newNodes = <T>[];
    for (T node in nodes) {
      final dynamic newNode =
          deepCopyASTNode(node, ignoreGenerics: ignoreGeneric);
      if (newNode != null) {
        newNodes.add(newNode);
      }
    }
    return newNodes;
  }

  static Arguments argumentsFromFunctionNode(FunctionNode functionNode) {
    final List<Expression> positional = <Expression>[];
    final List<NamedExpression> named = <NamedExpression>[];
    for (VariableDeclaration variableDeclaration
        in functionNode.positionalParameters) {
      positional.add(VariableGet(variableDeclaration));
    }
    for (VariableDeclaration variableDeclaration
        in functionNode.namedParameters) {
      named.add(NamedExpression(
          variableDeclaration.name!, VariableGet(variableDeclaration)));
    }
    return Arguments(positional, named: named);
  }

  static bool isClassEnableAspect(Class cls) {
    bool enabled = false;
    for (Expression annotation in cls.annotations) {
      //Release mode
      if (annotation is ConstantExpression) {
        final ConstantExpression constantExpression = annotation;
        final Constant constant = constantExpression.constant;
        if (constant is InstanceConstant) {
          final InstanceConstant instanceConstant = constant;
          final Class instanceClass = instanceConstant.classNode;
          if (instanceClass.name == AopUtils.kAopAnnotationClassAspect &&
              (instanceClass.parent as Library).importUri.toString() ==
                  AopUtils.kImportUriAopAspect) {
            String name =
                (instanceConstant.fieldValues.values.first as StringConstant)
                    .value
                    .toString();

            if (name == kImportUriAopAspectName) {
              enabled = true;
            }
            if (enabled) {
              break;
            }
          }
        }
      } else if (annotation is ConstructorInvocation) {
        final ConstructorInvocation constructorInvocation = annotation;
        final Class? cls =
            constructorInvocation.targetReference.node?.parent as Class?;
        if (cls == null) {
          continue;
        }

        final Library? library = cls.parent as Library?;
        if (cls.name == AopUtils.kAopAnnotationClassAspect &&
            library!.importUri.toString() == AopUtils.kImportUriAopAspect) {
          if (constructorInvocation.arguments.positional[0] is StringLiteral &&
              (constructorInvocation.arguments.positional[0] as StringLiteral)
                      .value ==
                  kImportUriAopAspectName) {
            enabled = true;
            break;
          } else {
            print("skip ${constructorInvocation.arguments.positional[0]}");
          }
        }
      }
    }
    return enabled;
  }

  static AopItem? processAopMember(Member member) {
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
            print("${instanceClass.name} aopMethod is false so return");
            continue;
          }
          String annotationName =
              (instanceConstant.fieldValues.values.first as StringConstant)
                  .value;
          if (annotationName != kImportUriAopInjectName) {
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
          }
          return AopItem(
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
        if (name != kImportUriAopInjectName) {
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
        return AopItem(
            importUri: importUri,
            clsName: clsName,
            methodName: methodName,
            isStatic: isStatic,
            aopMember: member,
            isRegex: isRegex);
      }
    }
  }
}
