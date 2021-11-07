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
        isFieldFormal: node.isFieldFormal,
        isCovariant: node.isCovariant,
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
          var list =
              ((instanceConstant.fieldValues.values.last as InstanceConstant)
                      .fieldValues
                      .values
                      .first as ListConstant)
                  .entries;
          if (list.length != 8) {
            continue;
          }

          String importUri = (list[1] as StringConstant).value;
          String clsName = (list[3] as StringConstant).value;
          String methodName = (list[5] as StringConstant).value;
          bool isRegex = (list[7] as BoolConstant).value;
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
}
