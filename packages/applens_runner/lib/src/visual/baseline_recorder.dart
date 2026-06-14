import 'dart:io';

import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';
import 'baseline_source.dart';

/// A baseline captured for one node, ready to be added to the graph. The human
/// reviews and commits it — baselines flow through a PR, never written to the
/// graph directory by a code path (CLAUDE.md, ARCHITECTURE.md §9), so this is
/// emitted as a *proposed* entry for the human to approve.
class RecordedBaseline {
  const RecordedBaseline({required this.nodeId, required this.baseline});

  final String nodeId;
  final VisualBaseline baseline;
}

/// Writes each captured PNG to `<goldensDir>/<hex>.png` (content-addressed via
/// [baselineImageKey]) and returns the [VisualBaseline] entry to add to each
/// node's YAML. Idempotent: a recapture with identical bytes rewrites the same
/// file, so re-recording an unchanged screen is a no-op diff.
///
/// [captures] and [kinds] are keyed by node id; [kinds] carries each node's
/// [captureKindOf]`(deriveCaptureScope(node))` so the baseline records the scope
/// it was taken at.
Future<List<RecordedBaseline>> recordBaselines({
  required Map<String, Capture> captures,
  required Map<String, CaptureKind> kinds,
  required BaselineContext context,
  required String goldensDir,
}) async {
  Directory(goldensDir).createSync(recursive: true);
  final recorded = <RecordedBaseline>[];
  for (final entry in captures.entries) {
    final png = entry.value.pngBytes;
    final key = baselineImageKey(png);
    File('$goldensDir/${key.substring('sha256:'.length)}.png')
        .writeAsBytesSync(png);
    recorded.add(
      RecordedBaseline(
        nodeId: entry.key,
        baseline: VisualBaseline(
          context: context,
          capture: kinds[entry.key] ?? CaptureKind.fullScreen,
          state: BaselineState.proposed,
          image: key,
        ),
      ),
    );
  }
  return recorded;
}
