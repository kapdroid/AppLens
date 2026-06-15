import '../model/graph.dart';
import '../model/node.dart';
import 'diagnostic.dart';

/// Runs whole-graph static analysis (ARCHITECTURE.md §4). A graph with no
/// [Severity.error] diagnostics is guaranteed matchable at runtime.
///
/// Checks: duplicate ids, dangling edge targets, reachability from entry nodes,
/// orphan/incomplete baseline refs, guard well-formedness, and — the most
/// important — fingerprint ambiguity (two nodes whose identities can match the
/// same observable state).
List<Diagnostic> validateGraph(Graph graph) {
  final diagnostics = <Diagnostic>[];
  _checkDuplicateIds(graph, diagnostics);
  _checkDanglingEdges(graph, diagnostics);
  _checkReachability(graph, diagnostics);
  _checkAmbiguity(graph, diagnostics);
  _checkBaselines(graph, diagnostics);
  _checkGuards(graph, diagnostics);
  return diagnostics;
}

/// Whether [graph] has no error-level diagnostics.
bool graphIsValid(Graph graph) =>
    validateGraph(graph).every((diagnostic) => !diagnostic.isError);

void _checkDuplicateIds(Graph graph, List<Diagnostic> out) {
  final seen = <String>{};
  for (final node in graph.nodes) {
    if (!seen.add(node.id)) {
      out.add(
        Diagnostic(
          Severity.error,
          'duplicate_id',
          'duplicate node id "${node.id}"',
          location: node.source,
        ),
      );
    }
  }
}

void _checkDanglingEdges(Graph graph, List<Diagnostic> out) {
  for (final node in graph.nodes) {
    for (final edge in node.payload.edges) {
      if (!graph.byId.containsKey(edge.target)) {
        out.add(
          Diagnostic(
            Severity.error,
            'dangling_edge',
            'edge from "${node.id}" targets unknown node "${edge.target}"',
            location: node.source,
          ),
        );
      }
    }
  }
}

void _checkReachability(Graph graph, List<Diagnostic> out) {
  if (graph.entryNodeIds.isEmpty) {
    out.add(
      const Diagnostic(
        Severity.warning,
        'no_entry_nodes',
        'graph declares no entry nodes; reachability cannot be checked',
      ),
    );
    return;
  }

  final reachable = <String>{};
  final queue = <String>[];
  for (final id in graph.entryNodeIds) {
    if (!graph.byId.containsKey(id)) {
      out.add(
        Diagnostic(
          Severity.error,
          'unknown_entry_node',
          'declared entry node "$id" does not exist',
        ),
      );
      continue;
    }
    if (reachable.add(id)) {
      queue.add(id);
    }
  }

  while (queue.isNotEmpty) {
    final node = graph.byId[queue.removeLast()]!;
    for (final edge in node.payload.edges) {
      if (graph.byId.containsKey(edge.target) && reachable.add(edge.target)) {
        queue.add(edge.target);
      }
    }
  }

  for (final node in graph.nodes) {
    if (!reachable.contains(node.id)) {
      out.add(
        Diagnostic(
          Severity.error,
          'unreachable_node',
          'node "${node.id}" is unreachable from any entry node',
          location: node.source,
        ),
      );
    }
  }
}

void _checkAmbiguity(Graph graph, List<Diagnostic> out) {
  final nodes = graph.nodes;
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      final a = nodes[i];
      final b = nodes[j];
      if (_indistinguishable(a.identity, b.identity)) {
        out.add(
          Diagnostic(
            Severity.error,
            'fingerprint_ambiguity',
            'nodes "${a.id}" and "${b.id}" are fingerprint-ambiguous: their '
                'identities can match the same state — distinguish them with a '
                'different route, a contradicting flag, or the overlay flag',
            location: a.source,
          ),
        );
      }
    }
  }
}

/// True when no observable state can rule one identity out in favor of the
/// other: compatible routes, the same overlay, and no flag they both constrain
/// contradicts. Anchors are existence-only and never distinguish.
bool _indistinguishable(NodeIdentity a, NodeIdentity b) {
  final routesCompatible =
      a.route == null || b.route == null || a.route == b.route;
  if (!routesCompatible) {
    return false;
  }
  if (a.overlay != b.overlay) {
    return false;
  }
  for (final entry in a.flags.entries) {
    final other = b.flags[entry.key];
    if (other != null && entry.value.contradicts(other)) {
      return false;
    }
  }
  return true;
}

void _checkBaselines(Graph graph, List<Diagnostic> out) {
  for (final node in graph.nodes) {
    for (final baseline in node.payload.visualBaselines) {
      final image = baseline.image;
      if (image == null || image.isEmpty) {
        out.add(
          Diagnostic(
            Severity.error,
            'orphan_baseline',
            'visual baseline on "${node.id}" has no image reference',
            location: node.source,
          ),
        );
      }
      final context = baseline.context;
      if (context.device.isEmpty ||
          context.locale.isEmpty ||
          context.theme.isEmpty) {
        out.add(
          Diagnostic(
            Severity.warning,
            'incomplete_baseline_context',
            'visual baseline on "${node.id}" is missing device/locale/theme',
            location: node.source,
          ),
        );
      }
    }
    // Semantic (tier-2.5) baselines get the same checks — without them, an
    // approved baseline missing its snapshot, or a context typo, silently
    // disables the tier on a green run (the class hardened for the visual tier).
    for (final baseline in node.payload.structuralBaselines) {
      final snapshot = baseline.snapshot;
      if (snapshot == null || snapshot.isEmpty) {
        out.add(
          Diagnostic(
            Severity.error,
            'orphan_baseline',
            'structural baseline on "${node.id}" has no snapshot reference',
            location: node.source,
          ),
        );
      }
      final context = baseline.context;
      if (context.device.isEmpty ||
          context.locale.isEmpty ||
          context.theme.isEmpty) {
        out.add(
          Diagnostic(
            Severity.warning,
            'incomplete_baseline_context',
            'structural baseline on "${node.id}" is missing device/locale/theme',
            location: node.source,
          ),
        );
      }
    }
    for (final assertion in node.payload.assertions) {
      if (assertion.type == 'layout_hash' &&
          !assertion.args.containsKey('baseline')) {
        out.add(
          Diagnostic(
            Severity.warning,
            'layout_hash_without_baseline',
            'layout_hash assertion on "${node.id}" has no baseline reference',
            location: node.source,
          ),
        );
      }
    }
  }
}

void _checkGuards(Graph graph, List<Diagnostic> out) {
  for (final node in graph.nodes) {
    final guard = node.payload.guard;
    if (guard == null) {
      continue;
    }
    for (final requirement in guard.requires) {
      if (requirement.trim().isEmpty) {
        out.add(
          Diagnostic(
            Severity.error,
            'empty_guard',
            'node "${node.id}" has an empty guard requirement',
            location: node.source,
          ),
        );
      }
    }
  }
}
