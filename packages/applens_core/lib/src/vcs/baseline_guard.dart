import '../model/graph.dart';
import '../model/node.dart';
import '../util/canonical.dart';
import 'vcs_adapter.dart';

/// The canonical v1 [MergeGuard] (ARCHITECTURE.md §9): a baseline PR may
/// auto-merge only when every changed file is a content-addressed golden image
/// or a graph node file — never source, CI workflows, module manifests, or app
/// config. This is the *file-scope* backstop; [isBaselineOnlyGraphChange] is its
/// semantic companion that proves a node file's edits are confined to
/// `visual_baselines`. The host never decides the merge — this runs in-process.
class BaselineOnlyMergeGuard implements MergeGuard {
  const BaselineOnlyMergeGuard({
    this.goldenDir = 'goldens',
    this.nodeDirSegment = 'nodes',
  });

  /// Path segment under which content-addressed goldens live (`goldens/*.png`).
  final String goldenDir;

  /// Path segment marking a graph node file (`modules/<m>/nodes/<n>.yaml`).
  final String nodeDirSegment;

  @override
  bool permits(Iterable<String> changedPaths) {
    final paths = changedPaths.toList();
    // A no-op PR is never auto-merged — there is nothing to approve.
    return paths.isNotEmpty && paths.every(_isAllowed);
  }

  bool _isAllowed(String path) {
    final segments = path.split('/');
    final lower = path.toLowerCase();
    final isGolden = segments.contains(goldenDir) && lower.endsWith('.png');
    final isNodeFile =
        segments.contains(nodeDirSegment) && lower.endsWith('.yaml');
    return isGolden || isNodeFile;
  }
}

/// True iff [after] differs from [before] *only* within nodes' `visual_baselines`
/// — identity, edges, assertions, guards, tags, includes, and the node set
/// itself all unchanged. This is the §9 guarantee that an auto-merged baseline
/// PR can never alter graph behaviour. Compared via the content hash with
/// baselines stripped, so it is independent of key and file ordering.
bool isBaselineOnlyGraphChange(Graph before, Graph after) {
  final beforeIds = before.byId.keys.toSet();
  final afterIds = after.byId.keys.toSet();
  if (beforeIds.length != afterIds.length || !beforeIds.containsAll(afterIds)) {
    return false;
  }
  for (final id in beforeIds) {
    if (contentHash(_withoutBaselines(before.byId[id]!)) !=
        contentHash(_withoutBaselines(after.byId[id]!))) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _withoutBaselines(Node node) {
  final map = node.toMap();
  final payload = map['payload'];
  if (payload is Map) {
    payload.remove('visual_baselines');
    // toMap drops empty maps (compactMap); match that so a node that only ever
    // had baselines compares equal to one with an emptied payload.
    if (payload.isEmpty) {
      map.remove('payload');
    }
  }
  return map;
}
