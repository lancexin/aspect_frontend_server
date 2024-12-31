// ignore_for_file: import_of_legacy_library_into_null_safe, unused_import

import 'dart:io';

import 'package:frontend_server/frontend_server.dart' as frontend;

import 'package:kernel/ast.dart';
import 'method_transformer.dart';
import 'try_catch_transformer.dart';
import 'utils.dart';

class AspectAopTransformer implements frontend.ProgramTransformer {
  @override
  void transform(Component component) {
    //TryCatchTransformer().transform(component);
    MethodAopTransformer().transform(component);
  }
}
