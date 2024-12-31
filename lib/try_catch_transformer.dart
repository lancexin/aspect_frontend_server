// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'dart:io';

import 'package:frontend_server/frontend_server.dart' as frontend;

import 'package:kernel/ast.dart';
import 'method_transformer.dart';
import 'utils.dart';

class TryCatchItem {
  final Member aopMember;

  TryCatchItem({required this.aopMember});
}

class TryCatchTransformer implements frontend.ProgramTransformer {
  TryCatchItem? tryCatchItem;

  static Set<Catch> manipulateCatchSet = {};
  static Set<Procedure> manipulatedProcedureSet = {};

  @override
  void transform(Component component) {
    stdout.writeln("[TryCacthTransformer] start transform");
    tryCatchItem = null;
    manipulateCatchSet.clear();
    _collectTryCatchItem(component);

    if (tryCatchItem != null) {
      stdout.writeln("[TryCacthTransformer] start visitChildren");
      component.visitChildren(_TryCatchVisitor(tryCatchItem));
    } else {
      stdout.writeln("[TryCacthTransformer] skip visitChildren");
    }
  }

  static bool isAopProcedure(Member member) {
    final aopItem = MethodAopTransformer.processMethodItemMember(member);
    return aopItem != null;
  }

  static bool isTryCatchProcedure(Member member) {
    final aopItem = processTryCatchMember(member);
    return aopItem != null;
  }

  void _collectTryCatchItem(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      stdout.writeln(
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
              stdout.writeln(
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

class _TryCatchVisitor extends RecursiveVisitor {
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
    if (TryCatchTransformer.isAopProcedure(node)) {
      stdout.writeln(
          "[TryCatchTransformer] defaultMember isAopProcedure skip ${node.name.text}");
      return;
    }
    if (TryCatchTransformer.isTryCatchProcedure(node)) {
      stdout.writeln(
          "[TryCatchTransformer] defaultMember isTryCatchProcedure skip ${node.name.text}");
      return;
    }
    node.visitChildren(this);
  }

  @override
  void defaultStatement(Statement node) {
    node.visitChildren(this);
  }

  @override
  void visitCatch(Catch node) {
    var procedure = AopUtils.findProcedure(node);
    if (procedure != null && TryCatchTransformer.isAopProcedure(procedure)) {
      return;
    }
    if (procedure != null &&
        TryCatchTransformer.isTryCatchProcedure(procedure)) {
      return;
    }
    transformCatchNode(
        AopUtils.findLibrary(node), procedure, node, node.parent);
  }

  void transformCatchNode(Library? originalLibrary,
      Procedure? originalProcedure, Catch node, TreeNode? parent) {
    if (TryCatchTransformer.manipulateCatchSet.contains(node)) {
      stdout.writeln("[TryCacthTransformer] transform skip node");
      return;
    }
    // if (TryCacthTransformer.manipulatedProcedureSet
    //     .contains(originalProcedure)) {
    //   print("[TryCacthTransformer] transform skip originalProcedure");
    //   return;
    // }
    TryCatchTransformer.manipulateCatchSet.add(node);
    // if (originalProcedure != null) {
    //   TryCacthTransformer.manipulatedProcedureSet.add(originalProcedure);
    // }

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
      stdout.writeln("[MethodAopTransformer] isInjectBlock1 so return");
      return;
    }

    //将aspect相关的包导入源码文件
    if (originalLibrary == null) {
      stdout
          .writeln("[TryCacthTransformer] originalLibrary is null so return ");
      return;
    }

    AopUtils.insertLibraryDependency(
        originalLibrary, tryCatchItem!.aopMember.parent?.parent as Library?);

    //创建调用静态方法的参数
    final Arguments redirectArguments = Arguments.empty();

    if (originalProcedure?.name.text != null) {
      redirectArguments.positional
          .add(StringLiteral(originalProcedure!.name.text));
    } else {
      redirectArguments.positional.add(NullLiteral());
    }

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
    block.addStatement(ExpressionStatement(callExpression));
    //将原本的处理流程替换成注入后的流程
    stdout.writeln(
        "[TryCacthTransformer] inject success ${originalProcedure?.name.text} ${originalLibrary.fileUri.toString()}");
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
        TryCatchTransformer.processTryCatchMember(injectProcedure) != null) {
      stdout.writeln(
          "[TryCacthTransformer] isInjectBlock so return ${expression.name.text}");
      return true;
    } else {
      return false;
    }
  }
}
