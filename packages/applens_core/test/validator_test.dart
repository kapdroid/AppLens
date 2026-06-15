import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

Node _node(
  String id, {
  String? route,
  List<String> anchors = const [],
  Map<String, FlagConstraint> flags = const {},
  bool overlay = false,
  List<Edge> edges = const [],
  List<VisualBaseline> baselines = const [],
}) =>
    Node(
      id: id,
      identity: NodeIdentity(
        route: route,
        anchors: anchors,
        flags: flags,
        overlay: overlay,
      ),
      payload: NodePayload(edges: edges, visualBaselines: baselines),
    );

List<String> _codes(Graph graph) =>
    validateGraph(graph).map((diagnostic) => diagnostic.code).toList();

void main() {
  group('fingerprint ambiguity', () {
    test('same route, distinguished only by anchors, is ambiguous', () {
      final graph = Graph(
        nodes: [
          _node('a', route: '/x', anchors: ['p']),
          _node('b', route: '/x', anchors: ['q']),
        ],
        entryNodeIds: ['a', 'b'],
      );
      expect(_codes(graph), contains('fingerprint_ambiguity'));
    });

    test('different routes are distinguishable', () {
      final graph = Graph(
        nodes: [_node('a', route: '/x'), _node('b', route: '/y')],
        entryNodeIds: ['a', 'b'],
      );
      expect(_codes(graph), isNot(contains('fingerprint_ambiguity')));
    });

    test('contradicting flags distinguish same-route nodes', () {
      final graph = Graph(
        nodes: [
          _node('empty',
              route: '/cart', flags: {'n': FlagConstraint.parse('==0')}),
          _node('filled',
              route: '/cart', flags: {'n': FlagConstraint.parse('>0')}),
        ],
        entryNodeIds: ['empty', 'filled'],
      );
      expect(_codes(graph), isNot(contains('fingerprint_ambiguity')));
    });

    test('the overlay flag distinguishes same-route nodes', () {
      final graph = Graph(
        nodes: [
          _node('page', route: '/x'),
          _node('dialog', route: '/x', overlay: true),
        ],
        entryNodeIds: ['page', 'dialog'],
      );
      expect(_codes(graph), isNot(contains('fingerprint_ambiguity')));
    });
  });

  test('a dangling edge target is an error', () {
    final graph = Graph(
      nodes: [
        _node(
          'a',
          route: '/a',
          edges: [const Edge(action: EdgeAction.tap, target: 'missing')],
        ),
      ],
      entryNodeIds: ['a'],
    );
    expect(_codes(graph), contains('dangling_edge'));
  });

  test('an unreachable node is an error', () {
    final graph = Graph(
      nodes: [_node('a', route: '/a'), _node('b', route: '/b')],
      entryNodeIds: ['a'],
    );
    expect(_codes(graph), contains('unreachable_node'));
  });

  test('an orphan (imageless) baseline is an error', () {
    final graph = Graph(
      nodes: [
        _node(
          'a',
          route: '/a',
          baselines: const [
            VisualBaseline(
              context: BaselineContext(
                device: 'pixel6',
                locale: 'en',
                theme: 'light',
              ),
              capture: CaptureKind.fullScreen,
              state: BaselineState.approved,
            ),
          ],
        ),
      ],
      entryNodeIds: ['a'],
    );
    expect(_codes(graph), contains('orphan_baseline'));
  });

  test('a structural baseline without a snapshot is an orphan_baseline error',
      () {
    final graph = Graph(
      nodes: [
        Node(
          id: 'a',
          identity: const NodeIdentity(route: '/a'),
          payload: const NodePayload(
            structuralBaselines: [
              StructuralBaseline(
                context: BaselineContext(
                    device: 'pixel6', locale: 'en', theme: 'light'),
                state: BaselineState.approved,
                // no snapshot → silently disables the tier if unvalidated
              ),
            ],
          ),
        ),
      ],
      entryNodeIds: ['a'],
    );
    expect(_codes(graph), contains('orphan_baseline'));
    expect(validateGraph(graph).where((d) => d.isError), isNotEmpty);
  });

  test('a structural baseline missing context warns (not errors)', () {
    final graph = Graph(
      nodes: [
        Node(
          id: 'a',
          identity: const NodeIdentity(route: '/a'),
          payload: const NodePayload(
            structuralBaselines: [
              StructuralBaseline(
                context: BaselineContext(device: '', locale: '', theme: ''),
                state: BaselineState.approved,
                snapshot: 'sha256:abc',
              ),
            ],
          ),
        ),
      ],
      entryNodeIds: ['a'],
    );
    expect(_codes(graph), contains('incomplete_baseline_context'));
    // context-only is a warning, not an error.
    expect(validateGraph(graph).where((d) => d.isError), isEmpty);
  });

  test('a reachable, distinguishable graph validates clean', () {
    final graph = Graph(
      nodes: [
        _node(
          'a',
          route: '/a',
          edges: [const Edge(action: EdgeAction.tap, target: 'b')],
        ),
        _node('b', route: '/b'),
      ],
      entryNodeIds: ['a'],
    );
    expect(validateGraph(graph).where((d) => d.isError), isEmpty);
  });
}
