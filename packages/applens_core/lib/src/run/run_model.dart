import 'dart:convert';
import 'dart:typed_data';

/// The outcome of visiting a node (ARCHITECTURE.md §7).
enum NodeOutcome {
  /// Reached the node and every assertion held.
  passed,

  /// An assertion mismatched but navigation worked — marked red, run continues.
  failedSoft,

  /// The expected node was unreachable — reroute via alternates is attempted.
  failedHard,

  /// Genuinely unreachable after reroute — distinct from failed in every report.
  blocked,

  /// Mismatches the approved baseline but matches an open proposal (Session 8).
  pending,
}

/// The result of evaluating one assertion.
class AssertionResult {
  const AssertionResult({
    required this.tierOrder,
    required this.type,
    required this.passed,
    this.skipped = false,
    this.detail = '',
  });

  final int tierOrder;
  final String type;
  final bool passed;

  /// True when this tier could not evaluate the assertion yet (recorded, never
  /// counted as a silent pass).
  final bool skipped;
  final String detail;

  Map<String, Object?> toMap() => {
        'tier_order': tierOrder,
        'type': type,
        'passed': passed,
        'skipped': skipped,
        'detail': detail,
      };

  factory AssertionResult.fromMap(Map<String, Object?> map) => AssertionResult(
        tierOrder: map['tier_order']! as int,
        type: map['type']! as String,
        passed: map['passed']! as bool,
        skipped: map['skipped'] as bool? ?? false,
        detail: map['detail'] as String? ?? '',
      );
}

/// Failure evidence recorded for a visit (never compared against anything).
class Artifact {
  const Artifact({required this.kind, required this.description, this.bytes});

  final String kind; // 'tree' | 'screenshot' | 'diff' | 'log'
  final String description;

  /// Binary payload (e.g. a tier-3 red diff PNG). Base64-encoded in [toMap] so
  /// it rides the same JSON transport device→host as the rest of the run.
  final Uint8List? bytes;

  Map<String, Object?> toMap() => {
        'kind': kind,
        'description': description,
        if (bytes != null) 'bytes_b64': base64Encode(bytes!),
      };

  factory Artifact.fromMap(Map<String, Object?> map) => Artifact(
        kind: map['kind']! as String,
        description: map['description']! as String,
        bytes: map['bytes_b64'] == null
            ? null
            : base64Decode(map['bytes_b64']! as String),
      );
}

/// A recorded visit to a node during a run.
class NodeVisit {
  const NodeVisit({
    required this.step,
    required this.expectedNodeId,
    required this.matchedNodeId,
    required this.outcome,
    this.assertions = const [],
    this.artifacts = const [],
  });

  final int step;
  final String expectedNodeId;

  /// The node actually matched; null when nothing known matched.
  final String? matchedNodeId;
  final NodeOutcome outcome;
  final List<AssertionResult> assertions;
  final List<Artifact> artifacts;

  /// True when the runner landed on a different known node than expected — the
  /// unexpected-transition event (ARCHITECTURE.md §7).
  bool get isUnexpectedTransition =>
      matchedNodeId != null && matchedNodeId != expectedNodeId;

  Map<String, Object?> toMap() => {
        'step': step,
        'expected_node_id': expectedNodeId,
        'matched_node_id': matchedNodeId,
        'outcome': outcome.name,
        'assertions': [for (final a in assertions) a.toMap()],
        'artifacts': [for (final a in artifacts) a.toMap()],
      };

  factory NodeVisit.fromMap(Map<String, Object?> map) => NodeVisit(
        step: map['step']! as int,
        expectedNodeId: map['expected_node_id']! as String,
        matchedNodeId: map['matched_node_id'] as String?,
        outcome: NodeOutcome.values.byName(map['outcome']! as String),
        assertions: [
          for (final a in (map['assertions'] as List? ?? const []))
            AssertionResult.fromMap((a as Map).cast<String, Object?>()),
        ],
        artifacts: [
          for (final a in (map['artifacts'] as List? ?? const []))
            Artifact.fromMap((a as Map).cast<String, Object?>()),
        ],
      );
}

/// A complete run record (ARCHITECTURE.md §13 schema:
/// runs · node_visits · assertion_results · artifacts).
class RunRecord {
  const RunRecord({
    required this.id,
    required this.strategy,
    required this.graphHash,
    required this.seed,
    this.visits = const [],
  });

  final String id;
  final String strategy;
  final String graphHash;
  final int seed;
  final List<NodeVisit> visits;

  Map<String, Object?> toMap() => {
        'id': id,
        'strategy': strategy,
        'graph_hash': graphHash,
        'seed': seed,
        'visits': [for (final v in visits) v.toMap()],
      };

  factory RunRecord.fromMap(Map<String, Object?> map) => RunRecord(
        id: map['id']! as String,
        strategy: map['strategy']! as String,
        graphHash: map['graph_hash']! as String,
        seed: map['seed']! as int,
        visits: [
          for (final v in (map['visits'] as List? ?? const []))
            NodeVisit.fromMap((v as Map).cast<String, Object?>()),
        ],
      );
}
