# applens_compare

A **tolerant, anti-aliasing-aware `GoldenFileComparator`** for `flutter_test` —
a drop-in replacement for the default exact-match comparator, whose
pixel-for-pixel strictness is the #1 golden-test complaint (one stray
anti-aliased pixel fails the whole test).

Standalone: **zero AppLens knowledge required.** It's a first-party Dart port of
[mapbox/pixelmatch](https://github.com/mapbox/pixelmatch) (ISC), validated
byte-for-byte against the upstream fixtures, with dual thresholds — a per-pixel
YIQ perceptual tolerance and an overall diff ratio.

## Use (2 lines)

In `test/flutter_test_config.dart` (auto-loaded by `flutter test`):

```dart
import 'dart:io';
import 'package:applens_compare/applens_compare.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  goldenFileComparator = AppLensGoldenFileComparator(Directory('test').uri);
  await main();
}
```

That's it — your existing `matchesGoldenFile(...)` tests now tolerate
sub-threshold rendering noise instead of failing on a single AA pixel. Tune it:

```dart
goldenFileComparator = AppLensGoldenFileComparator(
  Directory('test').uri,
  comparator: const VisualComparator(yiqThreshold: 0.1, diffRatioThreshold: 0.001),
);
```

## Direct comparison

```dart
final verdict = const VisualComparator().compare(actualPng, expectedPng);
if (!verdict.matches) {
  print('${verdict.mismatchedPixels} px differ (${verdict.diffRatio})');
  File('diff.png').writeAsBytesSync(verdict.diffPng!); // red diff overlay
}
```

Masks (e.g. a dynamic clock) are blanked in both images before comparison:
`VisualComparator(masks: [MaskRect(left, top, width, height)])`.

## License

Apache-2.0. The vendored pixelmatch port is ISC, © 2019 Mapbox — see
`test/fixtures/ATTRIBUTION.md`.
