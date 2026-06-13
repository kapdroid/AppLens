import 'dart:io';

import '../model/graph.dart';
import '../model/node.dart';
import '../parse/graph_parser.dart';
import '../util/source_location.dart';

/// Loads a graph from a module-mirrored `qa_graph` directory (ARCHITECTURE.md
/// §5): walks `modules/*/nodes/*.yaml`, assigns hierarchical ids
/// (`<module>.<file>`), reads each `<module>.module.yaml` manifest for entry
/// nodes, and resolves `includes:` from `shared/` fragments before returning.
///
/// Composition is resolve-then-validate: fragments are merged into node
/// identities here, so `validateGraph` still catches an ambiguity introduced by
/// an included fragment.
Graph loadGraph(String qaGraphDir) {
  final modulesDir = Directory('$qaGraphDir/modules');
  if (!modulesDir.existsSync()) {
    throw GraphParseException(
      'no modules/ directory found',
      SourceLocation(source: modulesDir.path, line: 1, column: 1),
    );
  }

  final nodes = <Node>[];
  final manifests = <ModuleManifest>[];
  final entryNodeIds = <String>[];

  final moduleDirs = modulesDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final moduleDir in moduleDirs) {
    final moduleName = _basename(moduleDir.path);

    final manifestFile = File('${moduleDir.path}/$moduleName.module.yaml');
    if (manifestFile.existsSync()) {
      final manifest = parseModuleManifest(
        manifestFile.readAsStringSync(),
        source: manifestFile.path,
        moduleName: moduleName,
      );
      manifests.add(manifest);
      entryNodeIds.addAll(manifest.entryNodes);
    }

    final nodesDir = Directory('${moduleDir.path}/nodes');
    if (!nodesDir.existsSync()) {
      continue;
    }
    final nodeFiles = nodesDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yaml'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in nodeFiles) {
      final base = _basename(file.path).replaceAll(RegExp(r'\.yaml$'), '');
      final id = '$moduleName.$base';
      var node = parseNode(
        file.readAsStringSync(),
        source: file.path,
        assignedId: id,
      );
      node = _resolveIncludes(node, qaGraphDir);
      node = _qualifyEdgeTargets(node, moduleName);
      nodes.add(node);
    }
  }

  return Graph(nodes: nodes, entryNodeIds: entryNodeIds, modules: manifests);
}

Node _resolveIncludes(Node node, String qaGraphDir) {
  if (node.includes.isEmpty) {
    return node;
  }
  final anchors = [...node.identity.anchors];
  final flags = {...node.identity.flags};
  final assertions = [...node.payload.assertions];
  final tags = [...node.payload.tags];

  for (final ref in node.includes) {
    final file = File('$qaGraphDir/$ref.yaml');
    if (!file.existsSync()) {
      throw GraphParseException(
        'include "$ref" not found at ${file.path}',
        node.source ?? SourceLocation(source: ref, line: 1, column: 1),
      );
    }
    final fragment = parseFragment(file.readAsStringSync(), source: file.path);
    for (final anchor in fragment.anchors) {
      if (!anchors.contains(anchor)) {
        anchors.add(anchor);
      }
    }
    fragment.flags.forEach((key, value) {
      flags.putIfAbsent(key, () => value); // the node's own flags win
    });
    assertions.addAll(fragment.assertions);
    for (final tag in fragment.tags) {
      if (!tags.contains(tag)) {
        tags.add(tag);
      }
    }
  }

  return node.copyWith(
    identity: node.identity.copyWith(anchors: anchors, flags: flags),
    payload: node.payload.copyWith(assertions: assertions, tags: tags),
  );
}

Node _qualifyEdgeTargets(Node node, String moduleName) {
  final edges = node.payload.edges;
  if (edges.every((edge) => edge.target.contains('.'))) {
    return node;
  }
  return node.copyWith(
    payload: node.payload.copyWith(
      edges: [
        for (final edge in edges)
          edge.target.contains('.')
              ? edge
              : edge.withTarget('$moduleName.${edge.target}'),
      ],
    ),
  );
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
