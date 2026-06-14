import 'dart:io';
import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:crypto/crypto.dart';

const String _shaPrefix = 'sha256:';

/// The content-address key for a baseline PNG — `sha256:<hex>`, the value stored
/// in [VisualBaseline.image] and the filename stem under `goldens/`. The same
/// bytes always key to the same golden, so a recapture that matches reuses the
/// existing file (ARCHITECTURE.md §8).
String baselineImageKey(Uint8List png) => '$_shaPrefix${sha256.convert(png)}';

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

/// Reads content-addressed goldens from a host directory as `<hex>.png` (the
/// CLI/host default).
class IoBaselineSource implements BaselineSource {
  const IoBaselineSource(this.goldensDir);

  /// Directory holding `<hex>.png` goldens (typically `<graph>/goldens`).
  final String goldensDir;

  @override
  Future<Uint8List?> load(VisualBaseline baseline) async {
    final image = baseline.image;
    if (image == null || !image.startsWith(_shaPrefix)) {
      return null;
    }
    final file = File('$goldensDir/${image.substring(_shaPrefix.length)}.png');
    return file.existsSync() ? file.readAsBytesSync() : null;
  }
}

/// In-memory goldens (`sha256:<hex>` → PNG bytes) for on-device runs that
/// pre-load the bundled goldens, mirroring MapGraphFiles.
class MapBaselineSource implements BaselineSource {
  const MapBaselineSource(this._images);

  final Map<String, Uint8List> _images;

  @override
  Future<Uint8List?> load(VisualBaseline baseline) async =>
      _images[baseline.image];
}
