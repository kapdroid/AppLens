import 'package:yaml/yaml.dart';

import '../model/assertion.dart';
import '../model/edge.dart';
import '../model/edge_action.dart';
import '../model/flag_constraint.dart';
import '../model/graph.dart';
import '../model/node.dart';
import '../util/source_location.dart';

/// Thrown when YAML cannot be parsed into a model, carrying the precise
/// location so a failure points straight at `file:line:col` (ARCHITECTURE.md §5).
class GraphParseException implements Exception {
  GraphParseException(this.message, this.location);

  final String message;
  final SourceLocation location;

  @override
  String toString() => '$location: $message';
}

/// A reusable partial node loaded from `shared/`, merged into nodes that
/// `include` it before validation (ARCHITECTURE.md §5).
class NodeFragment {
  const NodeFragment({
    this.anchors = const [],
    this.flags = const {},
    this.assertions = const [],
    this.tags = const [],
  });

  final List<String> anchors;
  final Map<String, FlagConstraint> flags;
  final List<Assertion> assertions;
  final List<String> tags;
}

/// Parses a node document. [assignedId] (the loader's location-derived id) wins;
/// if the document also declares an `id`, it must match.
Node parseNode(String yamlText, {required String source, String? assignedId}) {
  final map = _loadMap(yamlText, source);
  final reader = _Reader(map, source);

  final declaredId = reader.optString('id');
  if (assignedId != null && declaredId != null && declaredId != assignedId) {
    reader.fail(
      'node id "$declaredId" does not match its location-derived id "$assignedId"',
      map,
    );
  }
  final id = assignedId ?? declaredId;
  if (id == null) {
    reader.fail('node is missing "id" and none was assigned', map);
  }

  return Node(
    id: id,
    identity: _parseIdentity(reader),
    payload: _parsePayload(reader),
    includes: reader.stringList('includes'),
    source: reader.locationOf(map),
  );
}

/// Parses a `shared/` fragment into the additive pieces the loader merges.
NodeFragment parseFragment(String yamlText, {required String source}) {
  final map = _loadMap(yamlText, source);
  final reader = _Reader(map, source);

  final identity = reader.mapOf('identity');
  final payload = reader.mapOf('payload');
  final identityReader = identity == null ? null : _Reader(identity, source);
  final payloadReader = payload == null ? null : _Reader(payload, source);

  return NodeFragment(
    anchors: identityReader?.stringList('anchors') ?? const [],
    flags: identityReader == null ? const {} : _parseFlags(identityReader),
    assertions:
        payloadReader == null ? const [] : _parseAssertions(payloadReader),
    tags: payloadReader?.stringList('tags') ?? const [],
  );
}

/// Parses a `<module>.module.yaml` manifest. [moduleName] qualifies bare entry
/// node names into hierarchical ids.
ModuleManifest parseModuleManifest(
  String yamlText, {
  required String source,
  required String moduleName,
}) {
  final map = _loadMap(yamlText, source);
  final reader = _Reader(map, source);
  final entries = reader.stringList('entry_nodes');
  return ModuleManifest(
    name: moduleName,
    owner: reader.optString('owner'),
    tags: reader.stringList('tags'),
    entryNodes: [
      for (final entry in entries)
        entry.contains('.') ? entry : '$moduleName.$entry',
    ],
  );
}

NodeIdentity _parseIdentity(_Reader reader) {
  final identity = reader.mapOf('identity');
  if (identity == null) {
    return const NodeIdentity();
  }
  final r = _Reader(identity, reader.source);
  return NodeIdentity(
    route: r.optString('route'),
    anchors: r.stringList('anchors'),
    flags: _parseFlags(r),
    overlay: r.boolOr('overlay', fallback: false),
  );
}

Map<String, FlagConstraint> _parseFlags(_Reader reader) {
  final flagsMap = reader.mapOf('flags');
  if (flagsMap == null) {
    return const {};
  }
  final flags = <String, FlagConstraint>{};
  flagsMap.nodes.forEach((key, valueNode) {
    flags[(key as Object).toString()] = FlagConstraint.parse(
      _flagRaw(valueNode.value),
    );
  });
  return flags;
}

String _flagRaw(Object? value) => switch (value) {
      final bool b => b ? 'true' : 'false',
      final int i => i.toString(),
      final String s => s,
      _ => '$value',
    };

NodePayload _parsePayload(_Reader reader) {
  final payload = reader.mapOf('payload');
  if (payload == null) {
    return const NodePayload();
  }
  final r = _Reader(payload, reader.source);
  return NodePayload(
    assertions: _parseAssertions(r),
    visualBaselines: _parseBaselines(r),
    edges: _parseEdges(r),
    guard: _parseGuard(r),
    tags: r.stringList('tags'),
    owner: r.optString('owner'),
  );
}

List<Assertion> _parseAssertions(_Reader reader) {
  final list = reader.listOf('assertions');
  if (list == null) {
    return const [];
  }
  return [
    for (final item in list.nodes)
      _parseAssertion(reader.asMap(item, 'assertion'), reader.source),
  ];
}

Assertion _parseAssertion(YamlMap map, String source) {
  final reader = _Reader(map, source);
  final type = reader.requireString('type');
  final args = <String, Object?>{};
  map.nodes.forEach((key, valueNode) {
    final name = (key as Object).toString();
    if (name != 'type') {
      args[name] = _plain(valueNode.value);
    }
  });
  return Assertion(type: type, args: args);
}

List<Edge> _parseEdges(_Reader reader) {
  final list = reader.listOf('edges');
  if (list == null) {
    return const [];
  }
  return [
    for (final item in list.nodes)
      _parseEdge(reader.asMap(item, 'edge'), reader.source),
  ];
}

Edge _parseEdge(YamlMap map, String source) {
  final reader = _Reader(map, source);
  final actionName = reader.requireString('action');
  final action = EdgeAction.fromYaml(actionName);
  if (action == null) {
    reader.fail('unknown edge action "$actionName"', map);
  }
  return Edge(
    action: action,
    target: reader.requireString('target'),
    key: reader.optString('key'),
    text: reader.optString('text'),
    uri: reader.optString('uri'),
  );
}

Guard? _parseGuard(_Reader reader) {
  final guards = reader.mapOf('guards');
  if (guards == null) {
    return null;
  }
  return Guard(requires: _Reader(guards, reader.source).stringList('requires'));
}

List<VisualBaseline> _parseBaselines(_Reader reader) {
  final list = reader.listOf('visual_baselines');
  if (list == null) {
    return const [];
  }
  return [
    for (final item in list.nodes)
      _parseBaseline(reader.asMap(item, 'visual_baseline'), reader.source),
  ];
}

VisualBaseline _parseBaseline(YamlMap map, String source) {
  final reader = _Reader(map, source);
  final contextMap = reader.mapOf('context');
  final contextReader = contextMap == null ? null : _Reader(contextMap, source);
  final captureName =
      reader.optString('capture') ?? CaptureKind.fullScreen.yaml;
  final stateName = reader.optString('state') ?? BaselineState.proposed.name;
  return VisualBaseline(
    context: BaselineContext(
      device: contextReader?.optString('device') ?? '',
      locale: contextReader?.optString('locale') ?? '',
      theme: contextReader?.optString('theme') ?? '',
    ),
    capture: CaptureKind.fromYaml(captureName) ?? CaptureKind.fullScreen,
    state: BaselineState.fromYaml(stateName) ?? BaselineState.proposed,
    widget: reader.optString('widget'),
    image: reader.optString('image'),
    mask: reader.optString('mask'),
    threshold: reader.optDouble('threshold'),
    approvedBy: reader.optString('approved_by'),
    reasonPr: reader.optString('reason_pr'),
    replaced: reader.optString('replaced'),
  );
}

Object? _plain(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.nodes.entries)
        (entry.key as Object).toString(): _plain(entry.value.value),
    };
  }
  if (value is YamlList) {
    return [for (final item in value.nodes) _plain(item.value)];
  }
  return value;
}

YamlMap _loadMap(String text, String source) {
  final YamlNode node;
  try {
    node = loadYamlNode(text);
  } on YamlException catch (error) {
    final start = error.span?.start;
    throw GraphParseException(
      error.message,
      SourceLocation(
        source: source,
        line: (start?.line ?? 0) + 1,
        column: (start?.column ?? 0) + 1,
      ),
    );
  }
  if (node is! YamlMap) {
    throw GraphParseException(
      'expected a YAML map at the top level',
      SourceLocation(source: source, line: 1, column: 1),
    );
  }
  return node;
}

/// Typed, span-aware accessors over a [YamlMap] that fail with precise
/// locations instead of throwing opaque casts.
class _Reader {
  _Reader(this.map, this.source);

  final YamlMap map;
  final String source;

  SourceLocation locationOf(YamlNode node) {
    final start = node.span.start;
    return SourceLocation(
      source: source,
      line: start.line + 1,
      column: start.column + 1,
    );
  }

  Never fail(String message, YamlNode node) =>
      throw GraphParseException(message, locationOf(node));

  YamlNode? _node(String key) => map.nodes[key];

  String requireString(String key) {
    final node = _node(key);
    if (node == null) {
      fail('missing required key "$key"', map);
    }
    final value = node.value;
    if (value is! String) {
      fail('"$key" must be a string', node);
    }
    return value;
  }

  String? optString(String key) {
    final node = _node(key);
    if (node == null) {
      return null;
    }
    final value = node.value;
    if (value is! String) {
      fail('"$key" must be a string', node);
    }
    return value;
  }

  bool boolOr(String key, {required bool fallback}) {
    final node = _node(key);
    if (node == null) {
      return fallback;
    }
    final value = node.value;
    if (value is! bool) {
      fail('"$key" must be a boolean', node);
    }
    return value;
  }

  double? optDouble(String key) {
    final node = _node(key);
    if (node == null) {
      return null;
    }
    final value = node.value;
    if (value is! num) {
      fail('"$key" must be a number', node);
    }
    return value.toDouble();
  }

  List<String> stringList(String key) {
    final node = _node(key);
    if (node == null) {
      return const [];
    }
    if (node is! YamlList) {
      fail('"$key" must be a list', node);
    }
    final result = <String>[];
    for (final item in node.nodes) {
      final value = item.value;
      if (value is! String) {
        fail('"$key" entries must be strings', item);
      }
      result.add(value);
    }
    return result;
  }

  YamlMap? mapOf(String key) {
    final node = _node(key);
    if (node == null) {
      return null;
    }
    if (node is! YamlMap) {
      fail('"$key" must be a map', node);
    }
    return node;
  }

  YamlList? listOf(String key) {
    final node = _node(key);
    if (node == null) {
      return null;
    }
    if (node is! YamlList) {
      fail('"$key" must be a list', node);
    }
    return node;
  }

  YamlMap asMap(YamlNode node, String what) {
    if (node is! YamlMap) {
      fail('each $what must be a map', node);
    }
    return node;
  }
}
