import 'dart:ui' show Rect;

import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/driver/fake_driver.dart';
import 'package:applens_runner/src/run/tier2.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted [FingerprintSource]: returns each fingerprint in order, clamping
/// at the last so over-reads are harmless.
class _ScriptedFingerprints implements FingerprintSource {
  _ScriptedFingerprints(this._frames);
  final List<Fingerprint> _frames;
  int _index = 0;

  @override
  Future<Fingerprint> capture() async {
    final frame = _frames[_index.clamp(0, _frames.length - 1)];
    if (_index < _frames.length - 1) {
      _index++;
    }
    return frame;
  }
}

Node _node(String id, String route, {List<Assertion> assertions = const []}) =>
    Node(
      id: id,
      identity: NodeIdentity(route: route),
      payload: NodePayload(assertions: assertions),
    );

Assertion _exists(String key) =>
    Assertion(type: 'widget_exists', args: {'key': key});

// A→B→C by route; plus a direct A→C used as C's alternate inbound path.
final _graph = Graph(
  nodes: [
    _node('A', '/a'),
    _node('B', '/b', assertions: [_exists('b_btn')]),
    _node('C', '/c', assertions: [_exists('c_btn')]),
  ],
  entryNodeIds: ['A'],
);

PlanStep _tap(String to, String key) =>
    PlanStep(action: EdgeAction.tap, to: to, key: key);

Plan _plan(
  List<PlanPath> paths, {
  Map<String, List<PlanPath>> alternates = const {},
}) =>
    Plan(
      strategy: PlanStrategy.smoke,
      graphHash: 'h',
      seed: 0,
      paths: paths,
      alternateInboundPaths: alternates,
    );

const _fpA = Fingerprint(route: '/a');
const _fpBpass = Fingerprint(route: '/b', anchors: {'b_btn'});
const _fpBfail = Fingerprint(route: '/b');
const _fpCpass = Fingerprint(route: '/c', anchors: {'c_btn'});
const _fpUnknown = Fingerprint(route: '/zzz');

Orchestrator _orchestrator(FakeDriver driver, List<Fingerprint> frames) =>
    Orchestrator(
      driver: driver,
      fingerprints: _ScriptedFingerprints(frames),
      store: InMemoryRunStore(),
    );

void main() {
  final linear = _plan([
    PlanPath(start: 'A', steps: [_tap('B', 'k_ab'), _tap('C', 'k_bc')]),
  ]);

  test('clean pass: every node reached and verified', () async {
    final driver = FakeDriver();
    final record = await _orchestrator(driver, [
      _fpA,
      _fpBpass,
      _fpCpass,
    ]).run(_graph, linear);

    expect(
      record.visits.map((v) => v.outcome),
      [NodeOutcome.passed, NodeOutcome.passed, NodeOutcome.passed],
    );
    expect(driver.actionLog, [
      'tap key "k_ab"',
      'settle',
      'tap key "k_bc"',
      'settle',
    ]);
  });

  test('soft fail: assertion mismatch, run continues', () async {
    final driver = FakeDriver();
    final record = await _orchestrator(driver, [
      _fpA,
      _fpBfail,
      _fpCpass,
    ]).run(_graph, linear);

    expect(
      record.visits.map((v) => v.outcome),
      [NodeOutcome.passed, NodeOutcome.failedSoft, NodeOutcome.passed],
    );
    expect(record.visits[1].artifacts, isNotEmpty);
    expect(record.visits[1].assertions.any((a) => !a.passed), isTrue);
  });

  test('hard fail with successful reroute via an alternate inbound path',
      () async {
    final driver = FakeDriver();
    final plan = _plan(
      [
        PlanPath(start: 'A', steps: [_tap('B', 'k_ab'), _tap('C', 'k_bc')]),
      ],
      alternates: {
        'C': [
          PlanPath(start: 'A', steps: [_tap('C', 'k_ac')]),
        ],
      },
    );
    // entry A, step1 → B, step2 → nothing known (hard fail), reroute → C.
    final record = await _orchestrator(driver, [
      _fpA,
      _fpBpass,
      _fpUnknown,
      _fpCpass,
    ]).run(_graph, plan);

    expect(record.visits.map((v) => v.outcome), [
      NodeOutcome.passed,
      NodeOutcome.passed,
      NodeOutcome.failedHard,
      NodeOutcome.passed,
    ]);
    expect(record.visits[2].expectedNodeId, 'C');
    expect(record.visits[2].matchedNodeId, isNull);
    expect(record.visits[3].expectedNodeId, 'C');
    expect(driver.actionLog, contains('tap key "k_ac"'));
  });

  test('unexpected transition: landed on a different known node', () async {
    final driver = FakeDriver();
    final plan = _plan([
      PlanPath(start: 'A', steps: [_tap('B', 'k_ab')]),
    ]);
    // entry A, then observe C while expecting B.
    final record =
        await _orchestrator(driver, [_fpA, _fpCpass]).run(_graph, plan);

    expect(record.visits[0].outcome, NodeOutcome.passed);
    expect(record.visits[1].expectedNodeId, 'B');
    expect(record.visits[1].matchedNodeId, 'C');
    expect(record.visits[1].isUnexpectedTransition, isTrue);
    expect(record.visits[1].outcome, NodeOutcome.failedHard);
  });

  test('reroute exhausted: downstream nodes are blocked, not failed', () async {
    final driver = FakeDriver();
    // linear plan has no alternates: step1 (A→B) lands nowhere known (hard
    // fail), B has no alternate inbound path, so the C step is blocked.
    final record = await _orchestrator(driver, [
      _fpA,
      _fpUnknown,
    ]).run(_graph, linear);

    expect(record.visits.map((v) => v.outcome), [
      NodeOutcome.passed,
      NodeOutcome.failedHard,
      NodeOutcome.blocked,
    ]);
    expect(record.visits[2].expectedNodeId, 'C');
    expect(record.visits[2].matchedNodeId, isNull);
  });

  group('tier 2 (layout hash) wired into the loop', () {
    final observed = WidgetTreeSnapshot(
      SerializedWidget(
        type: 'Root',
        rect: const Rect.fromLTWH(0, 0, 1200, 1200),
        children: const [
          SerializedWidget(type: 'Text', rect: Rect.fromLTWH(0, 0, 100, 40)),
        ],
      ),
    );

    Graph graphWithB(List<Assertion> bAssertions) => Graph(
          nodes: [
            _node('A', '/a'),
            _node('B', '/b', assertions: bAssertions),
          ],
          entryNodeIds: ['A'],
        );

    final toB = _plan([
      PlanPath(start: 'A', steps: [_tap('B', 'k_ab')]),
    ]);

    test('matching layout hash passes as a tier-2 assertion', () async {
      final baseline = layoutHash(observed);
      final record = await _orchestrator(
        FakeDriver(trees: [observed]),
        [_fpA, _fpBpass],
      ).run(
        graphWithB([
          _exists('b_btn'),
          Assertion(type: 'layout_hash', args: {'value': baseline}),
        ]),
        toB,
      );

      expect(record.visits[1].outcome, NodeOutcome.passed);
      final tier2 = record.visits[1].assertions
          .where((a) => a.tierOrder == tier2Order)
          .toList();
      expect(tier2, hasLength(1));
      expect(tier2.single.passed, isTrue);
    });

    test('drifted layout hash is a soft fail', () async {
      final record = await _orchestrator(
        FakeDriver(trees: [observed]),
        [_fpA, _fpBpass],
      ).run(
        graphWithB([
          _exists('b_btn'),
          const Assertion(type: 'layout_hash', args: {'value': 'sha256:old'}),
        ]),
        toB,
      );

      expect(record.visits[1].outcome, NodeOutcome.failedSoft);
      expect(
        record.visits[1].assertions
            .singleWhere((a) => a.tierOrder == tier2Order)
            .passed,
        isFalse,
      );
    });

    test('a tier-1 failure short-circuits the tier-2 layout hash', () async {
      final baseline = layoutHash(observed);
      final record = await _orchestrator(
        FakeDriver(trees: [observed]),
        [_fpA, _fpBfail], // missing b_btn anchor → tier 1 fails
      ).run(
        graphWithB([
          _exists('b_btn'),
          Assertion(type: 'layout_hash', args: {'value': baseline}),
        ]),
        toB,
      );

      expect(record.visits[1].outcome, NodeOutcome.failedSoft);
      // Tier 2 never ran — no layout-hash result recorded.
      expect(
        record.visits[1].assertions.any((a) => a.tierOrder == tier2Order),
        isFalse,
      );
    });
  });

  test('same graph + plan run twice → identical visit sequence', () async {
    List<String> signature(RunRecord record) => [
          for (final visit in record.visits)
            '${visit.expectedNodeId}|${visit.matchedNodeId}|${visit.outcome.name}',
        ];
    final frames = [_fpA, _fpBpass, _fpCpass];
    final first = await _orchestrator(FakeDriver(), frames).run(_graph, linear);
    final second =
        await _orchestrator(FakeDriver(), frames).run(_graph, linear);

    expect(signature(second), signature(first));
  });
}
