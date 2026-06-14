import 'package:applens_compare/applens_compare.dart';
import 'package:applens_core/applens_core.dart';

import '../driver/driver.dart';
import '../visual/baseline_source.dart';
import '../visual/capture_scope.dart';
import '../visual/proposal_source.dart';
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
    this.proposals,
    this.captureContext,
  });

  final AppLensDriver driver;
  final FingerprintSource fingerprints;
  final RunStore store;
  final SettlePolicy settlePolicy;

  /// Loads approved baseline images for tier 3. Null disables tier 3 entirely
  /// (the default headless/no-visual config).
  final BaselineSource? baselines;

  /// Open baseline proposals (ARCHITECTURE.md §9). When a capture drifts from
  /// the approved baseline but matches an open proposal, the node is `pending`
  /// (yellow), not red. Null = no proposals (every drift is red).
  final ProposalSource? proposals;

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

    // Between plan paths the app is left wherever the previous path ended;
    // return to this path's start (an entry node) before observing it, so a
    // multi-path plan walks reliably rather than acting on the wrong screen.
    // The returned observation is the start node's fingerprint (one capture when
    // already there, so a single-path walk's observation sequence is unchanged).
    final entryFingerprint = await _returnToStart(graph, path.start);

    var blocked = false;
    if (matchNode(entryFingerprint, graph) != path.start) {
      // Could not return to the path's start: record it as a hard failure and
      // block the path, rather than evaluating the start node's assertions
      // against whatever screen we ended up on.
      visits.add(
        NodeVisit(
          step: step++,
          expectedNodeId: path.start,
          matchedNodeId: matchNode(entryFingerprint, graph),
          outcome: NodeOutcome.failedHard,
          artifacts: await _artifacts(),
        ),
      );
      blocked = true;
    } else {
      visits.add(
        await _evaluate(
            graph, path.start, entryFingerprint, step++, path.start),
      );
    }
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

      var actionFailed = false;
      try {
        await _act(planStep);
        await driver.settle(settlePolicy);
      } on DriverException {
        // The step couldn't execute (e.g. its widget is absent on this screen).
        // Treat it as failing to reach the target — record evidence and reroute
        // below — rather than letting the exception abort the whole run.
        actionFailed = true;
      }
      final fingerprint = await fingerprints.capture();
      final matched = matchNode(fingerprint, graph);

      if (!actionFailed && matched == planStep.to) {
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
    var pending = false;
    if (!_anyFailed(assertions) && !_tier3Evaluated.contains(expected)) {
      final baseline = _approvedBaselineFor(node);
      if (baseline != null) {
        _tier3Evaluated.add(expected);
        try {
          final capture = await driver.capture(deriveCaptureScope(node));
          final result = evaluateTier3(
            actual: capture,
            baselinePng: await baselines!.load(baseline),
            comparator: _comparatorFor(baseline),
          );
          if (result.assertion.passed || result.assertion.skipped) {
            assertions.add(result.assertion);
          } else {
            // Drift from the approved baseline. Matching an open proposal is
            // pending (yellow), not a regression (ARCHITECTURE.md §9).
            final proposal = await _matchedOpenProposal(node, capture);
            if (proposal != null) {
              pending = true;
              final pr = proposal.reasonPr;
              assertions.add(
                AssertionResult(
                  tierOrder: tier3Order,
                  type: 'visual_pending',
                  passed: true,
                  detail: 'matches open proposal ${proposal.image}'
                      '${pr == null ? '' : ' $pr'}',
                ),
              );
            } else {
              assertions.add(result.assertion);
              if (result.diffPng != null) {
                extraArtifacts.add(
                  Artifact(
                    kind: 'diff',
                    description:
                        'tier-3 ${node.id}: ${result.assertion.detail}',
                    bytes: result.diffPng,
                  ),
                );
              }
              // Record the drifted capture itself, content-addressed, so triage
              // can propose it as the candidate golden if it judges the change
              // intended (ARCHITECTURE.md §9). The diff overlay is evidence; this
              // is the would-be baseline.
              extraArtifacts.add(
                Artifact(
                  kind: 'capture',
                  description: baselineImageKey(capture.pngBytes),
                  bytes: capture.pngBytes,
                ),
              );
            }
          }
        } on DriverException catch (error) {
          // Tier-3 evidence collection is advisory: a capture failure (e.g. an
          // overlay's anchor absent or duplicated at capture time) must never
          // abort the run. Skip it so the node's verdict rests on tier-1/2.
          assertions.add(AssertionResult(
            tierOrder: tier3Order,
            type: 'visual_match',
            passed: true,
            skipped: true,
            detail: 'tier-3 capture skipped: ${error.message}',
          ));
        }
      }
    }

    final failed = _anyFailed(assertions);
    return NodeVisit(
      step: step,
      expectedNodeId: expected,
      matchedNodeId: matched,
      outcome: failed
          ? NodeOutcome.failedSoft
          : pending
              ? NodeOutcome.pending
              : NodeOutcome.passed,
      assertions: assertions,
      artifacts: failed ? [...await _artifacts(), ...extraArtifacts] : const [],
    );
  }

  /// The first open proposal for [node] whose golden the [capture] matches, or
  /// null. Proposal goldens are content-addressed in the same [baselines] store.
  Future<VisualBaseline?> _matchedOpenProposal(
      Node node, Capture capture) async {
    if (proposals == null) {
      return null;
    }
    for (final proposal in await proposals!.openProposalsFor(node.id)) {
      final result = evaluateTier3(
        actual: capture,
        baselinePng: await baselines!.load(proposal),
        comparator: _comparatorFor(proposal),
      );
      // A *skipped* tier-3 (the proposal's golden is absent from the store) is
      // not a match — otherwise a missing proposal golden would silently
      // downgrade a real regression from red to pending.
      if (result.assertion.passed && !result.assertion.skipped) {
        return proposal;
      }
    }
    return null;
  }

  VisualComparator _comparatorFor(VisualBaseline baseline) => VisualComparator(
        diffRatioThreshold: baseline.threshold ?? defaultDiffRatioThreshold,
      );

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
      // An alternate is a full path from an entry, so it must be replayed from
      // its start — but the failed step left the app on the wrong screen.
      // Return to the alternate's start first; if we can't, try the next one.
      final atStart = await _returnToStart(graph, alternate.start);
      if (matchNode(atStart, graph) != alternate.start) {
        continue;
      }
      var replayed = true;
      for (final planStep in alternate.steps) {
        try {
          await _act(planStep);
        } on DriverException {
          replayed = false; // a step's widget isn't here; this alternate fails
          break;
        }
        await driver.settle(settlePolicy);
      }
      if (!replayed) {
        continue;
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

  /// The most pops [_returnToStart] will attempt before giving up — a guard so a
  /// navigator that refuses to return to the entry can't loop forever.
  static const int _maxReturnPops = 24;

  /// Pops back toward [start] (an entry node) until the live state matches it,
  /// bounded by [_maxReturnPops], and returns the final observation (the start
  /// node's fingerprint). Best-effort: if it cannot reach [start], the caller's
  /// entry evaluation records the mismatch instead of the walk acting on the
  /// wrong screen.
  Future<Fingerprint> _returnToStart(Graph graph, String start) async {
    var fingerprint = await fingerprints.capture();
    var signature = _fingerprintSignature(fingerprint);
    for (var pops = 0;
        matchNode(fingerprint, graph) != start && pops < _maxReturnPops;
        pops++) {
      await driver.back();
      await driver.settle(settlePolicy);
      fingerprint = await fingerprints.capture();
      final next = _fingerprintSignature(fingerprint);
      if (next == signature) {
        // back() changed nothing observable (e.g. already at the root) — give
        // up. Compares the whole fingerprint, not just the matched node, so two
        // stacked screens that share a node id aren't mistaken for "stuck".
        break;
      }
      signature = next;
    }
    return fingerprint;
  }

  String _fingerprintSignature(Fingerprint fp) =>
      '${fp.route}|${(fp.anchors.toList()..sort()).join(',')}|${fp.overlay}';

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
