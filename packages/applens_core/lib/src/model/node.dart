import '../util/canonical.dart';
import '../util/source_location.dart';
import 'assertion.dart';
import 'edge.dart';
import 'flag_constraint.dart';

/// How the runner recognizes a node at runtime (ARCHITECTURE.md §4). Two nodes
/// whose identities cannot both be ruled out by some observable state are
/// fingerprint-ambiguous — see the validator.
class NodeIdentity {
  const NodeIdentity({
    this.route,
    this.anchors = const [],
    this.flags = const {},
    this.overlay = false,
  });

  /// Current route (e.g. `/order`); null means "any route".
  final String? route;

  /// Widget keys that must exist.
  final List<String> anchors;

  /// Flag predicates resolved via SDK introspection or UI inference.
  final Map<String, FlagConstraint> flags;

  /// True for dialogs/sheets that mount over a page.
  final bool overlay;

  NodeIdentity copyWith({
    List<String>? anchors,
    Map<String, FlagConstraint>? flags,
  }) =>
      NodeIdentity(
        route: route,
        anchors: anchors ?? this.anchors,
        flags: flags ?? this.flags,
        overlay: overlay,
      );

  Map<String, Object?> toMap() => compactMap({
        'route': route,
        'anchors': anchors,
        'flags': {
          for (final entry in flags.entries) entry.key: entry.value.raw
        },
        'overlay': overlay,
      });
}

/// A node precondition (ARCHITECTURE.md §4): state that must already hold for
/// the node to be reachable/meaningful.
class Guard {
  const Guard({this.requires = const []});

  final List<String> requires;

  Map<String, Object?> toMap() => {'requires': requires};
}

/// What to do and verify at a node (ARCHITECTURE.md §4).
class NodePayload {
  const NodePayload({
    this.assertions = const [],
    this.visualBaselines = const [],
    this.edges = const [],
    this.guard,
    this.tags = const [],
    this.owner,
  });

  final List<Assertion> assertions;
  final List<VisualBaseline> visualBaselines;
  final List<Edge> edges;
  final Guard? guard;
  final List<String> tags;
  final String? owner;

  NodePayload copyWith({
    List<Assertion>? assertions,
    List<Edge>? edges,
    List<String>? tags,
  }) =>
      NodePayload(
        assertions: assertions ?? this.assertions,
        visualBaselines: visualBaselines,
        edges: edges ?? this.edges,
        guard: guard,
        tags: tags ?? this.tags,
        owner: owner,
      );

  Map<String, Object?> toMap() => compactMap({
        'assertions': [for (final a in assertions) a.toMap()],
        'visual_baselines': [for (final b in visualBaselines) b.toMap()],
        'edges': [for (final e in edges) e.toMap()],
        'guards': guard?.toMap(),
        'tags': tags,
        'owner': owner,
      });
}

/// An equivalence class of app states: identity (how it is recognized) plus
/// payload (what to do and verify there). Execution history never lives here —
/// it belongs to the run store.
class Node {
  const Node({
    required this.id,
    required this.identity,
    required this.payload,
    this.includes = const [],
    this.source,
  });

  /// Hierarchical, globally unique id (e.g. `order.confirm`).
  final String id;

  final NodeIdentity identity;
  final NodePayload payload;

  /// Shared fragment references (e.g. `shared/overlays/sync_banner`), merged by
  /// the loader before validation.
  final List<String> includes;

  /// Where this node was parsed from, for diagnostics. Excluded from [toMap]
  /// and the content hash — it is provenance, not graph content.
  final SourceLocation? source;

  Node copyWith({NodeIdentity? identity, NodePayload? payload}) => Node(
        id: id,
        identity: identity ?? this.identity,
        payload: payload ?? this.payload,
        includes: includes,
        source: source,
      );

  Map<String, Object?> toMap() => compactMap({
        'id': id,
        'includes': includes,
        'identity': identity.toMap(),
        'payload': payload.toMap(),
      });
}
