// Enforces the architectural import boundaries from docs/SCAFFOLD.md §3/§5.
//
// Pure Dart, no package dependencies. Walks every packages/*/lib/**/*.dart
// file, parses its `import`/`export` directives, and asserts:
//
//   1. Driver isolation — nothing outside applens_runner/lib/src/driver/ may
//      import a concrete driver (anything under lib/src/driver/ other than the
//      DriverInterface itself, driver.dart).
//   2-5. Layering — a package may import another applens_* package only along
//      an edge in [allowedDeps]; everything else (including all upward imports,
//      and any import out of applens_core / applens_compare / applens_sdk) is a
//      violation.
//
// Exits non-zero on any violation, printing `file:line: rule`.

import 'dart:io';

/// The allowed internal dependency edges (docs/SCAFFOLD.md §3). A package may
/// import only the applens_* packages listed for it. Empty set = leaf package.
const Map<String, Set<String>> allowedDeps = {
  'applens_core': <String>{},
  'applens_llm': {'applens_core'},
  'applens_runner': {'applens_core'},
  'applens_compare': <String>{},
  'applens_crawler': {'applens_core', 'applens_runner'},
  'applens_report': {'applens_core'},
  'applens_cli': {
    'applens_core',
    'applens_llm',
    'applens_runner',
    'applens_compare',
    'applens_crawler',
    'applens_report',
  },
  'applens_sdk': <String>{},
};

/// A single boundary violation, formatted as `file:line: message`.
class BoundaryViolation {
  const BoundaryViolation(this.file, this.line, this.message);

  final String file;
  final int line;
  final String message;

  @override
  String toString() => '$file:$line: $message';
}

final RegExp _directive = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
);
final RegExp _packageUri = RegExp(r'^package:(applens_[a-z_]+)/(.+)$');

/// Returns the basename of a `/`-separated path.
String _basename(String path) => path.split('/').last;

/// Whether [filePath] sits inside any `lib/src/driver/` directory.
bool _underDriverDir(String filePath) => filePath.contains('/lib/src/driver/');

/// Scans [packagesDir] (a directory of applens_* packages) and returns every
/// boundary violation found. Pure: no process exit, no printing.
List<BoundaryViolation> checkBoundaries(String packagesDir) {
  final violations = <BoundaryViolation>[];
  final root = Directory(packagesDir);
  if (!root.existsSync()) {
    return violations;
  }

  for (final entity in root.listSync()) {
    if (entity is! Directory) {
      continue;
    }
    final pkg = _basename(entity.path);
    final allowed = allowedDeps[pkg];
    if (allowed == null) {
      continue; // Not a layered applens_* package; skip.
    }
    final libDir = Directory('${entity.path}/lib');
    if (!libDir.existsSync()) {
      continue;
    }

    for (final file in libDir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      if (file.path.endsWith('.g.dart') ||
          file.path.endsWith('.freezed.dart')) {
        continue;
      }
      _scanFile(file, pkg, allowed, violations);
    }
  }

  violations.sort((a, b) => a.toString().compareTo(b.toString()));
  return violations;
}

void _scanFile(
  File file,
  String pkg,
  Set<String> allowed,
  List<BoundaryViolation> violations,
) {
  final importerUnderDriver = _underDriverDir(file.path);
  final lines = file.readAsLinesSync();

  for (var i = 0; i < lines.length; i++) {
    final match = _directive.firstMatch(lines[i]);
    if (match == null) {
      continue;
    }
    final uri = match.group(1)!;
    final lineNo = i + 1;

    final pkgMatch = _packageUri.firstMatch(uri);
    if (pkgMatch != null) {
      final target = pkgMatch.group(1)!;
      final rest = pkgMatch.group(2)!;

      if (target != pkg && !allowed.contains(target)) {
        violations.add(
          BoundaryViolation(
            file.path,
            lineNo,
            'package $pkg may not import $target '
            '(allowed: ${allowed.isEmpty ? '(none)' : allowed.join(', ')})',
          ),
        );
      }

      // Reaching into another package's private driver implementation.
      if (target == 'applens_runner' &&
          rest.startsWith('src/driver/') &&
          _basename(rest) != 'driver.dart' &&
          !importerUnderDriver) {
        violations.add(
          BoundaryViolation(
            file.path,
            lineNo,
            'concrete driver import ($uri) is forbidden outside '
            'applens_runner/lib/src/driver/',
          ),
        );
      }
      continue;
    }

    if (uri.contains(':')) {
      continue; // dart:, other package:, etc.
    }

    // Relative import — resolve against the importing file's directory.
    final resolved = file.absolute.parent.uri.resolve(uri).toFilePath();
    if (_underDriverDir(resolved) &&
        _basename(resolved) != 'driver.dart' &&
        !importerUnderDriver) {
      violations.add(
        BoundaryViolation(
          file.path,
          lineNo,
          'concrete driver import ($uri) is forbidden outside lib/src/driver/',
        ),
      );
    }
  }
}

void main(List<String> args) {
  final packagesDir = args.isNotEmpty ? args.first : 'packages';
  final violations = checkBoundaries(packagesDir);

  if (violations.isEmpty) {
    stdout.writeln('✓ import boundaries clean ($packagesDir)');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  stderr.writeln('✗ ${violations.length} import-boundary violation(s)');
  exitCode = 1;
}
