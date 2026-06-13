import 'dart:typed_data';

import 'package:applens_runner/applens_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('framesIdentical', () {
    test('equal bytes are identical', () {
      expect(
        framesIdentical(
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([1, 2, 3]),
        ),
        isTrue,
      );
    });

    test('different length or content is not identical', () {
      expect(
        framesIdentical(
            Uint8List.fromList([1, 2]), Uint8List.fromList([1, 2, 3])),
        isFalse,
      );
      expect(
        framesIdentical(
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([1, 9, 3]),
        ),
        isFalse,
      );
    });
  });

  group('FrameStabilizer', () {
    test('stabilizes once two consecutive frames match', () async {
      final frames = [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
        Uint8List.fromList([2]),
      ];
      var index = 0;
      var pumps = 0;
      const stabilizer = FrameStabilizer(maxAttempts: 5);

      Future<Uint8List> nextFrame() async {
        final frame = frames[index.clamp(0, frames.length - 1)];
        index++;
        return frame;
      }

      final stabilized = await stabilizer.stabilize(
        pump: () async => pumps++,
        capture: nextFrame,
      );

      expect(stabilized, isTrue);
      expect(pumps, greaterThanOrEqualTo(3));
    });

    test('gives up when frames never stabilize within the budget', () async {
      var counter = 0;
      const stabilizer = FrameStabilizer(maxAttempts: 4);

      final stabilized = await stabilizer.stabilize(
        pump: () async {},
        capture: () async => Uint8List.fromList([counter++]),
      );

      expect(stabilized, isFalse);
    });
  });
}
