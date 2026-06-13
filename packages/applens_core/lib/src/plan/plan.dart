import '../model/edge_action.dart';
import '../util/canonical.dart';

/// A path-compilation strategy (ARCHITECTURE.md §6), in increasing cost.
enum PlanStrategy {
  smoke('smoke'),
  impact('impact'),
  regression('regression'),
  soak('soak');

  const PlanStrategy(this.yaml);
  final String yaml;

  static PlanStrategy? fromYaml(String value) {
    for (final strategy in PlanStrategy.values) {
      if (strategy.yaml == value) {
        return strategy;
      }
    }
    return null;
  }
}

/// One transition in a plan: the action taken and the node it arrives at. The
/// node it leaves from is the previous step's [to] (or the path's start).
class PlanStep {
  const PlanStep({
    required this.action,
    required this.to,
    this.key,
    this.text,
    this.uri,
  });

  final EdgeAction action;

  /// The id of the node reached by this step.
  final String to;

  final String? key;
  final String? text;
  final String? uri;

  Map<String, Object?> toMap() => compactMap({
        'action': action.yaml,
        'key': key,
        'text': text,
        'uri': uri,
        'to': to,
      });
}

/// A single walk the runner executes: starts at [start] (an entry node) and
/// applies [steps] in order. A zero-step path simply asserts the start node.
class PlanPath {
  const PlanPath({required this.start, this.steps = const []});

  final String start;
  final List<PlanStep> steps;

  /// The node ids visited, in order — `[start, steps[0].to, …]`.
  List<String> get visited => [start, for (final step in steps) step.to];

  Map<String, Object?> toMap() => {
        'start': start,
        'steps': [for (final step in steps) step.toMap()],
      };
}

/// A compiled, human-readable test plan (ARCHITECTURE.md §6). Embeds the
/// [graphHash] it was compiled from so a stale plan against a changed graph is
/// rejected at run start. Deterministic: the same graph + strategy + seed always
/// produces a byte-identical plan.
class Plan {
  const Plan({
    required this.strategy,
    required this.graphHash,
    required this.seed,
    required this.paths,
    this.alternateInboundPaths = const {},
  });

  final PlanStrategy strategy;
  final String graphHash;
  final int seed;
  final List<PlanPath> paths;

  /// Per-node top-k alternate inbound paths, consumed by the runner's reroute
  /// logic on hard failures (ARCHITECTURE.md §7).
  final Map<String, List<PlanPath>> alternateInboundPaths;

  Map<String, Object?> toMap() {
    final sortedNodeIds = alternateInboundPaths.keys.toList()..sort();
    return {
      'strategy': strategy.yaml,
      'graph_hash': graphHash,
      'seed': seed,
      'paths': [for (final path in paths) path.toMap()],
      'alternate_inbound_paths': {
        for (final id in sortedNodeIds)
          id: [for (final path in alternateInboundPaths[id]!) path.toMap()],
      },
    };
  }
}
