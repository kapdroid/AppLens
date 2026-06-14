import 'dart:collection';

import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';

import 'crawl_session.dart';

/// The outcome of a crawl: the proposed draft [graph] (never auto-merged — it
/// becomes a PR a human prunes and approves), plus what was explored and what
/// was deliberately skipped.
class CrawlResult {
  const CrawlResult({
    required this.graph,
    required this.statesDiscovered,
    required this.actionsTried,
    required this.skippedDestructive,
  });

  final Graph graph;
  final int statesDiscovered;
  final int actionsTried;

  /// Destructive widget keys the crawl declined to exercise (§11).
  final List<String> skippedDestructive;
}

/// Explores the app breadth-first within [budget] and proposes a draft graph
/// (ARCHITECTURE.md §11). Each state is clustered by (route, tree shape) — the
/// same `layoutHash` the tier-2 oracle uses — into a proposed node; each action
/// that changes the state becomes a proposed edge. Destructive actions
/// (delete/submit/pay …) are skipped unless [allowDestructive]. Deterministic:
/// actions are exercised in sorted key order, so the same app yields the same
/// draft. The result is never merged automatically.
Future<CrawlResult> crawl(
  CrawlSession session, {
  CrawlBudget budget = const CrawlBudget(),
  bool allowDestructive = false,
  String module = 'app',
  Set<String> destructiveKeywords = defaultDestructiveKeywords,
}) async {
  final frontier = Queue<List<String>>()..add(const []);
  final nodes = <String, _DraftNode>{}; // state signature -> node
  final expanded = <String>{}; // signatures whose actions are already enqueued
  final edges = <String, _DraftEdge>{}; // dedup key -> edge
  final usedIds = <String>{};
  final skipped = <String>{};
  var actionsTried = 0;
  var counter = 0;
  String? rootSig;

  String register(String sig, Fingerprint fp) {
    final existing = nodes[sig];
    if (existing != null) return existing.id;
    final id = _uniqueId(module, fp.route, counter++, usedIds);
    nodes[sig] = _DraftNode(id: id, route: fp.route);
    return id;
  }

  while (frontier.isNotEmpty && nodes.length < budget.maxStates) {
    final path = frontier.removeFirst();
    await session.reset();
    var fp = await session.fingerprint.capture();
    var tree = await session.driver.tree();
    var sig = _signature(fp, tree);
    register(sig, fp);
    rootSig ??= sig;

    var replayFailed = false;
    for (final key in path) {
      try {
        await session.driver.tap(KeySelector(key));
        await session.driver.settle(const SettlePolicy());
      } on DriverException {
        replayFailed =
            true; // the app diverged from the recorded path; abandon it
        break;
      }
      actionsTried++;
      fp = await session.fingerprint.capture();
      tree = await session.driver.tree();
      final next = _signature(fp, tree);
      final fromId = nodes[sig]!.id;
      final toId = register(next, fp);
      final edgeKey = '$sig$key$next';
      edges.putIfAbsent(
          edgeKey, () => _DraftEdge(fromId: fromId, key: key, toId: toId));
      sig = next;
    }
    if (replayFailed) continue;
    // Expand each state once; BFS reaches it first by its shortest path.
    if (!expanded.add(sig)) continue;
    if (path.length >= budget.maxDepth) continue;

    for (final key in _actionableKeys(tree)) {
      if (!allowDestructive && _isDestructive(key, destructiveKeywords)) {
        skipped.add(key);
        continue;
      }
      frontier.add([...path, key]);
    }
  }

  return CrawlResult(
    graph: _toGraph(nodes, edges.values, rootSig, module),
    statesDiscovered: nodes.length,
    actionsTried: actionsTried,
    skippedDestructive: skipped.toList()..sort(),
  );
}

/// Drift between a fresh crawl and the approved graph (ARCHITECTURE.md §11):
/// screens and actions that exist in the app but not in the model — coverage
/// decay made visible. Matched by route, since draft node ids are generated.
class DriftReport {
  const DriftReport({required this.newRoutes, required this.newActions});

  /// Routes the crawl found that no approved node declares.
  final List<String> newRoutes;

  /// `route --key-->` actions the crawl found that the approved graph lacks.
  final List<String> newActions;

  bool get hasDrift => newRoutes.isNotEmpty || newActions.isNotEmpty;
}

DriftReport driftReport(Graph discovered, Graph approved) {
  final approvedRoutes = {
    for (final n in approved.nodes)
      if (n.identity.route != null) n.identity.route!,
  };
  final approvedActions = <String>{
    for (final n in approved.nodes)
      for (final e in n.payload.edges)
        '${n.identity.route}${e.key ?? e.action.yaml}',
  };

  final newRoutes = <String>{};
  final newActions = <String>{};
  for (final n in discovered.nodes) {
    final route = n.identity.route;
    if (route != null && !approvedRoutes.contains(route)) {
      newRoutes.add(route);
    }
    for (final e in n.payload.edges) {
      final sig = '$route${e.key ?? e.action.yaml}';
      if (!approvedActions.contains(sig)) {
        newActions.add('$route --${e.key ?? e.action.yaml}-->');
      }
    }
  }
  return DriftReport(
    newRoutes: newRoutes.toList()..sort(),
    newActions: newActions.toList()..sort(),
  );
}

// --- internals --------------------------------------------------------------

class _DraftNode {
  _DraftNode({required this.id, required this.route});
  final String id;
  final String? route;
}

class _DraftEdge {
  const _DraftEdge(
      {required this.fromId, required this.key, required this.toId});
  final String fromId;
  final String key;
  final String toId;
}

String _signature(Fingerprint fp, WidgetTreeSnapshot tree) =>
    '${fp.route ?? ''}${layoutHash(tree)}';

String _uniqueId(String module, String? route, int n, Set<String> used) {
  final base = _routeSlug(route) ?? 's$n';
  var id = '$module.$base';
  // Loop a suffix until the id is genuinely unused — reusing the global counter
  // could collide with a different state whose slug already took that suffix,
  // silently collapsing two distinct states into one node id.
  for (var suffix = 2; used.contains(id); suffix++) {
    id = '$module.${base}_$suffix';
  }
  used.add(id);
  return id;
}

String? _routeSlug(String? route) {
  if (route == null || route.isEmpty) return null;
  final slug = route
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  return slug.isEmpty ? 'root' : slug;
}

List<String> _actionableKeys(WidgetTreeSnapshot tree) {
  final keys = <String>{};
  void visit(SerializedWidget w) {
    if (w.key != null && w.key!.isNotEmpty) keys.add(w.key!);
    for (final child in w.children) {
      visit(child);
    }
  }

  visit(tree.root);
  return keys.toList()..sort();
}

bool _isDestructive(String key, Set<String> keywords) =>
    _tokens(key).any(keywords.contains);

/// Splits a widget key into lowercase word tokens on non-alphanumeric
/// separators and camelCase boundaries, so destructive matching is by word, not
/// substring (`reorder`/`border`/`buyer` ≠ `order`/`buy`).
List<String> _tokens(String key) {
  final spaced = key
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase();
  return [
    for (final token in spaced.split(' '))
      if (token.isNotEmpty) token,
  ];
}

Graph _toGraph(
  Map<String, _DraftNode> nodes,
  Iterable<_DraftEdge> edges,
  String? rootSig,
  String module,
) {
  final edgesByFrom = <String, List<Edge>>{};
  for (final e in edges) {
    (edgesByFrom[e.fromId] ??= []).add(
      Edge(action: EdgeAction.tap, target: e.toId, key: e.key),
    );
  }
  final graphNodes = [
    for (final node in nodes.values)
      Node(
        id: node.id,
        identity: NodeIdentity(route: node.route),
        payload: NodePayload(edges: edgesByFrom[node.id] ?? const []),
      ),
  ];
  final rootId = rootSig == null ? null : nodes[rootSig]?.id;
  return Graph(
    nodes: graphNodes,
    entryNodeIds: [if (rootId != null) rootId],
  );
}
