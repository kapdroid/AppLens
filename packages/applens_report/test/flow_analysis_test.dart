import 'package:applens_core/applens_core.dart';
import 'package:applens_report/src/report/flow_analysis.dart';
import 'package:test/test.dart';

Node _node(String id, String route, {List<Edge> edges = const []}) => Node(
      id: id,
      identity: NodeIdentity(route: route),
      payload: NodePayload(edges: edges),
    );

final _graph = Graph(
  nodes: [
    _node('A', '/a',
        edges: [const Edge(action: EdgeAction.tap, target: 'B', key: 'k_ab')]),
    _node('B', '/b',
        edges: [const Edge(action: EdgeAction.tap, target: 'C', key: 'k_bc')]),
    _node('C', '/c'),
  ],
  entryNodeIds: ['A'],
);

NodeVisit _v(int flow, String node, NodeOutcome outcome, int step) => NodeVisit(
      step: step,
      flow: flow,
      expectedNodeId: node,
      matchedNodeId: node,
      outcome: outcome,
    );

RunRecord _run(String strategy, List<NodeVisit> visits) => RunRecord(
      id: 'r',
      strategy: strategy,
      graphHash: 'h',
      seed: 0,
      visits: visits,
    );

void main() {
  test('groups visits into flows by their stamped index', () {
    final fa = FlowAnalysis.of(
      _run('regression', [
        _v(0, 'A', NodeOutcome.passed, 0),
        _v(0, 'B', NodeOutcome.passed, 1),
        _v(1, 'A', NodeOutcome.passed, 2),
        _v(1, 'C', NodeOutcome.failedSoft, 3),
      ]),
      _graph,
    );
    expect(fa.flows, hasLength(2));
    expect(fa.flows[0].nodes, ['A', 'B']);
    expect(fa.flows[0].failed, isFalse);
    expect(fa.flows[1].nodes, ['A', 'C']);
    expect(fa.flows[1].failed, isTrue);
    expect(fa.flows[1].firstFailure!.expectedNodeId, 'C');
  });

  test('steps to reproduce list the actions up to the failing screen', () {
    final fa = FlowAnalysis.of(
      _run('regression', [
        _v(0, 'A', NodeOutcome.passed, 0),
        _v(0, 'B', NodeOutcome.passed, 1),
        _v(0, 'C', NodeOutcome.failedSoft, 2),
      ]),
      _graph,
    );
    final str = stepsToReproduce(fa.flows[0], 'C');
    expect(str.map((s) => s.node), ['A', 'B', 'C']);
    expect(str[0].action, isNull, reason: 'first step is the launch');
    expect(str[1].action, 'tap k_ab');
    expect(str[2].action, 'tap k_bc');
  });

  test('falls back to the node sequence when the path is unrecoverable', () {
    final fa = FlowAnalysis.of(
      _run('mystery', [
        _v(0, 'A', NodeOutcome.passed, 0),
        _v(0, 'B', NodeOutcome.failedSoft, 1),
      ]),
      _graph,
    );
    expect(fa.flows[0].path, isNull);
    final str = stepsToReproduce(fa.flows[0], 'B');
    expect(str.map((s) => s.node), ['A', 'B']);
    expect(str.every((s) => s.action == null), isTrue);
  });
}
