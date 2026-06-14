import 'package:applens_core/applens_core.dart';

import 'degrade.dart';
import 'provider.dart';
import 'schema.dart';

/// The schema an author draft must validate against — a set of proposed nodes
/// with identity, tier-1 assertions, and edges. Provider-neutral, like triage.
const authorNodeSchema = <String, Object?>{
  'type': 'object',
  'required': ['nodes'],
  'properties': {
    'nodes': {
      'type': 'array',
      'items': {
        'type': 'object',
        'required': ['id'],
        'properties': {
          'id': {'type': 'string'},
          'route': {'type': 'string', 'nullable': true},
          'anchors': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'assertions': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'edges': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    },
  },
};

/// The author prompt, versioned in-repo and provider-neutral (ARCHITECTURE.md
/// §12). Authoring turns a prose test case into a draft graph a human refines.
const authorSystemPrompt = '''
You are AppLens author. Turn the user's prose test case into a draft set of
qa_graph nodes for a Flutter app. Each node is a screen/state with:
- id: a short snake_case name (the module is added by the tool).
- route: the screen's route if known, else null.
- anchors: widget keys that identify the screen.
- assertions: tier-1 checks, e.g. {"type":"widget_exists","key":"btn_x"} or
  {"type":"text_equals","key":"lbl_y","value":"Hello"}.
- edges: actions to other nodes, e.g. {"action":"tap","key":"btn_x","target":"other_id"}.
This is a draft a human will prune and approve — prefer fewer, well-named nodes.
Reply only with JSON matching the required schema.
''';

/// Drafts a graph from a prose [testCase] via [provider] (BYO-key, any vendor,
/// or a human through ManualProvider). Schema-validated structured output — never
/// free text. The result is a *draft* a human refines and approves through a PR;
/// authoring proposes, it never gates (ARCHITECTURE.md §9/§12). Node ids and edge
/// targets are qualified into [module] so the draft is a module-mirrored graph.
Future<Graph> author(
  String testCase,
  LlmProvider provider, {
  String module = 'app',
}) async {
  final request = LlmRequest(
    messages: [
      const LlmMessage(LlmRole.system, authorSystemPrompt),
      LlmMessage(LlmRole.user, testCase),
    ],
    jsonSchema: authorNodeSchema,
  );
  final result = await provider
      .complete(degradeForCapabilities(request, provider.capabilities));
  // Defense in depth: re-validate before building the draft, so a non-validating
  // adapter surfaces an LlmException instead of crashing with a TypeError.
  final errors = validateAgainstSchema(result.json, authorNodeSchema);
  if (errors.isNotEmpty) {
    throw LlmException('author draft failed schema: ${errors.join('; ')}');
  }
  return _graphFromDraft(result.json, module);
}

String _qualify(String id, String module) =>
    id.contains('.') ? id : '$module.$id';

Graph _graphFromDraft(Map<String, Object?> json, String module) {
  final rawNodes = json['nodes']! as List;
  final nodes = <Node>[];
  for (final raw in rawNodes) {
    final m = (raw as Map).cast<String, Object?>();
    final assertions = [
      for (final a in (m['assertions'] as List? ?? const []))
        _assertion((a as Map).cast<String, Object?>()),
    ];
    final edges = [
      for (final e in (m['edges'] as List? ?? const []))
        if (((e as Map)['target'] as String?)?.isNotEmpty ?? false)
          _edge(e.cast<String, Object?>(), module),
    ];
    nodes.add(Node(
      id: _qualify(m['id']! as String, module),
      identity: NodeIdentity(
        route: m['route'] as String?,
        anchors: [for (final a in (m['anchors'] as List? ?? const [])) '$a'],
      ),
      payload: NodePayload(assertions: assertions, edges: edges),
    ));
  }
  return Graph(
    nodes: nodes,
    entryNodeIds: [if (nodes.isNotEmpty) nodes.first.id],
  );
}

Assertion _assertion(Map<String, Object?> m) => Assertion(
      type: m['type']! as String,
      args: {
        for (final entry in m.entries)
          if (entry.key != 'type') entry.key: entry.value,
      },
    );

Edge _edge(Map<String, Object?> m, String module) => Edge(
      action: EdgeAction.fromYaml(m['action'] as String? ?? 'tap') ??
          EdgeAction.tap,
      target: _qualify(m['target'] as String? ?? '', module),
      key: m['key'] as String?,
      text: m['text'] as String?,
    );
