import 'dart:io';

import 'package:test/test.dart';

import '../tool/check_boundaries.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('applens_boundaries_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  void writeLib(String pkg, String relPath, String contents) {
    final file = File('${tmp.path}/$pkg/lib/$relPath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('a clean layered set of packages has no violations', () {
    writeLib('applens_core', 'applens_core.dart', "export 'src/x.dart';\n");
    writeLib('applens_core', 'src/x.dart', 'class X {}\n');
    writeLib(
      'applens_runner',
      'applens_runner.dart',
      "import 'package:applens_core/applens_core.dart';\n",
    );
    writeLib(
      'applens_report',
      'applens_report.dart',
      "import 'package:applens_core/applens_core.dart';\n",
    );
    expect(checkBoundaries(tmp.path), isEmpty);
  });

  test('an upward / disallowed import is flagged with a line number', () {
    // applens_core is a leaf and may import no internal package.
    writeLib(
      'applens_core',
      'applens_core.dart',
      "import 'package:applens_runner/applens_runner.dart';\n",
    );
    final violations = checkBoundaries(tmp.path);
    expect(violations, hasLength(1));
    expect(violations.single.line, 1);
    expect(
      violations.single.message,
      contains('applens_core may not import applens_runner'),
    );
  });

  test('importing a concrete driver from above the seam is flagged', () {
    // applens_cli may depend on applens_runner, but not reach into its driver
    // implementation.
    writeLib(
      'applens_cli',
      'applens_cli.dart',
      "import 'package:applens_runner/src/driver/applens_driver.dart';\n",
    );
    final violations = checkBoundaries(tmp.path);
    expect(violations, hasLength(1));
    expect(violations.single.message, contains('concrete driver import'));
  });

  test('the driver layer itself may import its own implementations', () {
    writeLib(
      'applens_runner',
      'src/driver/applens_driver.dart',
      "import 'driver.dart';\n",
    );
    writeLib(
      'applens_runner',
      'src/driver/driver.dart',
      'abstract interface class AppLensDriver {}\n',
    );
    expect(checkBoundaries(tmp.path), isEmpty);
  });

  test('a relative reach into lib/src/driver from outside is flagged', () {
    writeLib(
      'applens_runner',
      'src/orchestrator.dart',
      "import 'driver/fake_driver.dart';\n",
    );
    writeLib(
      'applens_runner',
      'src/driver/fake_driver.dart',
      'class FakeDriver {}\n',
    );
    final violations = checkBoundaries(tmp.path);
    expect(violations, hasLength(1));
    expect(violations.single.message, contains('concrete driver import'));
  });

  test('importing the DriverInterface (driver.dart) from above is allowed', () {
    writeLib(
      'applens_runner',
      'src/orchestrator.dart',
      "import 'driver/driver.dart';\n",
    );
    writeLib(
      'applens_runner',
      'src/driver/driver.dart',
      'abstract interface class AppLensDriver {}\n',
    );
    expect(checkBoundaries(tmp.path), isEmpty);
  });
}
