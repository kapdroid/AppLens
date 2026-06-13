import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pixelmatch.dart';

/// A rectangular region (in device pixels) masked out of a comparison — e.g. a
/// dynamic clock or avatar. Both images are blanked here so the region never
/// counts as a difference (ARCHITECTURE.md §8).
class MaskRect {
  const MaskRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;
}

/// The outcome of a tolerant comparison.
class VisualVerdict {
  const VisualVerdict({
    required this.matches,
    required this.mismatchedPixels,
    required this.diffRatio,
    this.diffPng,
  });

  final bool matches;

  /// Pixels that differed (after masking), or -1 when sizes did not match.
  final int mismatchedPixels;

  /// Mismatched pixels over the unmasked total.
  final double diffRatio;

  /// A red diff-overlay PNG, present only when [matches] is false.
  final Uint8List? diffPng;
}

/// Tolerant, anti-aliasing-aware image comparison (ARCHITECTURE.md §8): masks
/// applied to both images, then the vendored pixelmatch with dual thresholds —
/// a per-pixel YIQ tolerance and an overall diff ratio over unmasked pixels.
class VisualComparator {
  const VisualComparator({
    this.yiqThreshold = 0.1,
    this.diffRatioThreshold = 0.001,
    this.masks = const [],
  });

  final double yiqThreshold;
  final double diffRatioThreshold;
  final List<MaskRect> masks;

  /// Compares two PNG-encoded images.
  VisualVerdict compare(Uint8List actualPng, Uint8List expectedPng) {
    final actual = img.decodePng(actualPng);
    final expected = img.decodePng(expectedPng);
    if (actual == null || expected == null) {
      return const VisualVerdict(
        matches: false,
        mismatchedPixels: -1,
        diffRatio: 1,
      );
    }
    if (actual.width != expected.width || actual.height != expected.height) {
      return const VisualVerdict(
        matches: false,
        mismatchedPixels: -1,
        diffRatio: 1,
      );
    }

    final width = actual.width;
    final height = actual.height;
    final actualBytes = actual.getBytes(order: img.ChannelOrder.rgba);
    final expectedBytes = expected.getBytes(order: img.ChannelOrder.rgba);
    final maskedPixels = _applyMasks(actualBytes, expectedBytes, width, height);

    final output = Uint8List(actualBytes.length);
    final mismatched = pixelmatch(
      actualBytes,
      expectedBytes,
      output,
      width,
      height,
      PixelmatchOptions(threshold: yiqThreshold),
    );

    final unmasked = width * height - maskedPixels;
    final ratio = unmasked <= 0 ? 0.0 : mismatched / unmasked;
    final matches = ratio <= diffRatioThreshold;

    return VisualVerdict(
      matches: matches,
      mismatchedPixels: mismatched,
      diffRatio: ratio,
      diffPng: matches
          ? null
          : img.encodePng(
              img.Image.fromBytes(
                width: width,
                height: height,
                bytes: output.buffer,
                numChannels: 4,
                order: img.ChannelOrder.rgba,
              ),
            ),
    );
  }

  /// Blanks every masked pixel in both images and returns the count of
  /// distinct masked pixels — overlapping masks are counted once, so the
  /// unmasked total (and thus the diff ratio) stays correct.
  int _applyMasks(Uint8List a, Uint8List b, int width, int height) {
    if (masks.isEmpty) return 0;
    final covered = Uint8List(width * height);
    for (final mask in masks) {
      final top = mask.top.clamp(0, height);
      final bottom = (mask.top + mask.height).clamp(0, height);
      final left = mask.left.clamp(0, width);
      final right = (mask.left + mask.width).clamp(0, width);
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          covered[y * width + x] = 1;
        }
      }
    }
    var count = 0;
    for (var i = 0; i < covered.length; i++) {
      if (covered[i] == 0) continue;
      count++;
      final pos = i * 4;
      a[pos] = 0;
      a[pos + 1] = 0;
      a[pos + 2] = 0;
      a[pos + 3] = 255;
      b[pos] = 0;
      b[pos + 1] = 0;
      b[pos + 2] = 0;
      b[pos + 3] = 255;
    }
    return count;
  }
}
