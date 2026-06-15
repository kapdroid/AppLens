import 'dart:convert';
import 'dart:io';

import 'package:applens_core/applens_core.dart';

const String _shaPrefix = 'sha256:';

/// Loads recorded semantic snapshots for the tier-2.5 comparison, keeping the
/// runner storage-agnostic (mirrors [BaselineSource]): the host CLI reads JSON
/// from the graph's `structural/` directory and the device reads it from bundled
/// assets, both behind this seam (ARCHITECTURE.md §8).
abstract interface class StructuralBaselineSource {
  /// The recorded snapshot for [baseline]'s content-addressed reference, or null
  /// when it is absent — the semantic tier then reports *skipped*, never a pass
  /// or fail.
  Future<StructuralSnapshot?> load(StructuralBaseline baseline);
}

/// Reads content-addressed snapshots from a host directory as `<hex>.json`.
class IoStructuralBaselineSource implements StructuralBaselineSource {
  const IoStructuralBaselineSource(this.structuralDir);

  /// Directory holding `<hex>.json` snapshots (typically `<graph>/structural`).
  final String structuralDir;

  @override
  Future<StructuralSnapshot?> load(StructuralBaseline baseline) async {
    final ref = baseline.snapshot;
    if (ref == null || !ref.startsWith(_shaPrefix)) {
      return null;
    }
    final file =
        File('$structuralDir/${ref.substring(_shaPrefix.length)}.json');
    if (!file.existsSync()) {
      return null;
    }
    final map = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return StructuralSnapshot.fromMap(map);
  }
}

/// In-memory snapshots (`sha256:<hex>` → snapshot) for on-device runs that
/// pre-load the bundled JSON, mirroring [MapBaselineSource].
class MapStructuralBaselineSource implements StructuralBaselineSource {
  const MapStructuralBaselineSource(this._snapshots);

  final Map<String?, StructuralSnapshot> _snapshots;

  @override
  Future<StructuralSnapshot?> load(StructuralBaseline baseline) async =>
      _snapshots[baseline.snapshot];
}
