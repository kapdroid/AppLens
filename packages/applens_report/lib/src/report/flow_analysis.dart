import 'package:applens_core/applens_core.dart';

/// One flow in a run: the visits stamped with a given `flow` index, plus the
/// recompiled plan path they walked (when recoverable). The report groups by
/// the stamped index — robust across reroutes/blocked steps that change a
/// flow's visit count — and uses the path only for action labels in the STR.
class FlowView {
  FlowView(this.index, this.path, this.visits);

  final int index;

  /// The recompiled `PlanPath` for this flow, or null when it can't be
  /// recovered (e.g. the impact strategy, whose changed-node set isn't stored).
  final PlanPath? path;

  /// Visits stamped with this flow index, in walk order.
  final List<NodeVisit> visits;

  bool get failed => visits.any(_isBad);

  /// The first non-passing visit in the flow, or null when the flow is green.
  NodeVisit? get firstFailure {
    for (final v in visits) {
      if (_isBad(v)) return v;
    }
    return null;
  }

  /// The node sequence the flow walked (from the visits' expected ids), used
  /// for the flow overview and the STR fallback when [path] is null.
  List<String> get nodes => [for (final v in visits) v.expectedNodeId];

  static bool _isBad(NodeVisit v) =>
      v.outcome == NodeOutcome.failedSoft ||
      v.outcome == NodeOutcome.failedHard ||
      v.outcome == NodeOutcome.blocked;
}

/// One step in a steps-to-reproduce list: the screen reached and the action
/// that got there (`null` for the initial launch).
class ReproStep {
  ReproStep(this.node, this.action);
  final String node;
  final String? action;
}

/// Groups a run's visits into flows by their stamped `flow` index, recompiling
/// the plan (deterministic from strategy + seed + graph) to recover each flow's
/// path for action labels.
class FlowAnalysis {
  FlowAnalysis._(this.flows);

  final List<FlowView> flows;

  static FlowAnalysis of(RunRecord run, Graph graph) {
    final plan = _recompile(run, graph);
    final byFlow = <int, List<NodeVisit>>{};
    for (final visit in run.visits) {
      (byFlow[visit.flow] ??= <NodeVisit>[]).add(visit);
    }
    final indices = byFlow.keys.toList()..sort();
    return FlowAnalysis._([
      for (final i in indices)
        FlowView(
          i,
          (plan != null && i < plan.paths.length) ? plan.paths[i] : null,
          byFlow[i]!,
        ),
    ]);
  }

  static Plan? _recompile(RunRecord run, Graph graph) {
    final strategy = PlanStrategy.fromYaml(run.strategy);
    if (strategy == null) {
      return null;
    }
    try {
      // impact's changed-node set isn't stored on the run, so its recompiled
      // plan is empty — flows then fall back to the visit node sequence.
      return compilePlan(graph, strategy: strategy, seed: run.seed);
    } on Object {
      return null;
    }
  }
}

/// The steps to reproduce reaching [failingNodeId] in [flow]: the launch plus
/// each action up to (and including) the failing screen. Uses the recompiled
/// path for action labels; falls back to the bare node sequence when the path
/// is unavailable.
List<ReproStep> stepsToReproduce(FlowView flow, String failingNodeId) {
  final path = flow.path;
  if (path != null) {
    final stop = path.visited.indexOf(failingNodeId);
    final steps = stop < 0 ? path.steps.length : stop;
    return [
      ReproStep(path.start, null),
      for (var i = 0; i < steps; i++)
        ReproStep(path.steps[i].to, _describe(path.steps[i])),
    ];
  }
  final nodes = flow.nodes;
  final stop = nodes.indexOf(failingNodeId);
  final end = stop < 0 ? nodes.length : stop + 1;
  return [for (var i = 0; i < end; i++) ReproStep(nodes[i], null)];
}

String _describe(PlanStep step) {
  final action = step.action.yaml;
  if (step.key != null) return '$action ${step.key}';
  if (step.text != null) return '$action "${step.text}"';
  if (step.uri != null) return '$action ${step.uri}';
  return action;
}
