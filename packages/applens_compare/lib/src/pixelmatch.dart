import 'dart:typed_data';

// A first-party Dart port of mapbox/pixelmatch v5.3.0 (ISC, © 2019 Mapbox) —
// see test/fixtures/ATTRIBUTION. Ported, not depended on, so the comparator
// never sits behind another project's release cycle (ARCHITECTURE.md §14).
// Validated byte-for-byte against the upstream test fixtures. Watch the RGBA
// byte-format trap: inputs must be straight (un-premultiplied) RGBA.

/// Options for [pixelmatch].
class PixelmatchOptions {
  const PixelmatchOptions({
    this.threshold = 0.1,
    this.includeAA = false,
    this.alpha = 0.1,
    this.aaColor = const [255, 255, 0],
    this.diffColor = const [255, 0, 0],
    this.diffColorAlt,
    this.diffMask = false,
  });

  /// Matching threshold (0–1); smaller is more sensitive.
  final double threshold;

  /// Whether to skip anti-aliasing detection.
  final bool includeAA;

  /// Opacity of the original image in the diff output.
  final double alpha;
  final List<int> aaColor;
  final List<int> diffColor;
  final List<int>? diffColorAlt;

  /// Draw the diff over a transparent background (a mask).
  final bool diffMask;
}

/// Compares two equally sized straight-RGBA images pixel by pixel, optionally
/// writing a diff into [output]. Returns the number of mismatched pixels.
int pixelmatch(
  Uint8List img1,
  Uint8List img2,
  Uint8List? output,
  int width,
  int height, [
  PixelmatchOptions options = const PixelmatchOptions(),
]) {
  if (img1.length != img2.length ||
      (output != null && output.length != img1.length)) {
    throw ArgumentError('Image sizes do not match.');
  }
  if (img1.length != width * height * 4) {
    throw ArgumentError('Image data size does not match width/height.');
  }

  final len = width * height;
  var identical = true;
  for (var i = 0; i < img1.length; i++) {
    if (img1[i] != img2[i]) {
      identical = false;
      break;
    }
  }
  if (identical) {
    if (output != null && !options.diffMask) {
      for (var i = 0; i < len; i++) {
        _drawGrayPixel(img1, 4 * i, options.alpha, output);
      }
    }
    return 0;
  }

  // 35215 is the maximum possible value for the YIQ difference metric.
  final maxDelta = 35215 * options.threshold * options.threshold;
  var diff = 0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pos = (y * width + x) * 4;
      final delta = _colorDelta(img1, img2, pos, pos, false);

      if (delta.abs() > maxDelta) {
        if (!options.includeAA &&
            (_antialiased(img1, x, y, width, height, img2) ||
                _antialiased(img2, x, y, width, height, img1))) {
          if (output != null && !options.diffMask) {
            _drawPixel(output, pos, options.aaColor);
          }
        } else {
          if (output != null) {
            _drawPixel(
              output,
              pos,
              delta < 0 && options.diffColorAlt != null
                  ? options.diffColorAlt!
                  : options.diffColor,
            );
          }
          diff++;
        }
      } else if (output != null && !options.diffMask) {
        _drawGrayPixel(img1, pos, options.alpha, output);
      }
    }
  }
  return diff;
}

bool _antialiased(
  Uint8List img,
  int x1,
  int y1,
  int width,
  int height,
  Uint8List img2,
) {
  final x0 = (x1 - 1).clamp(0, width - 1);
  final y0 = (y1 - 1).clamp(0, height - 1);
  final x2 = (x1 + 1).clamp(0, width - 1);
  final y2 = (y1 + 1).clamp(0, height - 1);
  final pos = (y1 * width + x1) * 4;
  var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0;
  var min = 0.0;
  var max = 0.0;
  var minX = 0;
  var minY = 0;
  var maxX = 0;
  var maxY = 0;

  for (var x = x0; x <= x2; x++) {
    for (var y = y0; y <= y2; y++) {
      if (x == x1 && y == y1) {
        continue;
      }
      final delta = _colorDelta(img, img, pos, (y * width + x) * 4, true);

      if (delta == 0) {
        zeroes++;
        if (zeroes > 2) {
          return false;
        }
      } else if (delta < min) {
        min = delta;
        minX = x;
        minY = y;
      } else if (delta > max) {
        max = delta;
        maxX = x;
        maxY = y;
      }
    }
  }

  if (min == 0 || max == 0) {
    return false;
  }

  return (_hasManySiblings(img, minX, minY, width, height) &&
          _hasManySiblings(img2, minX, minY, width, height)) ||
      (_hasManySiblings(img, maxX, maxY, width, height) &&
          _hasManySiblings(img2, maxX, maxY, width, height));
}

bool _hasManySiblings(Uint8List img, int x1, int y1, int width, int height) {
  final x0 = (x1 - 1).clamp(0, width - 1);
  final y0 = (y1 - 1).clamp(0, height - 1);
  final x2 = (x1 + 1).clamp(0, width - 1);
  final y2 = (y1 + 1).clamp(0, height - 1);
  final pos = (y1 * width + x1) * 4;
  var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0;

  for (var x = x0; x <= x2; x++) {
    for (var y = y0; y <= y2; y++) {
      if (x == x1 && y == y1) {
        continue;
      }
      final pos2 = (y * width + x) * 4;
      if (img[pos] == img[pos2] &&
          img[pos + 1] == img[pos2 + 1] &&
          img[pos + 2] == img[pos2 + 2] &&
          img[pos + 3] == img[pos2 + 3]) {
        zeroes++;
      }
      if (zeroes > 2) {
        return true;
      }
    }
  }
  return false;
}

double _colorDelta(Uint8List img1, Uint8List img2, int k, int m, bool yOnly) {
  var r1 = img1[k].toDouble();
  var g1 = img1[k + 1].toDouble();
  var b1 = img1[k + 2].toDouble();
  final a1 = img1[k + 3].toDouble();

  var r2 = img2[m].toDouble();
  var g2 = img2[m + 1].toDouble();
  var b2 = img2[m + 2].toDouble();
  final a2 = img2[m + 3].toDouble();

  if (a1 == a2 && r1 == r2 && g1 == g2 && b1 == b2) {
    return 0;
  }

  if (a1 < 255) {
    final a = a1 / 255;
    r1 = _blend(r1, a);
    g1 = _blend(g1, a);
    b1 = _blend(b1, a);
  }
  if (a2 < 255) {
    final a = a2 / 255;
    r2 = _blend(r2, a);
    g2 = _blend(g2, a);
    b2 = _blend(b2, a);
  }

  final y1 = _rgb2y(r1, g1, b1);
  final y2 = _rgb2y(r2, g2, b2);
  final y = y1 - y2;

  if (yOnly) {
    return y;
  }

  final i = _rgb2i(r1, g1, b1) - _rgb2i(r2, g2, b2);
  final q = _rgb2q(r1, g1, b1) - _rgb2q(r2, g2, b2);
  final delta = 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q;

  return y1 > y2 ? -delta : delta;
}

double _rgb2y(double r, double g, double b) =>
    r * 0.29889531 + g * 0.58662247 + b * 0.11448223;
double _rgb2i(double r, double g, double b) =>
    r * 0.59597799 - g * 0.27417610 - b * 0.32180189;
double _rgb2q(double r, double g, double b) =>
    r * 0.21147017 - g * 0.52261711 + b * 0.31114694;

double _blend(double c, double a) => 255 + (c - 255) * a;

void _drawPixel(Uint8List output, int pos, List<int> color) {
  output[pos] = color[0];
  output[pos + 1] = color[1];
  output[pos + 2] = color[2];
  output[pos + 3] = 255;
}

void _drawGrayPixel(Uint8List img, int i, double alpha, Uint8List output) {
  final val = _blend(
    _rgb2y(img[i].toDouble(), img[i + 1].toDouble(), img[i + 2].toDouble()),
    alpha * img[i + 3] / 255,
  ).toInt();
  _drawPixel(output, i, [val, val, val]);
}
