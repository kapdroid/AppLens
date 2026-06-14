import 'dart:io';

import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

/// Finds the repo directory that contains [relative], walking up from the test's
/// working directory so the test works whether run from the package or the root.
Directory _repoDirContaining(String relative) {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/$relative').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'cannot locate "$relative" from ${Directory.current.path}');
    }
    dir = parent;
  }
}

void main() {
  const relativeGraph = 'examples/stranger_app/qa_graph';
  late Graph graph;

  setUpAll(() {
    final root = _repoDirContaining(relativeGraph);
    graph = loadGraph('${root.path}/$relativeGraph');
  });

  test('loads every node across all modules with hierarchical ids', () {
    expect(graph.nodes.map((node) => node.id).toSet(), {
      'shop.dashboard',
      'shop.catalog',
      'shop.product',
      'shop.cart',
      'shop.confirm',
      'account.login',
      'account.profile',
      'account.orders',
      'support.help',
      'support.settings',
    });
  });

  test('a cross-module edge keeps its qualified target', () {
    final dashboard = graph.byId['shop.dashboard']!;
    expect(
      dashboard.payload.edges.map((e) => e.target),
      contains('account.login'),
    );
  });

  test('entry nodes come from the module manifest, module-qualified', () {
    expect(graph.entryNodeIds, ['shop.dashboard']);
  });

  test('includes are resolved into identity and payload (composition)', () {
    final dashboard = graph.byId['shop.dashboard']!;
    expect(dashboard.identity.anchors, contains('app_bar'));
    expect(
      dashboard.payload.assertions.any((a) => a.args['key'] == 'app_bar'),
      isTrue,
    );
  });

  test('bare edge targets are qualified to the module', () {
    final dashboard = graph.byId['shop.dashboard']!;
    expect(
        dashboard.payload.edges.map((e) => e.target), contains('shop.catalog'));
  });

  test('the hand-written stranger graph validates with no errors', () {
    final errors = validateGraph(graph).where((d) => d.isError).toList();
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('every node round-trips through serialize → parse', () {
    for (final node in graph.nodes) {
      final once = writeYaml(node.toMap());
      final twice = writeYaml(
        parseNode(once, source: node.id, assignedId: node.id).toMap(),
      );
      expect(twice, once, reason: 'round-trip failed for ${node.id}');
    }
  });

  test('the content hash is a sha256 stable across node ordering', () {
    final reordered = Graph(
      nodes: graph.nodes.reversed.toList(),
      entryNodeIds: graph.entryNodeIds,
    );
    expect(graph.contentHash, startsWith('sha256:'));
    expect(reordered.contentHash, graph.contentHash);
  });

  test('a deliberately ambiguous module fails validation', () {
    final tmp = Directory.systemTemp.createTempSync('applens_ambiguous_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final nodes = Directory('${tmp.path}/modules/dup/nodes')
      ..createSync(recursive: true);
    File(
      '${tmp.path}/modules/dup/dup.module.yaml',
    ).writeAsStringSync('entry_nodes: [one]\n');
    File('${nodes.path}/one.yaml').writeAsStringSync(
      'identity:\n'
      '  route: /same\n'
      '  anchors: [a]\n'
      'payload:\n'
      '  edges:\n'
      '    - { action: tap, key: a, target: two }\n',
    );
    File('${nodes.path}/two.yaml').writeAsStringSync(
      'identity:\n'
      '  route: /same\n'
      '  anchors: [b]\n',
    );

    final ambiguous = loadGraph(tmp.path);
    final codes = validateGraph(ambiguous).map((d) => d.code);
    expect(codes, contains('fingerprint_ambiguity'));
  });
}
