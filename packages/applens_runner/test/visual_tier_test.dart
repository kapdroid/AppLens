import 'dart:typed_data';

import 'package:applens_compare/applens_compare.dart';
import 'package:applens_runner/src/driver/driver.dart';
import 'package:applens_runner/src/visual/visual_tier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A solid w×h straight-RGBA buffer — what the device hands the evaluator.
Uint8List _rgba(int w, int h, int r, int g, int b) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final p = i * 4;
    bytes[p] = r;
    bytes[p + 1] = g;
    bytes[p + 2] = b;
    bytes[p + 3] = 255;
  }
  return bytes;
}

/// The same solid color encoded as a PNG baseline.
Uint8List _png(int w, int h, int r, int g, int b) => Uint8List.fromList(
      img.encodePng(
        img.Image.fromBytes(
          width: w,
          height: h,
          bytes: _rgba(w, h, r, g, b).buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ),
      ),
    );

Capture _capture(int w, int h, int r, int g, int b) =>
    Capture(bytes: _rgba(w, h, r, g, b), width: w, height: h);

void main() {
  test('a capture matching its baseline passes tier 3', () {
    final result = evaluateTier3(
      actual: _capture(8, 8, 10, 20, 30),
      baselinePng: _png(8, 8, 10, 20, 30),
    );
    expect(result.assertion.tierOrder, tier3Order);
    expect(result.assertion.type, 'visual_match');
    expect(result.assertion.passed, isTrue);
    expect(result.diffPng, isNull);
  });

  test('a drifted capture fails and emits a red diff PNG', () {
    final result = evaluateTier3(
      actual: _capture(8, 8, 200, 0, 0),
      baselinePng: _png(8, 8, 10, 20, 30),
      comparator: const VisualComparator(diffRatioThreshold: 0),
    );
    expect(result.assertion.passed, isFalse);
    expect(result.assertion.detail, contains('px differ'));
    expect(result.diffPng, isNotNull);
  });

  test('no approved baseline → skipped, never a silent pass or fail', () {
    final result = evaluateTier3(
      actual: _capture(8, 8, 10, 20, 30),
      baselinePng: null,
    );
    expect(result.assertion.skipped, isTrue);
    expect(result.assertion.tierOrder, tier3Order);
    expect(result.diffPng, isNull);
  });

  test('a size mismatch never matches', () {
    final result = evaluateTier3(
      actual: _capture(8, 8, 10, 20, 30),
      baselinePng: _png(4, 4, 10, 20, 30),
    );
    expect(result.assertion.passed, isFalse);
  });
}
