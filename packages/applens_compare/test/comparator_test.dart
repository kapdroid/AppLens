import 'dart:io';
import 'dart:typed_data';

import 'package:applens_compare/applens_compare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(String name) => File('test/fixtures/$name').readAsBytesSync();

/// A 10×10 black PNG with a solid white [block]×[block] square at the
/// bottom-right corner — a deterministic, AA-free synthetic for mask math.
Uint8List _corner(int block) {
  final image = img.Image(width: 10, height: 10, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 255));
  for (var y = 10 - block; y < 10; y++) {
    for (var x = 10 - block; x < 10; x++) {
      image.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _black() {
  final image = img.Image(width: 10, height: 10, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('tolerates a perceptually-identical but byte-different pair', () {
    final verdict = const VisualComparator(yiqThreshold: 0.05)
        .compare(_png('5b.png'), _png('5a.png'));
    expect(verdict.matches, isTrue);
    expect(verdict.mismatchedPixels, 0);
    expect(verdict.diffPng, isNull);
  });

  test('flags a real difference and emits a red diff PNG', () {
    final verdict =
        const VisualComparator(yiqThreshold: 0.05, diffRatioThreshold: 0)
            .compare(_png('1b.png'), _png('1a.png'));
    expect(verdict.matches, isFalse);
    expect(verdict.mismatchedPixels, 143);
    expect(verdict.diffPng, isNotNull);
  });

  test('a size mismatch never matches', () {
    final verdict =
        const VisualComparator().compare(_png('5a.png'), _png('1a.png'));
    expect(verdict.matches, isFalse);
  });

  test('overlapping masks count their union, not the sum of their areas', () {
    // Two masks overlap in a 2×2 region (areas 25+25, union 46 of 100 px), both
    // well clear of the differing 2×2 corner block. The diff ratio is taken
    // over 100-46=54 unmasked px; the buggy sum (50) would give 100-50=50.
    // Asserting ratio == mismatched/54 pins the denominator regardless of how
    // many corner pixels survive AA detection.
    final verdict = const VisualComparator(
      yiqThreshold: 0.05,
      diffRatioThreshold: 0,
      masks: [MaskRect(0, 0, 5, 5), MaskRect(3, 3, 5, 5)],
    ).compare(_corner(2), _black());
    expect(verdict.mismatchedPixels, greaterThan(0));
    expect(verdict.diffRatio, closeTo(verdict.mismatchedPixels / 54, 1e-9));
  });

  group('AppLensGoldenFileComparator drop-in', () {
    final dir = Directory('test/fixtures').absolute.uri;

    test('passes a within-tolerance golden the exact comparator would reject',
        () async {
      final comparator = AppLensGoldenFileComparator(
        dir,
        comparator: const VisualComparator(yiqThreshold: 0.05),
      );
      // 5b "render" vs 5a golden: byte-different, perceptually identical — the
      // default LocalFileComparator (exact bytes) would fail this; we pass it.
      expect(await comparator.compare(_png('5b.png'), Uri.parse('5a.png')),
          isTrue);
    });

    test('still rejects a genuine regression', () async {
      final comparator = AppLensGoldenFileComparator(
        dir,
        comparator:
            const VisualComparator(yiqThreshold: 0.05, diffRatioThreshold: 0),
      );
      expect(await comparator.compare(_png('1b.png'), Uri.parse('1a.png')),
          isFalse);
    });

    test('negative control: the stock exact comparison rejects the same pair',
        () async {
      // flutter_test's own exact-match engine (the default behind
      // matchesGoldenFile) on the very pair we tolerate: 256px differ.
      final exact = await GoldenFileComparator.compareLists(
        _png('5b.png'),
        _png('5a.png'),
      );
      expect(exact.passed, isFalse);

      // Our drop-in, same inputs, passes — the contrast is real, not an
      // artifact of how the test feeds bytes in.
      final tolerant = AppLensGoldenFileComparator(
        dir,
        comparator: const VisualComparator(yiqThreshold: 0.05),
      );
      expect(
          await tolerant.compare(_png('5b.png'), Uri.parse('5a.png')), isTrue);
    });

    test('forTestFile roots golden resolution at the test file directory',
        () async {
      final comparator = AppLensGoldenFileComparator.forTestFile(
        dir.resolve('placeholder_test.dart'),
        comparator: const VisualComparator(yiqThreshold: 0.05),
      );
      expect(await comparator.compare(_png('5b.png'), Uri.parse('5a.png')),
          isTrue);
    });
  });
}
