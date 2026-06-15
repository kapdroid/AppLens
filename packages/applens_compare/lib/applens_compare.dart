/// AppLens compare: a standalone, tolerant, anti-aliasing-aware
/// GoldenFileComparator for plain flutter_test goldens — usable with zero
/// AppLens knowledge. The comparator (a vendored pixelmatch port) lands in
/// Session 6; these are its calibrated default thresholds
/// (docs/ARCHITECTURE.md §8).
library;

export 'src/annotate.dart';
export 'src/comparator.dart';
export 'src/golden_comparator.dart';
export 'src/pixelmatch.dart';

/// Default overall diff ratio over unmasked pixels above which a golden fails.
const double defaultDiffRatioThreshold = 0.001;

/// Default per-pixel YIQ perceptual color tolerance.
const double defaultYiqThreshold = 0.1;
