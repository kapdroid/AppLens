import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How a highlighted region changed, selecting its outline color.
enum AnnotationStyle { changed, moved, removed }

/// One labeled highlight box to draw over a screenshot, in *pixel* coordinates.
/// The runner converts its normalized findings into these (scaling by the
/// capture's resolution), keeping this package free of any AppLens model — it
/// depends on `image` alone (docs/ARCHITECTURE.md §14).
class AnnotationBox {
  const AnnotationBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    this.style = AnnotationStyle.changed,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final String label;
  final AnnotationStyle style;
}

img.ColorRgba8 _colorFor(AnnotationStyle style) => switch (style) {
      AnnotationStyle.changed => img.ColorRgba8(255, 40, 40, 255), // red
      AnnotationStyle.moved => img.ColorRgba8(255, 145, 0, 255), // orange
      AnnotationStyle.removed => img.ColorRgba8(220, 0, 220, 255), // magenta
    };

/// Draws each [boxes] entry as a labeled outline over [png], returning a new PNG
/// — the localized, human-readable failure highlight (ARCHITECTURE.md §8). Pure:
/// same input → same bytes. Boxes are clamped to the image; an undecodable PNG
/// is returned unchanged.
Uint8List annotate(Uint8List png, List<AnnotationBox> boxes) {
  final image = img.decodePng(png);
  if (image == null) {
    return png;
  }
  final maxX = image.width - 1;
  final maxY = image.height - 1;
  int clampX(int v) => v.clamp(0, maxX);
  int clampY(int v) => v.clamp(0, maxY);

  for (final box in boxes) {
    final color = _colorFor(box.style);
    final x1 = clampX(box.x);
    final y1 = clampY(box.y);
    final x2 = clampX(box.x + box.width);
    final y2 = clampY(box.y + box.height);
    img.drawRect(image,
        x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: 3);
    // Caption above the box (or just inside the top edge when flush to it).
    final labelY = box.y - 16 >= 0 ? box.y - 16 : y1 + 2;
    img.drawString(image, box.label,
        font: img.arial14,
        x: clampX(box.x + 2),
        y: clampY(labelY),
        color: color);
  }
  return Uint8List.fromList(img.encodePng(image));
}
