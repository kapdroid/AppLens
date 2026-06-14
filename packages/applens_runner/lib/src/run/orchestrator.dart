import 'package:applens_compare/applens_compare.dart';
import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';
import '../visual/baseline_source.dart';
import '../visual/capture_scope.dart';
import '../visual/visual_tier.dart';
import 'fingerprint.dart';
import 'node_matcher.dart';
import 'tier1.dart';
import 'tier2.dart';

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
    this.baselines,
    this.captureContext,
  });

  final AppLensDriver driver;
  final FingerprintSource fingerprints;
  final RunStore store;
  final SettlePolicy settlePolicy;

  /// Loads approved baseline images for tier 3. Null disables tier 3 entirely
  /// (the default headless/no-visual config).
  final BaselineSource? baselines;

  /// The profile this run captures under. When null, any approved baseline
  /// matches (single-profile v1); when set, a baseline's context must match.
  final BaselineContext? captureContext;

  /// Nodes whose tier-3 baseline has been compared this run. A golden captures a
  /// node's *canonical* appearance, so it is compared on the first reach only —
  /// re-observations during a multi-path walk land the node in transient states
  /// (mid-transition, post-back) that are not regressions.
  final Set<String> _tier3Evaluated = <String>{};

  Future<RunRecord> run(Graph graph, Plan plan, {String runId = 'run'}) async {
    _tier3Evaluated.clear();
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
    final extraArtifacts = <Artifact>[];

    // Cheap-to-expensive (ARCHITECTURE.md §8): descend a tier only when every
    // cheaper tier held (the default short-circuit), and only when the node opts
    // in. Each observation (tree, capture) is fetched lazily, where it's used.
    if (!_anyFailed(assertions) && _wantsTier2(node)) {
      assertions.addAll(evaluateTier2(node, await driver.tree()));
    }
    if (!_anyFailed(assertions) && !_tier3Evaluated.contains(expected)) {
      final baseline = _approvedBaselineFor(node);
      if (baseline != null) {
        _tier3Evaluated.add(expected);
        final capture = await driver.capture(deriveCaptureScope(node));
        final result = evaluateTier3(
          actual: capture,
          baselinePng: await baselines!.load(baseline),
          comparator: VisualComparator(
            diffRatioThreshold: baseline.threshold ?? defaultDiffRatioThreshold,
          ),
        );
        assertions.add(result.assertion);
        if (result.diffPng != null) {
          extraArtifacts.add(
            Artifact(
              kind: 'diff',
              description: 'tier-3 ${node.id}: ${result.assertion.detail}',
              bytes: result.diffPng,
            ),
          );
        }
      }
    }

    final failed = _anyFailed(assertions);
    return NodeVisit(
      step: step,
      expectedNodeId: expected,
      matchedNodeId: matched,
      outcome: failed ? NodeOutcome.failedSoft : NodeOutcome.passed,
      assertions: assertions,
      artifacts: failed ? [...await _artifacts(), ...extraArtifacts] : const [],
    );
  }

  bool _anyFailed(List<AssertionResult> results) =>
      results.any((a) => !a.skipped && !a.passed);

  bool _wantsTier2(Node node) =>
      node.payload.assertions.any((a) => a.type == 'layout_hash');

  /// The node's approved baseline matching the run's [captureContext] (any
  /// approved baseline when the context is unset), or null if tier 3 is not
  /// configured or the node has no approved baseline.
  VisualBaseline? _approvedBaselineFor(Node node) {
    if (baselines == null) {
      return null;
    }
    for (final baseline in node.payload.visualBaselines) {
      if (baseline.state != BaselineState.approved) {
        continue;
      }
      final context = captureContext;
      if (context == null ||
          (baseline.context.device == context.device &&
              baseline.context.locale == context.locale &&
              baseline.context.theme == context.theme)) {
        return baseline;
      }
    }
    return null;
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
