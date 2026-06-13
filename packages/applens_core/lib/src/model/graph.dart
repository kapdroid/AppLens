import '../util/canonical.dart' as canonical;
import 'node.dart';

/// A module manifest (`<module>.module.yaml`): ownership, tags, and which of the
/// module's nodes are entry points (ARCHITECTURE.md §5).
class ModuleManifest {
  const ModuleManifest({
    required this.name,
    this.owner,
    this.tags = const [],
    this.entryNodes = const [],
  });

  final String name;
  final String? owner;
  final List<String> tags;

  /// Entry node ids (already module-qualified).
  final List<String> entryNodes;

  Map<String, Object?> toMap() => canonical.compactMap({
        'name': name,
        'owner': owner,
        'tags': tags,
        'entry_nodes': entryNodes,
      });
}

/// The whole app model: nodes, the declared entry points, and module metadata.
/// The graph in files is the machine source of truth; humans read generated
/// views (ARCHITECTURE.md §5).
class Graph {
  Graph({
    required List<Node> nodes,
    required this.entryNodeIds,
    this.modules = const [],
  })  : nodes = List.unmodifiable(nodes),
        byId = {for (final node in nodes) node.id: node};

  /// All nodes, in their loaded order. [toMap] sorts them so the content hash
  /// is independent of file read order.
  final List<Node> nodes;

  /// Node ids the runner may start from (reachability is measured from here).
  final List<String> entryNodeIds;

  final List<ModuleManifest> modules;

  /// Nodes indexed by id, for O(1) lookup and dangling-target checks.
  final Map<String, Node> byId;

  /// A canonical structural map, with nodes sorted by id — the basis for the
  /// content hash and structural equality.
  Map<String, Object?> toMap() {
    final sorted = [...nodes]..sort((a, b) => a.id.compareTo(b.id));
    return {
      'entry_nodes': [...entryNodeIds]..sort(),
      'nodes': [for (final node in sorted) node.toMap()],
    };
  }

  /// A stable `sha256:<hex>` hash of the graph's content, independent of YAML
  /// key ordering and node-file read order — used for plan staleness checks.
  String get contentHash => canonical.contentHash(toMap());
}
