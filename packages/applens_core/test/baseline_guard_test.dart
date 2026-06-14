import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

Node _node(
  String id, {
  List<Assertion> assertions = const [],
  List<VisualBaseline> baselines = const [],
}) =>
    Node(
      id: id,
      identity: const NodeIdentity(route: '/x', anchors: ['k']),
      payload: NodePayload(assertions: assertions, visualBaselines: baselines),
    );

const _baseline = VisualBaseline(
  context: BaselineContext(device: 'd', locale: 'l', theme: 't'),
  capture: CaptureKind.fullScreen,
  state: BaselineState.approved,
  image: 'sha256:abc',
);

Graph _graph(List<Node> nodes) =>
    Graph(nodes: nodes, entryNodeIds: [nodes.first.id]);

void main() {
  group('BaselineOnlyMergeGuard.permits (file scope)', () {
    const guard = BaselineOnlyMergeGuard();

    test('permits goldens and node files', () {
      expect(
        guard.permits([
          'examples/app/qa_graph/goldens/7f43.png',
          'examples/app/qa_graph/modules/shop/nodes/cart.yaml',
        ]),
        isTrue,
      );
    });

    test('rejects source, module manifests, app config, workflows', () {
      expect(guard.permits(['packages/app/lib/main.dart']), isFalse);
      expect(
        guard.permits(['qa_graph/modules/shop/shop.module.yaml']),
        isFalse,
      );
      expect(guard.permits(['qa_graph/applens.yaml']), isFalse);
      expect(guard.permits(['.github/workflows/ci.yaml']), isFalse);
    });

    test('rejects a mixed diff (one stray path taints the whole PR)', () {
      expect(
        guard.permits([
          'qa_graph/goldens/a.png',
          'packages/app/lib/main.dart',
        ]),
        isFalse,
      );
    });

    test('never auto-merges an empty diff', () {
      expect(guard.permits(const []), isFalse);
    });
  });

  group('isBaselineOnlyGraphChange (semantic)', () {
    test('adding a baseline to a node is baseline-only', () {
      final before = _graph([_node('a'), _node('b')]);
      final after = _graph([
        _node('a', baselines: [_baseline]),
        _node('b')
      ]);
      expect(isBaselineOnlyGraphChange(before, after), isTrue);
    });

    test('an identical graph is trivially baseline-only', () {
      expect(
        isBaselineOnlyGraphChange(_graph([_node('a')]), _graph([_node('a')])),
        isTrue,
      );
    });

    test('changing an assertion is NOT baseline-only', () {
      final before = _graph([
        _node('a', assertions: [
          const Assertion(type: 'widget_exists', args: {'key': 'x'})
        ]),
      ]);
      final after = _graph([
        _node('a', assertions: [
          const Assertion(type: 'widget_exists', args: {'key': 'y'})
        ], baselines: [
          _baseline
        ]),
      ]);
      expect(isBaselineOnlyGraphChange(before, after), isFalse);
    });

    test('adding or removing a node is NOT baseline-only', () {
      expect(
        isBaselineOnlyGraphChange(
            _graph([_node('a')]), _graph([_node('a'), _node('b')])),
        isFalse,
      );
    });
  });
}
