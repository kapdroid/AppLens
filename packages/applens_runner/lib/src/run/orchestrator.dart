import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';
import 'fingerprint.dart';
import 'node_matcher.dart';
import 'run_model.dart';
import 'run_store.dart';
import 'tier1.dart';

/// Walks a compiled plan against a driver, fingerprinting each state, matching
/// it to the expected node, running tier-1 assertions, and recording the
/// outcome (ARCHITECTURE.md §7). On a hard failure it consumes the plan's
/// precomputed alternate inbound paths to reroute; if reroute fails, downstream
/// nodes are blocked, not falsely failed.
///
/// Deterministic and device-agnostic: actions go through [AppLensDriver] and
/// state is observed through [FingerprintSource], so the full state machine is
/// exercised headless with a FakeDriver and a scripted source.
class Orchestrator {
  Orchestrator({
    required this.driver,
    required this.fingerprints,
    required this.store,
    this.settlePolicy = const SettlePolicy(),
  });

  final AppLensDriver driver;
  final FingerprintSource fingerprints;
  final RunStore store;
  final SettlePolicy settlePolicy;

  Future<RunRecord> run(Graph graph, Plan plan, {String runId = 'run'}) async {
    final visits = <NodeVisit>[];
    var step = 0;
    for (final path in plan.paths) {
      step = await _walk(graph, plan, path, visits, step);
    }
    final record = RunRecord(
      id: runId,
      strategy: plan.strategy.yaml,
      graphHash: plan.graphHash,
      seed: plan.seed,
      visits: visits,
    );
    await store.saveRun(record);
    return record;
  }

  Future<int> _walk(
    Graph graph,
    Plan plan,
    PlanPath path,
    List<NodeVisit> visits,
    int startStep,
  ) async {
    var step = startStep;

    // The app launches at the entry node; observe and verify it.
    final entryFingerprint = await fingerprints.capture();
    visits.add(
      await _evaluate(graph, path.start, entryFingerprint, step++, path.start),
    );

    var blocked = false;
    for (final planStep in path.steps) {
      if (blocked) {
        visits.add(
          NodeVisit(
            step: step++,
            expectedNodeId: planStep.to,
            matchedNodeId: null,
            outcome: NodeOutcome.blocked,
          ),
        );
        continue;
      }

      await _act(planStep);
      await driver.settle(settlePolicy);
      final fingerprint = await fingerprints.capture();
      final matched = matchNode(fingerprint, graph);

      if (matched == planStep.to) {
        visits.add(
          await _evaluate(graph, planStep.to, fingerprint, step++, planStep.to),
        );
        continue;
      }

      // Expected node not reached: a hard failure (matched some other known
      // node = unexpected transition; matched nothing = lost). Record evidence,
      // then try to reroute via the plan's alternates.
      visits.add(
        NodeVisit(
          step: step++,
          expectedNodeId: planStep.to,
          matchedNodeId: matched,
          outcome: NodeOutcome.failedHard,
          artifacts: await _artifacts(),
        ),
      );
      final reroutedStep =
          await _reroute(graph, plan, planStep.to, visits, step);
      if (reroutedStep == null) {
        blocked = true;
      } else {
        step = reroutedStep;
      }
    }
    return step;
  }

  Future<NodeVisit> _evaluate(
    Graph graph,
    String expected,
    Fingerprint fingerprint,
    int step,
    String matched,
  ) async {
    final node = graph.byId[expected]!;
    final assertions = evaluateTier1(node, fingerprint);
    final failed = assertions.any((a) => !a.skipped && !a.passed);
    return NodeVisit(
      step: step,
      expectedNodeId: expected,
      matchedNodeId: matched,
      outcome: failed ? NodeOutcome.failedSoft : NodeOutcome.passed,
      assertions: assertions,
      artifacts: failed ? await _artifacts() : const [],
    );
  }

  Future<int?> _reroute(
    Graph graph,
    Plan plan,
    String target,
    List<NodeVisit> visits,
    int startStep,
  ) async {
    var step = startStep;
    for (final alternate
        in plan.alternateInboundPaths[target] ?? const <PlanPath>[]) {
      for (final planStep in alternate.steps) {
        await _act(planStep);
        await driver.settle(settlePolicy);
      }
      final fingerprint = await fingerprints.capture();
      if (matchNode(fingerprint, graph) == target) {
        visits.add(await _evaluate(graph, target, fingerprint, step++, target));
        return step;
      }
    }
    return null;
  }

  Future<void> _act(PlanStep planStep) async {
    final key = planStep.key;
    KeySelector requireSelector() {
      if (key == null) {
        throw DriverException(
          '${planStep.action.yaml} step targeting "${planStep.to}" has no key',
        );
      }
      return KeySelector(key);
    }

    switch (planStep.action) {
      case EdgeAction.tap:
        await driver.tap(requireSelector());
      case EdgeAction.longPress:
        await driver.longPress(requireSelector());
      case EdgeAction.enterText:
        await driver.enterText(requireSelector(), planStep.text ?? '');
      case EdgeAction.scrollTo:
        await driver.scrollTo(requireSelector());
      case EdgeAction.back:
        await driver.back();
      case EdgeAction.deepLink:
        await driver.openDeepLink(Uri.parse(planStep.uri ?? ''));
      case EdgeAction.swipe:
        throw UnimplementedError(
          'swipe edges carry no coordinates in the model yet; not used in v1 plans',
        );
      case EdgeAction.native:
        await driver.native(const PermissionAction(''));
    }
  }

  Future<List<Artifact>> _artifacts() async {
    // Tier-0 evidence: the serialized tree + a log placeholder. Full-screen
    // capture is wired with capture() in Session 7; it is not called here.
    final tree = await driver.tree();
    return [
      Artifact(kind: 'tree', description: 'root=${tree.root.type}'),
      const Artifact(
          kind: 'log', description: 'log-tail capture lands in Session 5'),
    ];
  }
}
