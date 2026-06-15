import 'dart:collection';
import 'dart:math';

import '../model/edge.dart';
import '../model/graph.dart';
import 'plan.dart';

/// Default step budget for a soak walk.
const int defaultSoakSteps = 40;

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
/// edge into it, so a PR runs only the affected screens. `soak` is a seeded
/// random long walk weighted toward least-visited edges ([soakSteps] long) —
/// reproducible because the seed fixes every choice.
Plan compilePlan(
  Graph graph, {
  required PlanStrategy strategy,
  int seed = 0,
  int alternates = 2,
  String smokeTag = defaultSmokeTag,
  Set<String> changedNodeIds = const {},
  int soakSteps = defaultSoakSteps,
}) {
  final entries = (graph.entryNodeIds.toSet().toList())..sort();
  final nodeIds = graph.byId.keys.toList()..sort();

  final paths = switch (strategy) {
    PlanStrategy.smoke => _smoke(graph, entries, nodeIds, smokeTag),
    PlanStrategy.regression => _regression(graph, entries, nodeIds),
    PlanStrategy.impact => _impact(graph, entries, nodeIds, changedNodeIds),
    PlanStrategy.soak => _soak(graph, entries, seed, soakSteps),
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

/// The number of steps per soak segment. A soak walk is cut into segments, each
/// a fresh walk from the entry, so a hard failure mid-walk costs only the rest
/// of one short segment — the runner re-anchors to the entry between paths and
/// keeps exploring, rather than the whole long walk going `blocked`.
const int defaultSoakSegment = 8;

/// A seeded random soak (ARCHITECTURE.md §6): from the first entry, step along
/// the least-visited outgoing edge — biased so the walk explores rather than
/// looping a hot path — for a [steps] budget, split into segments of at most
/// [defaultSoakSegment] each. Every segment restarts from the entry but the
/// visit counts are shared, so later segments take edges earlier ones didn't.
/// Each segment is its own [PlanPath], which is what gives soak resilience: the
/// runner walks paths independently (returning to start between them), so a
/// stumble in one segment never blocks the others. One segment with no leaving
/// edges stops early (dead end). The seed's PRNG fixes every choice, so the
/// same graph + seed + budget yields a byte-identical plan.
List<PlanPath> _soak(Graph graph, List<String> entries, int seed, int steps) {
  if (entries.isEmpty) {
    return const [];
  }
  final rng = Random(seed);
  final visits = <String>[]; // "from#edgeIndex" appended once per traversal
  int count(String key) => visits.where((v) => v == key).length;

  final start = entries.first;
  final paths = <PlanPath>[];
  var remaining = steps;
  while (remaining > 0) {
    final segment =
        remaining < defaultSoakSegment ? remaining : defaultSoakSegment;
    final stepList = <PlanStep>[];
    var current = start;
    for (var i = 0; i < segment; i++) {
      final edges = graph.byId[current]!.payload.edges;
      if (edges.isEmpty) {
        break; // dead end — restart from the entry in the next segment
      }
      // Indices of the edges with the lowest visit count, in edge order.
      final keys = [for (var e = 0; e < edges.length; e++) '$current#$e'];
      final counts = keys.map(count).toList();
      final min = counts.reduce((a, b) => a < b ? a : b);
      final leastVisited = [
        for (var e = 0; e < edges.length; e++)
          if (counts[e] == min) e,
      ];
      final chosen = leastVisited[rng.nextInt(leastVisited.length)];
      final edge = edges[chosen];
      visits.add(keys[chosen]);
      stepList.add(PlanStep(
        action: edge.action,
        to: edge.target,
        key: edge.key,
        text: edge.text,
        uri: edge.uri,
        direction: edge.direction,
      ));
      current = edge.target;
    }
    paths.add(PlanPath(start: start, steps: stepList));
    remaining -= segment;
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
    // Dedup by edge identity, not just the node sequence: two parallel inbound
    // edges (same source and target, different action/key) are distinct ways in
    // and must both be covered (§6 "every edge into it").
    if (seen.add(_edgeIdentityKey(path))) paths.add(path);
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
    // Alternates are *distinct reroute routes*: collapse parallel inbound edges
    // (same node sequence, different action/key) to one, keeping the shortest.
    final routes = <String>{};
    result[target] = [
      for (final candidate in candidates)
        if (routes.add(_routeKey(candidate))) candidate,
    ].take(k).toList();
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

/// Identity of a path's *route* — its start and the node sequence it visits,
/// ignoring how each hop was taken. Two paths with the same route key reach the
/// same screens the same way structurally.
String _routeKey(PlanPath path) =>
    '${path.start}>${path.steps.map((step) => step.to).join('>')}';

/// Identity of a path including *how* each hop is taken (action + operands), so
/// parallel edges between the same two nodes are distinguished. Fields are joined
/// with the unit separator (U+001F), which can't appear in a key/text/uri, so an
/// operand containing the delimiter can't collide two distinct edges.
String _edgeIdentityKey(PlanPath path) {
  const sep = '\u001f';
  return [
    path.start,
    for (final step in path.steps)
      [
        step.to,
        step.action.yaml,
        step.key ?? '',
        step.text ?? '',
        step.uri ?? ''
      ].join(sep),
  ].join(sep);
}

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
        direction: edge.direction,
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
