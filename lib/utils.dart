import 'package:kernel/ast.dart';

class AopUtils {
  static final String kImportUriAopAspect = 'dart:core';
  static final String kImportUriAopAspectName = 'aopd:aspect';
  static final String kImportUriAopInjectName = 'aopd:inject';
  static final String kImportUriAopTryCatchName = 'aopd:trycatch';

  static final String kAopAnnotationClassAspect = 'pragma';

  static final String kAopAnnotationInstanceMethodPrefix = '-';
  static final String kAopAnnotationStaticMethodPrefix = '+';

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
      return TypeParameterType(
        deepCopyASTNode(node.parameter),
        node.nullability,
      );
    }
    if (node is FunctionType) {
      return FunctionType(
        deepCopyASTNodes(node.positionalParameters),
        deepCopyASTNode(node.returnType, isReturnType: true),
        node.declaredNullability,
        namedParameters: deepCopyASTNodes(node.namedParameters),
        typeParameters: deepCopyASTNodes(node.typeParameters),
        requiredParameterCount: node.requiredParameterCount,
        // typedefType: deepCopyASTNode(node.typedefType,
        //     ignoreGenerics: ignoreGenerics)
      );
    }
    if (node is TypedefType) {
      return TypedefType(node.typedefNode, node.declaredNullability,
          deepCopyASTNodes(node.typeArguments, ignoreGeneric: ignoreGenerics));
    }
    if (node is InterfaceType) {
      return InterfaceType(node.classNode, node.declaredNullability,
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

  static Library? findLibrary(TreeNode? node) {
    if (node == null) {
      return null;
    }
    if (node is Library) {
      return node;
    }
    return findLibrary(node.parent);
  }

  static FunctionNode? findFunctionNode(TreeNode? node) {
    if (node == null) {
      return null;
    }
    if (node is FunctionNode) {
      return node;
    }
    return findFunctionNode(node.parent);
  }

  static Procedure? findProcedure(TreeNode? node) {
    if (node == null) {
      return null;
    }
    if (node is Procedure) {
      return node;
    }
    return findProcedure(node.parent);
  }

  static FunctionDeclaration? findFunctionDeclaration(TreeNode? node) {
    if (node == null) {
      return null;
    }
    if (node is FunctionDeclaration) {
      return node;
    }
    return findFunctionDeclaration(node.parent);
  }
}
