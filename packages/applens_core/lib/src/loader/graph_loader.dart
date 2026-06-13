import '../model/graph.dart';
import '../model/node.dart';
import '../parse/graph_parser.dart';
import '../util/source_location.dart';
import 'graph_files.dart';

/// Loads a graph from a module-mirrored `qa_graph` directory (ARCHITECTURE.md
/// §5): walks `modules/*/nodes/*.yaml`, assigns hierarchical ids
/// (`<module>.<file>`), reads each `<module>.module.yaml` manifest for entry
/// nodes, and resolves `includes:` from `shared/` fragments before returning.
///
/// [files] abstracts file access — the default reads the host filesystem; an
/// on-device run passes a [MapGraphFiles] of pre-loaded bundled assets.
/// Composition is resolve-then-validate: fragments are merged into node
/// identities here, so `validateGraph` still catches an ambiguity introduced by
/// an included fragment.
Graph loadGraph(String qaGraphDir, {GraphFiles files = const IoGraphFiles()}) {
  final modulesDir = '$qaGraphDir/modules';
  if (!files.exists(modulesDir)) {
    throw GraphParseException(
      'no modules/ directory found',
      SourceLocation(source: modulesDir, line: 1, column: 1),
    );
  }

  final nodes = <Node>[];
  final manifests = <ModuleManifest>[];
  final entryNodeIds = <String>[];

  for (final moduleDir in files.listDirs(modulesDir)) {
    final moduleName = _basename(moduleDir);

    final manifestPath = '$moduleDir/$moduleName.module.yaml';
    if (files.exists(manifestPath)) {
      final manifest = parseModuleManifest(
        files.read(manifestPath),
        source: manifestPath,
        moduleName: moduleName,
      );
      manifests.add(manifest);
      entryNodeIds.addAll(manifest.entryNodes);
    }

    final nodesDir = '$moduleDir/nodes';
    if (!files.exists(nodesDir)) {
      continue;
    }
    final nodeFiles =
        files.listFiles(nodesDir).where((f) => f.endsWith('.yaml'));

    for (final path in nodeFiles) {
      final base = _basename(path).replaceAll(RegExp(r'\.yaml$'), '');
      final id = '$moduleName.$base';
      var node = parseNode(files.read(path), source: path, assignedId: id);
      node = _resolveIncludes(node, qaGraphDir, files);
      node = _qualifyEdgeTargets(node, moduleName);
      nodes.add(node);
    }
  }

  return Graph(nodes: nodes, entryNodeIds: entryNodeIds, modules: manifests);
}

Node _resolveIncludes(Node node, String qaGraphDir, GraphFiles files) {
  if (node.includes.isEmpty) {
    return node;
  }
  final anchors = [...node.identity.anchors];
  final flags = {...node.identity.flags};
  final assertions = [...node.payload.assertions];
  final tags = [...node.payload.tags];

  for (final ref in node.includes) {
    final path = '$qaGraphDir/$ref.yaml';
    if (!files.exists(path)) {
      throw GraphParseException(
        'include "$ref" not found at $path',
        node.source ?? SourceLocation(source: ref, line: 1, column: 1),
      );
    }
    final fragment = parseFragment(files.read(path), source: path);
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

String _basename(String path) => path.split('/').last;
