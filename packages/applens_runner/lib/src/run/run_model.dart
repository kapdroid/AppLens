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
}

/// Failure evidence recorded for a visit (never compared against anything).
class Artifact {
  const Artifact({required this.kind, required this.description});

  final String kind; // 'tree' | 'screenshot' | 'log'
  final String description;
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
}
