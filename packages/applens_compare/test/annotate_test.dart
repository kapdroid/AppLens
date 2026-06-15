import 'dart:typed_data';

import 'package:applens_compare/applens_compare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _solid(int w, int h, int r, int g, int b) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('draws a box outline in the style color over the screenshot', () {
    final png = _solid(100, 100, 255, 255, 255); // white
    final out = annotate(png, const [
      AnnotationBox(x: 20, y: 30, width: 40, height: 20, label: 'x'),
    ]);
    final image = img.decodePng(out)!;

    // A pixel on the top edge of the box is the red 'changed' color…
    final edge = image.getPixel(40, 30);
    expect(edge.r, greaterThan(200));
    expect(edge.g, lessThan(120));
    expect(edge.b, lessThan(120));

    // …while a pixel far from any box is still white.
    final bg = image.getPixel(90, 90);
    expect(bg.r, 255);
    expect(bg.g, 255);
    expect(bg.b, 255);
  });

  test('moved vs changed use distinct colors', () {
    final png = _solid(80, 80, 0, 0, 0);
    final changed = img.decodePng(annotate(png, const [
      AnnotationBox(x: 10, y: 10, width: 30, height: 30, label: 'c'),
    ]))!;
    final moved = img.decodePng(annotate(png, const [
      AnnotationBox(
          x: 10,
          y: 10,
          width: 30,
          height: 30,
          label: 'm',
          style: AnnotationStyle.moved),
    ]))!;
    final c = changed.getPixel(25, 10);
    final m = moved.getPixel(25, 10);
    // changed = red, moved = orange → their green channels differ markedly.
    expect((c.g - m.g).abs(), greaterThan(60));
  });

  test('a box past the image edge is clamped, not a crash', () {
    final png = _solid(50, 50, 255, 255, 255);
    final out = annotate(png, const [
      AnnotationBox(x: 40, y: 40, width: 999, height: 999, label: 'edge'),
    ]);
    expect(img.decodePng(out), isNotNull);
  });

  test('an undecodable PNG is returned unchanged', () {
    final junk = Uint8List.fromList([1, 2, 3, 4]);
    expect(
        annotate(junk,
            const [AnnotationBox(x: 0, y: 0, width: 1, height: 1, label: '')]),
        junk);
  });
}
