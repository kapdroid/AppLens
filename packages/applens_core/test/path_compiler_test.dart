import 'dart:io';

import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Directory _repoDirContaining(String relative) {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/$relative').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'cannot locate "$relative" from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

Set<String> _edgeSignatures(Graph graph) {
  final edges = <String>{};
  for (final node in graph.nodes) {
    for (final edge in node.payload.edges) {
      if (graph.byId.containsKey(edge.target)) {
        edges.add('${node.id}|${edge.action.yaml}|${edge.target}');
      }
    }
  }
  return edges;
}

Set<String> _traversedSignatures(Plan plan) {
  final traversed = <String>{};
  for (final path in plan.paths) {
    var from = path.start;
    for (final step in path.steps) {
      traversed.add('$from|${step.action.yaml}|${step.to}');
      from = step.to;
    }
  }
  return traversed;
}

void main() {
  late Graph graph;

  setUpAll(() {
    final root = _repoDirContaining('examples/stranger_app/qa_graph');
    graph = loadGraph('${root.path}/examples/stranger_app/qa_graph');
  });

  test('smoke plan visits every tagged (sanity) node', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    final visited = {for (final path in plan.paths) ...path.visited};
    final tagged = graph.nodes
        .where((node) => node.payload.tags.contains('sanity'))
        .map((node) => node.id)
        .toSet();
    expect(tagged, isNotEmpty);
    expect(
      visited.containsAll(tagged),
      isTrue,
      reason: 'visited=$visited tagged=$tagged',
    );
  });

  test('every smoke path starts at an entry node', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    for (final path in plan.paths) {
      expect(graph.entryNodeIds, contains(path.start));
    }
  });

  test('regression plan covers every edge', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.regression);
    final traversed = _traversedSignatures(plan);
    final edges = _edgeSignatures(graph);
    expect(edges, isNotEmpty);
    expect(
      traversed.containsAll(edges),
      isTrue,
      reason: 'uncovered=${edges.difference(traversed)}',
    );
  });

  test('a plan embeds the source graph content hash', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    expect(plan.graphHash, graph.contentHash);
  });

  test('same graph + strategy + seed → byte-identical plan', () {
    for (final strategy in [PlanStrategy.smoke, PlanStrategy.regression]) {
      final first =
          writeYaml(compilePlan(graph, strategy: strategy, seed: 7).toMap());
      final second =
          writeYaml(compilePlan(graph, strategy: strategy, seed: 7).toMap());
      expect(second, first, reason: '${strategy.yaml} is not deterministic');
    }
  });

  test('a multi-inbound node has distinct alternate inbound paths', () {
    final plan =
        compilePlan(graph, strategy: PlanStrategy.smoke, alternates: 3);
    // The catalog is reached several ways — directly from the dashboard, and
    // by backing out of a product or the cart — so it has distinct alternates.
    final catalog = plan.alternateInboundPaths['shop.catalog'];
    expect(catalog, isNotNull);
    expect(catalog!.length, greaterThanOrEqualTo(2));
    for (final path in catalog) {
      expect(graph.entryNodeIds, contains(path.start));
      expect(path.visited.last, 'shop.catalog');
    }
    final routes = catalog.map((path) => path.visited.join('>')).toSet();
    expect(routes.length, catalog.length,
        reason: 'alternates should be distinct');
  });

  test('impact covers the changed screen and every edge into it', () {
    // The cart screen has two state nodes (empty / filled) on the same route;
    // a change to it touches both. Reached two distinct ways: "view cart" from
    // the dashboard lands on the empty cart, "add to cart" from a product on
    // the filled one — both must be exercised (§6 "every edge into them").
    final plan = compilePlan(
      graph,
      strategy: PlanStrategy.impact,
      changedNodeIds: {'shop.cart', 'shop.cart_empty'},
    );
    // Every path targets an affected screen — nothing beyond it.
    expect(plan.paths, isNotEmpty);
    for (final path in plan.paths) {
      expect(path.visited.last, isIn(['shop.cart', 'shop.cart_empty']));
      expect(path.start, isIn(graph.entryNodeIds));
    }
    final inboundKeys = {
      for (final path in plan.paths)
        if (path.steps.isNotEmpty) path.steps.last.key,
    };
    expect(inboundKeys, containsAll(['btn_view_cart', 'btn_add_to_cart']));
    // The downstream confirm screen is never run.
    expect(
      plan.paths.expand((p) => p.visited),
      isNot(contains('shop.confirm')),
    );
  });

  test('impact with no changed nodes plans nothing', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.impact);
    expect(plan.paths, isEmpty);
  });

  test('impact covers parallel inbound edges (same source, different action)',
      () {
    // Two ways from the dashboard into the catalog: a tap and a long-press.
    final parallel = Graph(
      nodes: [
        Node(
          id: 'shop.dashboard',
          identity: const NodeIdentity(route: '/'),
          payload: const NodePayload(edges: [
            Edge(action: EdgeAction.tap, target: 'shop.catalog', key: 'btn_go'),
            Edge(
                action: EdgeAction.longPress,
                target: 'shop.catalog',
                key: 'btn_go'),
          ]),
        ),
        Node(
            id: 'shop.catalog',
            identity: const NodeIdentity(route: '/catalog'),
            payload: const NodePayload()),
      ],
      entryNodeIds: const ['shop.dashboard'],
    );
    final plan = compilePlan(parallel,
        strategy: PlanStrategy.impact, changedNodeIds: {'shop.catalog'});

    expect(
        plan.paths, hasLength(2)); // both inbound edges, not collapsed to one
    expect(
      plan.paths.map((p) => p.steps.last.action).toSet(),
      {EdgeAction.tap, EdgeAction.longPress},
    );

    // The same edges, as alternates, collapse to one distinct route.
    final smoke = compilePlan(parallel, strategy: PlanStrategy.smoke);
    expect(smoke.alternateInboundPaths['shop.catalog'], hasLength(1));
  });

  test('impact distinguishes edges whose operands would collide under a slash',
      () {
    // Two distinct enter_text edges whose (key, text) fields join identically
    // if you concatenate with "/": ('a','b/c') and ('a/b','c') both flatten to
    // "...a/b/c". The unit-separator key keeps them distinct so neither way in
    // is silently dropped (§6 "every edge into it").
    final collide = Graph(
      nodes: [
        Node(
          id: 'shop.dashboard',
          identity: const NodeIdentity(route: '/'),
          payload: const NodePayload(edges: [
            Edge(
                action: EdgeAction.enterText,
                target: 'shop.catalog',
                key: 'a',
                text: 'b/c'),
            Edge(
                action: EdgeAction.enterText,
                target: 'shop.catalog',
                key: 'a/b',
                text: 'c'),
          ]),
        ),
        Node(
            id: 'shop.catalog',
            identity: const NodeIdentity(route: '/catalog'),
            payload: const NodePayload()),
      ],
      entryNodeIds: const ['shop.dashboard'],
    );
    final plan = compilePlan(collide,
        strategy: PlanStrategy.impact, changedNodeIds: {'shop.catalog'});

    expect(plan.paths, hasLength(2)); // not collapsed by a delimiter collision
    expect(
      plan.paths.map((p) => (p.steps.last.key, p.steps.last.text)).toSet(),
      {('a', 'b/c'), ('a/b', 'c')},
    );
  });

  test('impact is deterministic: same change set → byte-identical plan', () {
    String compile() => writeYaml(compilePlan(
          graph,
          strategy: PlanStrategy.impact,
          changedNodeIds: {'shop.cart', 'shop.product'},
        ).toMap());
    expect(compile(), compile());
  });

  test('nodeIdsInModules expands a module to its node ids', () {
    final ids = nodeIdsInModules(graph, {'shop'});
    expect(ids, contains('shop.cart'));
    expect(ids.every((id) => id.startsWith('shop.')), isTrue);
    expect(nodeIdsInModules(graph, {'nonexistent'}), isEmpty);
  });

  group('soak', () {
    test('splits the budget into entry-rooted segments (resilience)', () {
      // 20 steps / 8-per-segment = 3 segments, each its own path from an entry —
      // so a failure in one segment can't block the others when walked.
      final plan =
          compilePlan(graph, strategy: PlanStrategy.soak, soakSteps: 20);
      expect(plan.paths, hasLength(3));
      var total = 0;
      for (final path in plan.paths) {
        expect(graph.entryNodeIds, contains(path.start));
        total += path.steps.length;
        // Every step follows a real edge from the previous node to its target.
        var current = path.start;
        for (final step in path.steps) {
          final edges = graph.byId[current]!.payload.edges;
          expect(
              edges.any((e) => e.action == step.action && e.target == step.to),
              isTrue,
              reason: 'step $current → ${step.to} must be a declared edge');
          current = step.to;
        }
      }
      expect(total, 20, reason: 'segments cover the full budget');
    });

    test('is reproducible: same seed → byte-identical plan', () {
      final a = compilePlan(graph, strategy: PlanStrategy.soak, seed: 7);
      final b = compilePlan(graph, strategy: PlanStrategy.soak, seed: 7);
      expect(writeYaml(a.toMap()), writeYaml(b.toMap()));
    });

    test('explores: visits more than one distinct edge, sharing visit counts',
        () {
      // Least-visited bias (shared across segments) fans out across edges
      // rather than looping a single hot path.
      final plan = compilePlan(graph,
          strategy: PlanStrategy.soak, soakSteps: 30, seed: 1);
      final distinctTargets = {
        for (final path in plan.paths)
          for (final s in path.steps) s.to
      }.length;
      expect(distinctTargets, greaterThan(1));
    });
  });

  test('a compiled plan serializes to valid, structured YAML', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    final document = loadYaml(writeYaml(plan.toMap())) as YamlMap;
    expect(document['strategy'], 'smoke');
    expect(document['graph_hash'], startsWith('sha256:'));
    expect(document['paths'], isA<YamlList>());
  });
}
