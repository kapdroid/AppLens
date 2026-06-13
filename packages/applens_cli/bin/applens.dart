import 'dart:io';

import 'package:applens_cli/applens_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await AppLensCli().run(args);
}
