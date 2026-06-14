import 'dart:collection';

import '../model/edge.dart';
import '../model/graph.dart';
import 'plan.dart';

/// The default tag whose nodes the smoke strategy must cover.
const String defaultSmokeTag = 'sanity';

/// The node ids belonging to any of [modules] — a node's module is the first
/// segment of its hierarchical id (`shop.dashboard` → `shop`), ARCHITECTURE.md
/// §5. The middle of impact's git-diff → modules → nodes chain.
Set<String> nodeIdsInModules(Graph graph, Set<String> modules) => {
      for (final id in graph.byId.keys)
        if (modules.contains(id.split('.').first)) id,
    };

/// Compiles [graph] into a [Plan] under [strategy] (ARCHITECTURE.md §6).
///
/// Expects a graph that passes `validateGraph`. Deterministic: the same graph,
/// strategy, and seed always produce a byte-identical plan. The `impact`
/// strategy targets [changedNodeIds] — the nodes a PR's diff touched (the CLI
/// resolves git-diff → modules → nodes) — and covers each affected node and every
/// edge into it, so a PR runs only the affected screens. `soak` (seeded random
/// walks) is not implemented yet.
Plan compilePlan(
  Graph graph, {
  required PlanStrategy strategy,
  int seed = 0,
  int alternates = 2,
  String smokeTag = defaultSmokeTag,
  Set<String> changedNodeIds = const {},
}) {
  final entries = (graph.entryNodeIds.toSet().toList())..sort();
  final nodeIds = graph.byId.keys.toList()..sort();

  final paths = switch (strategy) {
    PlanStrategy.smoke => _smoke(graph, entries, nodeIds, smokeTag),
    PlanStrategy.regression => _regression(graph, entries, nodeIds),
    PlanStrategy.impact => _impact(graph, entries, nodeIds, changedNodeIds),
    PlanStrategy.soak => throw UnimplementedError(
        'soak strategy is not implemented yet — see ARCHITECTURE.md §6 '
        '(seeded random walks).',
      ),
  };

  // Alternates are reroute options for the nodes the plan will visit; an impact
  // plan visits only the changed screens, so its alternates scope to them.
  final alternateTargets = strategy == PlanStrategy.impact
      ? (changedNodeIds.where(graph.byId.containsKey).toList()..sort())
      : nodeIds;

  return Plan(
    strategy: strategy,
    graphHash: graph.contentHash,
    seed: seed,
    paths: paths,
    alternateInboundPaths:
        _alternates(graph, entries, alternateTargets, alternates),
  );
}

// --- Strategies -------------------------------------------------------------

/// Shortest path to every node tagged [smokeTag], one path per tagged node.
List<PlanPath> _smoke(
  Graph graph,
  List<String> entries,
  List<String> nodeIds,
  String smokeTag,
) {
  final paths = <PlanPath>[];
  for (final id in nodeIds) {
    if (!graph.byId[id]!.payload.tags.contains(smokeTag)) {
      continue;
    }
    final reached = _bfsTo(graph, entries, (node) => node == id);
    if (reached != null) {
      paths.add(reached.toPlanPath());
    }
  }
  return paths;
}

/// Paths covering each node a PR touched ([changedNodeIds]) *and every edge into
/// it* (ARCHITECTURE.md §6) — so an impact run exercises every way of reaching an
/// affected screen, but nothing beyond the affected screens. For each impacted
/// node: a trivial path if it is an entry, plus, for each inbound edge, the
/// shortest path to that edge's source followed by the edge. Deterministic
/// (nodes and inbound edges in sorted order); unreachable ids are skipped; an
/// empty change set yields an empty plan (nothing impacted → nothing to run).
List<PlanPath> _impact(
  Graph graph,
  List<String> entries,
  List<String> nodeIds,
  Set<String> changedNodeIds,
) {
  final paths = <PlanPath>[];
  final seen = <String>{};
  void add(PlanPath path) {
    final key = '${path.start}>${path.steps.map((s) => s.to).join('>')}';
    if (seen.add(key)) paths.add(path);
  }

  for (final id in nodeIds) {
    if (!changedNodeIds.contains(id) || !graph.byId.containsKey(id)) {
      continue;
    }
    var added = false;
    if (entries.contains(id)) {
      add(PlanPath(start: id));
      added = true;
    }
    for (final hop in _inboundHops(graph, nodeIds, id)) {
      final prefix = _bfsTo(graph, entries, (node) => node == hop.from);
      if (prefix == null) {
        continue;
      }
      add(PlanPath(
          start: prefix.start, steps: [...prefix.steps(), hop.toStep()]));
      added = true;
    }
    if (!added) {
      // No covered inbound edge and not an entry — fall back to any shortest
      // path so a reachable impacted node is still exercised.
      final reached = _bfsTo(graph, entries, (node) => node == id);
      if (reached != null) add(reached.toPlanPath());
    }
  }
  return paths;
}

/// Directed edge coverage via a deterministic Chinese-postman-style greedy:
/// repeatedly route from an entry to the nearest node with an uncovered edge,
/// then follow uncovered edges greedily. Covers every reachable edge; optimality
/// is not required, determinism is.
List<PlanPath> _regression(
  Graph graph,
  List<String> entries,
  List<String> nodeIds,
) {
  final covered = <String>{};
  String key(String from, int index) => '$from#$index';

  bool hasUncovered(String id) {
    final edges = graph.byId[id]!.payload.edges;
    for (var i = 0; i < edges.length; i++) {
      if (graph.byId.containsKey(edges[i].target) &&
          !covered.contains(key(id, i))) {
        return true;
      }
    }
    return false;
  }

  final paths = <PlanPath>[];
  while (true) {
    final reached = _bfsTo(graph, entries, hasUncovered);
    if (reached == null) {
      break;
    }
    final hops = [...reached.hops];
    for (final hop in hops) {
      covered.add(key(hop.from, hop.index));
    }
    var current = reached.target;
    while (true) {
      final edges = graph.byId[current]!.payload.edges;
      var chosen = -1;
      for (var i = 0; i < edges.length; i++) {
        if (graph.byId.containsKey(edges[i].target) &&
            !covered.contains(key(current, i))) {
          chosen = i;
          break;
        }
      }
      if (chosen == -1) {
        break;
      }
      covered.add(key(current, chosen));
      hops.add(_Hop(current, edges[chosen], chosen));
      current = edges[chosen].target;
    }
    paths.add(_PathTo(reached.start, current, hops).toPlanPath());
  }
  return paths;
}

// --- Alternate inbound paths ------------------------------------------------

Map<String, List<PlanPath>> _alternates(
  Graph graph,
  List<String> entries,
  List<String> nodeIds,
  int k,
) {
  final result = <String, List<PlanPath>>{};
  for (final target in nodeIds) {
    final candidates = <PlanPath>[];
    if (entries.contains(target)) {
      candidates.add(PlanPath(start: target));
    }
    for (final hop in _inboundHops(graph, nodeIds, target)) {
      final prefix = _bfsTo(graph, entries, (node) => node == hop.from);
      if (prefix == null) {
        continue;
      }
      candidates.add(
        PlanPath(start: prefix.start, steps: [...prefix.steps(), hop.toStep()]),
      );
    }
    if (candidates.isEmpty) {
      continue;
    }
    candidates.sort((a, b) => _pathSortKey(a).compareTo(_pathSortKey(b)));
    result[target] = candidates.take(k).toList();
  }
  return result;
}

List<_Hop> _inboundHops(Graph graph, List<String> nodeIds, String target) {
  final hops = <_Hop>[];
  for (final from in nodeIds) {
    final edges = graph.byId[from]!.payload.edges;
    for (var i = 0; i < edges.length; i++) {
      if (edges[i].target == target) {
        hops.add(_Hop(from, edges[i], i));
      }
    }
  }
  hops.sort((a, b) {
    final byFrom = a.from.compareTo(b.from);
    return byFrom != 0 ? byFrom : a.index.compareTo(b.index);
  });
  return hops;
}

String _pathSortKey(PlanPath path) =>
    '${path.steps.length.toString().padLeft(6, '0')}|${path.start}|'
    '${path.steps.map((step) => step.to).join('>')}';

// --- Deterministic BFS ------------------------------------------------------

/// A traversed edge: from [from] via [edge] (index [index] in `from`'s edges).
class _Hop {
  const _Hop(this.from, this.edge, this.index);

  final String from;
  final Edge edge;
  final int index;

  PlanStep toStep() => PlanStep(
        action: edge.action,
        to: edge.target,
        key: edge.key,
        text: edge.text,
        uri: edge.uri,
      );
}

/// A reconstructed path: from [start] to [target] through [hops].
class _PathTo {
  const _PathTo(this.start, this.target, this.hops);

  final String start;
  final String target;
  final List<_Hop> hops;

  List<PlanStep> steps() => [for (final hop in hops) hop.toStep()];

  PlanPath toPlanPath() => PlanPath(start: start, steps: steps());
}

/// Multi-source BFS from [entries] (sorted) to the nearest node satisfying
/// [isTarget]. Deterministic: entries in sorted order, edges in declared order.
_PathTo? _bfsTo(
    Graph graph, List<String> entries, bool Function(String) isTarget) {
  final parent = <String, _Hop?>{};
  final origin = <String, String>{};
  final queue = Queue<String>();

  for (final entry in entries) {
    if (graph.byId.containsKey(entry) && !parent.containsKey(entry)) {
      parent[entry] = null;
      origin[entry] = entry;
      queue.add(entry);
    }
  }

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    if (isTarget(current)) {
      return _reconstruct(current, parent, origin);
    }
    final edges = graph.byId[current]!.payload.edges;
    for (var i = 0; i < edges.length; i++) {
      final next = edges[i].target;
      if (graph.byId.containsKey(next) && !parent.containsKey(next)) {
        parent[next] = _Hop(current, edges[i], i);
        origin[next] = origin[current]!;
        queue.add(next);
      }
    }
  }
  return null;
}

_PathTo _reconstruct(
  String target,
  Map<String, _Hop?> parent,
  Map<String, String> origin,
) {
  final hops = <_Hop>[];
  var current = target;
  while (parent[current] != null) {
    final hop = parent[current]!;
    hops.add(hop);
    current = hop.from;
  }
  return _PathTo(origin[target]!, target, hops.reversed.toList());
}
