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
    final cart = plan.alternateInboundPaths['shop.cart'];
    expect(cart, isNotNull);
    expect(cart!.length, greaterThanOrEqualTo(2));
    for (final path in cart) {
      expect(graph.entryNodeIds, contains(path.start));
      expect(path.visited.last, 'shop.cart');
    }
    final routes = cart.map((path) => path.visited.join('>')).toSet();
    expect(routes.length, cart.length, reason: 'alternates should be distinct');
  });

  test('impact covers the changed screen and every edge into it', () {
    final plan = compilePlan(
      graph,
      strategy: PlanStrategy.impact,
      changedNodeIds: {'shop.cart'},
    );
    // Every path targets the affected screen — nothing beyond it.
    expect(plan.paths, isNotEmpty);
    for (final path in plan.paths) {
      expect(path.visited.last, 'shop.cart');
      expect(path.start, isIn(graph.entryNodeIds));
    }
    // The two ways into the cart (from the dashboard and from a product) are
    // both exercised — §6 "every edge into them".
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

  test('soak is still an unimplemented stub', () {
    expect(
      () => compilePlan(graph, strategy: PlanStrategy.soak),
      throwsUnimplementedError,
    );
  });

  test('a compiled plan serializes to valid, structured YAML', () {
    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    final document = loadYaml(writeYaml(plan.toMap())) as YamlMap;
    expect(document['strategy'], 'smoke');
    expect(document['graph_hash'], startsWith('sha256:'));
    expect(document['paths'], isA<YamlList>());
  });
}
