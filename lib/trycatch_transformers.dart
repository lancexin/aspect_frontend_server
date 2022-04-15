// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'package:frontend_server/frontend_server.dart' as frontend;
import 'package:vm/target/flutter.dart';

import 'package:kernel/ast.dart';
import 'utils.dart';

class TryCatchItem {
  final Member aopMember;

  TryCatchItem({required this.aopMember});
}

class TryCacthTransformer implements frontend.ProgramTransformer {
  TryCatchItem? tryCatchItem;

  static Set<Catch> manipulateCatchSet = {};

  @override
  void transform(Component component) {
    print("[TryCacthTransformer] start transform");
    tryCatchItem = null;
    manipulateCatchSet.clear();
    _collectAopItem(component);

    if (tryCatchItem != null) {
      print("[TryCacthTransformer] start visitChildren");
      component.visitChildren(_TryCatchVisitor(tryCatchItem));
    } else {
      print("[TryCacthTransformer] skip visitChildren");
    }
  }

  void _collectAopItem(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      print(
          "[AspectAopTransformer] _collectAopItem  libraries.isEmpty so return");
      return;
    }
    _resolveTryCatchProcedures(libraries);
  }

  void _resolveTryCatchProcedures(Iterable<Library> libraries) {
    for (Library library in libraries) {
      final List<Class> classes = library.classes;
      classes.forEach((cls) {
        bool aspectdEnabled = AopUtils.isClassEnableAspect(cls);
        if (aspectdEnabled) {
          cls.members.forEach((member) {
            var item = processTryCatchMember(member);
            if (item != null) {
              tryCatchItem = item;
              print(
                  "[TryCacthTransformer]  _resolveTryCatchProcedures success");
            }
          });
        }
      });
    }
  }

  static TryCatchItem? processTryCatchMember(Member member) {
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
          if (annotationName != AopUtils.kImportUriAopTryCatchName) {
            continue;
          }

          return TryCatchItem(aopMember: member as Procedure);
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

        return TryCatchItem(aopMember: member as Procedure);
      }
    }
    return null;
  }
}

class _TryCatchVisitor extends RecursiveVisitor<void> {
  TryCatchItem? tryCatchItem;

  _TryCatchVisitor(this.tryCatchItem);

  @override
  void defaultNode(Node node) {
    node.visitChildren(this);
  }

  @override
  void defaultTreeNode(TreeNode node) {
    node.visitChildren(this);
  }

  @override
  void defaultExpression(Expression node) {
    node.visitChildren(this);
  }

  @override
  void defaultMember(Member node) {
    node.visitChildren(this);
  }

  @override
  void defaultStatement(Statement node) {
    node.visitChildren(this);
  }

  @override
  void visitCatch(Catch node) {
    transformCatchNode(
        AopUtils.findLibrary(node), AopUtils.findProcedure(node), node);
  }

  void transformCatchNode(
      Library? originalLibrary, Procedure? originalProcedure, Catch node) {
    if (TryCacthTransformer.manipulateCatchSet.contains(node)) {
      print("[TryCacthTransformer] transform skip ");
      return;
    }
    TryCacthTransformer.manipulateCatchSet.add(node);

    var statement = node.body;
    var exception = node.exception;
    var stackTrace = node.stackTrace;

    //当前方法的处理逻辑
    Block? bodyStatements = statement as Block?;
    if (bodyStatements == null) {
      return;
    }
    //检查当前方法是否已经被注入
    if (isInjectBlock(bodyStatements, tryCatchItem!.aopMember)) {
      print("[MethodAopTransformer] isInjectBlock1 so return");
      return;
    }

    //将aspect相关的包导入源码文件
    if (originalLibrary == null) {
      print("[TryCacthTransformer] originalLibrary is null so return ");
      return;
    }

    AopUtils.insertLibraryDependency(
        originalLibrary, tryCatchItem!.aopMember.parent?.parent as Library?);

    //创建调用静态方法的参数
    final Arguments redirectArguments = Arguments.empty();
    if (exception != null) {
      redirectArguments.positional.add(VariableGet(exception));
    } else {
      redirectArguments.positional.add(NullLiteral());
    }

    if (stackTrace != null) {
      redirectArguments.positional.add(VariableGet(stackTrace));
    } else {
      redirectArguments.positional.add(NullLiteral());
    }

    //创建静态方法调用
    final StaticInvocation callExpression = StaticInvocation(
        tryCatchItem!.aopMember as Procedure, redirectArguments);
    final Block block = Block(<Statement>[]);
    bodyStatements.addStatement(ExpressionStatement(callExpression));
    //将原本的处理流程替换成注入后的流程
    print(
        "[TryCacthTransformer] inject success ${originalProcedure?.name.text} ${originalLibrary.name}");
    bodyStatements.statements.forEach((element) {
      block.addStatement(element);
    });

    node.body = block;
  }

  bool isInjectBlock(Block? block, Member injectProcedure) {
    if (block == null) {
      return false;
    }
    if (block.statements.length <= 1) {
      return false;
    }
    Expression? expression;
    if (block.statements.first is ExpressionStatement) {
      expression = (block.statements.first as ExpressionStatement).expression;
    } else {
      return false;
    }

    if (expression is StaticInvocation &&
        expression.precedence == injectProcedure &&
        TryCacthTransformer.processTryCatchMember(injectProcedure) != null) {
      return true;
    } else {
      return false;
    }
  }

  Block? getInjectBlock(Block? block, Procedure originalProcedure) {
    if (block == null) {
      return block;
    }
    if (block.statements.length != 1) {
      return block;
    }
    Expression? expression;
    if (block.statements.first is ReturnStatement) {
      expression = (block.statements.first as ReturnStatement).expression;
    } else if (block.statements.first is ExpressionStatement) {
      expression = (block.statements.first as ExpressionStatement).expression;
    } else {
      return block;
    }

    if (expression is StaticInvocation) {
      if (expression.arguments.positional.length != 5) {
        print(
            "[AspectAopTransformer] arguments is not 5 so return ${expression.arguments.positional.length}");
        return block;
      }
      if (expression.arguments.positional[1] is StringLiteral &&
          expression.arguments.positional[2] is ListLiteral &&
          expression.arguments.positional[3] is MapLiteral &&
          expression.arguments.positional[4] is FunctionExpression) {
        if ((expression.arguments.positional[1] as StringLiteral).value ==
            originalProcedure.name.text) {
          block = (expression.arguments.positional[4] as FunctionExpression)
              .function
              .body as Block?;
          block = getInjectBlock(block, originalProcedure);
        }
        return block;
      }
      return block;
    } else {
      print(
          "[AspectAopTransformer] expression is not StaticInvocation so return ");
      return block;
    }
  }
}
