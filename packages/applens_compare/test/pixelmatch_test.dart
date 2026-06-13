import 'dart:io';
import 'dart:typed_data';

import 'package:applens_compare/applens_compare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

({Uint8List bytes, int width, int height}) _png(String name) {
  final decoded = img.decodePng(File('test/fixtures/$name').readAsBytesSync())!;
  return (
    bytes: decoded.getBytes(order: img.ChannelOrder.rgba),
    width: decoded.width,
    height: decoded.height,
  );
}

int _count(
  String a,
  String b, {
  double threshold = 0.1,
  List<int>? diffColorAlt,
}) {
  final first = _png(a);
  final second = _png(b);
  return pixelmatch(
    first.bytes,
    second.bytes,
    null,
    first.width,
    first.height,
    PixelmatchOptions(threshold: threshold, diffColorAlt: diffColorAlt),
  );
}

void main() {
  test('matches upstream pixelmatch v5.3.0 mismatch counts', () {
    expect(_count('1a.png', '1b.png', threshold: 0.05), 143);
    expect(_count('3a.png', '3b.png', threshold: 0.05), 212);
    expect(_count('6a.png', '6b.png', threshold: 0.05), 51);
    expect(_count('7a.png', '7b.png', diffColorAlt: [0, 255, 0]), 2448);
  });

  test('identical images report zero mismatches', () {
    expect(_count('1a.png', '1a.png', threshold: 0), 0);
  });

  test('diff output is byte-identical to the upstream 1diff fixture', () {
    final a = _png('1a.png');
    final b = _png('1b.png');
    final output = Uint8List(a.bytes.length);
    pixelmatch(
      a.bytes,
      b.bytes,
      output,
      a.width,
      a.height,
      const PixelmatchOptions(threshold: 0.05),
    );
    expect(output, equals(_png('1diff.png').bytes));
  });

  test('diffColorAlt paints darkened pixels its own color in the output', () {
    // 7a/7b differ in both directions; with an output buffer the alt-color
    // branch (delta < 0) must actually paint, not just be counted.
    final a = _png('7a.png');
    final b = _png('7b.png');
    final output = Uint8List(a.bytes.length);
    pixelmatch(
      a.bytes,
      b.bytes,
      output,
      a.width,
      a.height,
      const PixelmatchOptions(diffColorAlt: [0, 255, 0]),
    );
    var altPixels = 0;
    for (var i = 0; i < output.length; i += 4) {
      if (output[i] == 0 && output[i + 1] == 255 && output[i + 2] == 0) {
        altPixels++;
      }
    }
    expect(altPixels, greaterThan(0));
  });
}
