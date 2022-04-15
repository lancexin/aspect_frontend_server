// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'package:frontend_server/frontend_server.dart' as frontend;
import 'package:vm/target/flutter.dart';

import 'package:kernel/ast.dart';
import 'method_transformer.dart';
import 'trycatch_transformers.dart';
import 'utils.dart';

class AspectAopTransformer implements frontend.ProgramTransformer {
  @override
  void transform(Component component) {
    TryCacthTransformer().transform(component);
    MethodAopTransformer().transform(component);
  }
}
