import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'comparator.dart';

/// A tolerant, anti-aliasing-aware [GoldenFileComparator] — a drop-in
/// replacement for flutter_test's exact-match default (the #1 golden-test
/// complaint). Two-line adoption in `flutter_test_config.dart`:
///
/// ```dart
/// goldenFileComparator = AppLensGoldenFileComparator(Directory('test').uri);
/// ```
///
/// Standalone: requires zero AppLens knowledge.
class AppLensGoldenFileComparator extends GoldenFileComparator {
  AppLensGoldenFileComparator(this.basedir, {VisualComparator? comparator})
      : _comparator = comparator ?? const VisualComparator();

  /// Directory that golden [Uri]s resolve against (typically the test dir).
  final Uri basedir;
  final VisualComparator _comparator;

  /// Builds a comparator rooted at the directory of [testFile].
  factory AppLensGoldenFileComparator.forTestFile(
    Uri testFile, {
    VisualComparator? comparator,
  }) =>
      AppLensGoldenFileComparator(testFile.resolve('.'),
          comparator: comparator);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final file = File.fromUri(basedir.resolveUri(golden));
    if (!file.existsSync()) {
      throw TestFailure('Golden file not found: ${file.path}');
    }
    return _comparator.compare(imageBytes, await file.readAsBytes()).matches;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final file = File.fromUri(basedir.resolveUri(golden));
    await file.create(recursive: true);
    await file.writeAsBytes(imageBytes);
  }
}
