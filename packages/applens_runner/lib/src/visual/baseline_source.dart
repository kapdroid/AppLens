import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';

/// Loads approved baseline images for tier-3 comparison, keeping the runner
/// storage-agnostic: the host CLI loads PNGs from the graph's `goldens/`
/// directory and the device loads them from bundled assets, both behind this
/// seam (ARCHITECTURE.md §8/§9). Mirrors the GraphFiles seam used for nodes.
abstract interface class BaselineSource {
  /// The PNG bytes for [baseline]'s content-addressed image, or null when the
  /// image is absent — a tagged node awaiting its first recorded baseline,
  /// which tier 3 reports as *skipped* rather than a pass or fail.
  Future<Uint8List?> load(VisualBaseline baseline);
}
