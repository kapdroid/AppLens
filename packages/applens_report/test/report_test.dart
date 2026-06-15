import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:applens_report/applens_report.dart';
import 'package:test/test.dart';

Node _node(
  String id, {
  String? route,
  List<Assertion> assertions = const [],
  List<Edge> edges = const [],
  SourceLocation? source,
}) =>
    Node(
      id: id,
      identity: NodeIdentity(route: route),
      payload: NodePayload(assertions: assertions, edges: edges),
      source: source,
    );

final _graph = Graph(
  nodes: [
    _node(
      'shop.dashboard',
      route: '/',
      edges: [
        const Edge(
          action: EdgeAction.tap,
          target: 'shop.cart',
          key: 'btn_view_cart',
        ),
      ],
      source: const SourceLocation(
        source: 'modules/shop/nodes/dashboard.yaml',
        line: 1,
        column: 1,
      ),
    ),
    _node(
      'shop.cart',
      route: '/cart',
      assertions: [
        const Assertion(
            type: 'widget_exists', args: {'key': 'btn_place_order'}),
      ],
      source: const SourceLocation(
        source: 'modules/shop/nodes/cart.yaml',
        line: 1,
        column: 1,
      ),
    ),
  ],
  entryNodeIds: ['shop.dashboard'],
);

void main() {
  test('renders summary, coverage, and a self-locating failure', () {
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'sha256:abc',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.failedSoft,
          assertions: [
            AssertionResult(
              tierOrder: 10,
              type: 'widget_exists',
              passed: false,
              detail: 'key "btn_place_order" not present',
            ),
          ],
        ),
      ],
    );

    final html = renderRunReport(run, _graph);
    expect(html, contains('node coverage: 2/2'));
    // Self-locating: the node file + the failing assertion both appear.
    expect(html, contains('modules/shop/nodes/cart.yaml'));
    expect(html, contains('btn_place_order')); // the failing assertion detail
    expect(html, contains('<svg'));
    // The failing node is highlighted via a theme-driven class, not inline hex.
    expect(html, contains('al-node--failed'));
  });

  test('embeds an annotated highlight image for a semantic failure', () {
    final run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'sha256:abc',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.failedSoft,
          assertions: const [
            AssertionResult(
              tierOrder: 25,
              type: 'semantic_match',
              passed: false,
              detail: 'btn_place_order: "Place order" → "Order"',
            ),
          ],
          artifacts: [
            Artifact(
              kind: 'annotated',
              description: 'semantic shop.cart: text changed',
              bytes: Uint8List.fromList(const [137, 80, 78, 71]), // 'PNG' magic
            ),
          ],
        ),
      ],
    );

    final html = renderRunReport(run, _graph);
    expect(html, contains('data:image/png;base64,'));
    expect(html, contains('semantic shop.cart: text changed'));
    expect(html, contains('Place order')); // the change is shown in the detail
  });

  test('renders a pending section with a confirm-in-PR link', () {
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'sha256:abc',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.pending,
          assertions: [
            AssertionResult(
              tierOrder: 30,
              type: 'visual_pending',
              passed: true,
              detail: 'matches open proposal sha256:bb '
                  'https://github.com/o/r/pull/7',
            ),
          ],
        ),
      ],
    );

    final html = renderRunReport(run, _graph);
    expect(html, contains('Pending — intended changes'));
    expect(html, contains('section class="pending"'));
    expect(html, contains('href="https://github.com/o/r/pull/7"'));
    expect(html, contains('Confirm in PR'));
    // The cart node file locates the pending change.
    expect(html, contains('modules/shop/nodes/cart.yaml'));
  });

  test('exitCodeForRun maps outcomes to 0/1/2', () {
    RunRecord runWith(NodeOutcome outcome) => RunRecord(
          id: 'x',
          strategy: 'smoke',
          graphHash: 'h',
          seed: 0,
          visits: [
            NodeVisit(
              step: 0,
              expectedNodeId: 'a',
              matchedNodeId: 'a',
              outcome: outcome,
            ),
          ],
        );
    expect(exitCodeForRun(runWith(NodeOutcome.passed)), 0);
    expect(exitCodeForRun(runWith(NodeOutcome.failedSoft)), 1);
    expect(exitCodeForRun(runWith(NodeOutcome.failedHard)), 1);
    expect(exitCodeForRun(runWith(NodeOutcome.blocked)), 1);
    expect(exitCodeForRun(runWith(NodeOutcome.pending)), 2);
  });

  test('exitCodeForRun: red takes precedence over pending on a mixed run', () {
    const mixed = RunRecord(
      id: 'm',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'a',
          matchedNodeId: 'a',
          outcome: NodeOutcome.pending,
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'b',
          matchedNodeId: 'b',
          outcome: NodeOutcome.failedHard,
        ),
      ],
    );
    expect(exitCodeForRun(mixed), 1);
  });

  test('coverage never exceeds 100% when a run visits a non-graph node', () {
    // A run against a since-changed graph can carry a visit to a node that no
    // longer exists; it must not inflate coverage past the graph's node count.
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'stale',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'shop.ghost', // not in _graph
          matchedNodeId: null,
          outcome: NodeOutcome.passed,
        ),
      ],
    );
    final html = renderRunReport(run, _graph);
    expect(html, contains('node coverage: 1/2'));
    expect(html, isNot(contains('200%')));
  });

  test('escapeXml escapes both quote forms', () {
    expect(escapeXml('a\'b"c<d>&'), 'a&#39;b&quot;c&lt;d&gt;&amp;');
  });

  test('renderModule renders the module nodes as SVG', () {
    final svg = renderModule(_graph, 'shop');
    expect(svg, startsWith('<svg'));
    expect(svg, contains('shop.dashboard'));
    expect(svg, contains('shop.cart'));
  });

  test('folds a triage report into failures, clusters, and the metric', () {
    const run = RunRecord(
      id: 'r',
      strategy: 'regression',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.failedSoft,
          assertions: [
            AssertionResult(tierOrder: 30, type: 'visual_match', passed: false),
          ],
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.failedSoft,
          assertions: [
            AssertionResult(tierOrder: 30, type: 'visual_match', passed: false),
          ],
        ),
      ],
    );
    const triage = TriageReport(
      verdicts: [
        // cart was judged intended (sinks down); dashboard is a bug (rises).
        TriageVerdict(
          nodeId: 'shop.cart',
          classification: TriageClass.intended,
          confidence: 0.88,
          reasoning: 'matches restyle',
          causalCommit: 'abc123',
          cluster: 'abc123',
        ),
        TriageVerdict(
          nodeId: 'shop.dashboard',
          classification: TriageClass.bug,
          confidence: 0.91,
          reasoning: 'no commit explains this',
        ),
      ],
    );

    final html = renderRunReport(run, _graph, triage: triage);

    expect(html, contains('human-overturn rate 0%'));
    expect(html, contains('p class="verdict bug"'));
    expect(html, contains('p class="verdict intended"'));
    expect(html, contains('Triage clusters'));
    expect(html, contains('cause <code>abc123</code>'));
    // Bug sorts before the intended change in the Failures section.
    expect(html.indexOf('verdict bug'),
        lessThan(html.indexOf('verdict intended')));
  });

  test('without a triage report the page is unchanged (advisory, opt-in)', () {
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
      ],
    );
    final html = renderRunReport(run, _graph);
    expect(html, isNot(contains('triage:')));
    expect(html, isNot(contains('Triage clusters')));
  });

  test('renders a verdict banner, flows, and steps-to-reproduce', () {
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
        NodeVisit(
          step: 1,
          flow: 1,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
        NodeVisit(
          step: 2,
          flow: 1,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.failedSoft,
          assertions: [
            AssertionResult(
                tierOrder: 30,
                type: 'visual_match',
                passed: false,
                detail: '84% differ'),
          ],
        ),
      ],
    );
    final html = renderRunReport(run, _graph);
    expect(html, contains('class="banner red"'));
    expect(html, contains('✗ RED'));
    expect(html, contains('<h2>Flows</h2>'));
    expect(html, contains('failed at shop.cart')); // the broken flow is marked
    expect(html, contains('Steps to reproduce'));
    expect(html, contains('84% differ')); // the reason in the failing step
  });

  test(
      'renders per-screen tabs with the visual comparison and a no-baseline '
      'note', () {
    final run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
          assertions: const [
            AssertionResult(tierOrder: 30, type: 'visual_match', passed: true),
          ],
          artifacts: [
            Artifact(
              kind: 'visual_baseline',
              description: 'sha256:aa',
              bytes: Uint8List.fromList(const [137, 80, 78, 71]),
            ),
          ],
        ),
        const NodeVisit(
          step: 1,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.passed,
        ),
      ],
    );
    final html = renderRunReport(run, _graph);
    expect(html, contains('<h2>Screens</h2>'));
    expect(html, contains('class="tabs"'));
    expect(html, contains('data:image/png;base64,')); // the baseline thumbnail
    expect(html, contains('No approved baseline')); // cart has none
  });

  test('supports light and dark themes (auto + toggle), no inline node hex',
      () {
    const run = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
      ],
    );
    final html = renderRunReport(run, _graph);
    expect(html, contains('@media(prefers-color-scheme:dark)'));
    expect(html, contains('data-theme'));
    expect(html, contains('alToggleTheme'));
    expect(html, contains('al-node{')); // svg styled by class, from tokens
    expect(html, isNot(contains('fill="#'))); // no inline hex fills on nodes
  });
}
