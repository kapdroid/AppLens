import '../driver/driver.dart';

/// One assertion tier. Tiers run cheap-to-expensive; a structural failure
/// short-circuits lower tiers by default.
abstract interface class OracleTier {
  /// Lower runs first. T1 tree = 10, T2 layout = 20, T3 pixel = 30,
  /// T4 advisory = 40.
  int get order;

  /// Evaluates this tier against the current state. Pure given its inputs — no
  /// tier may consult an LLM or any nondeterministic source.
  Future<OracleResult> evaluate(NodeSpec node, EvaluationContext context);
}

/// Whether a tier's assertions held.
enum OracleStatus { passed, failed }

/// The outcome of evaluating one [OracleTier].
class OracleResult {
  const OracleResult({
    required this.order,
    required this.status,
    this.detail = '',
  });

  /// The [OracleTier.order] that produced this result.
  final int order;
  final OracleStatus status;

  /// Human-facing explanation, empty when passed.
  final String detail;

  bool get passed => status == OracleStatus.passed;
}

/// The slice of a graph node an oracle evaluates against. The full graph model
/// lands in applens_core (Session 1); this minimal shape is what the contract
/// needs today.
class NodeSpec {
  const NodeSpec(this.id);

  /// Hierarchical, globally unique node id (e.g. `order.confirm`).
  final String id;
}

/// Everything a tier needs to evaluate a node: a handle to drive and observe
/// the app, plus the current tree snapshot.
class EvaluationContext {
  const EvaluationContext({required this.driver, required this.tree});

  final AppLensDriver driver;
  final WidgetTreeSnapshot tree;
}
