import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_runner/src/run/node_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Node _node(
  String id, {
  String? route,
  List<String> anchors = const [],
  Map<String, FlagConstraint> flags = const {},
  bool overlay = false,
}) =>
    Node(
      id: id,
      identity: NodeIdentity(
        route: route,
        anchors: anchors,
        flags: flags,
        overlay: overlay,
      ),
      payload: const NodePayload(),
    );

void main() {
  test('matches by route, anchor presence, and flag acceptance', () {
    final graph = Graph(
      nodes: [
        _node(
          'cart',
          route: '/cart',
          anchors: ['list_cart_items'],
          flags: {'cart_count': FlagConstraint.parse('>0')},
        ),
        _node('empty',
            route: '/cart', flags: {'cart_count': FlagConstraint.parse('==0')}),
      ],
      entryNodeIds: ['cart', 'empty'],
    );

    expect(
      matchNode(
        const Fingerprint(
          route: '/cart',
          anchors: {'list_cart_items'},
          flags: {'cart_count': '3'},
        ),
        graph,
      ),
      'cart',
    );
    expect(
      matchNode(
          const Fingerprint(route: '/cart', flags: {'cart_count': '0'}), graph),
      'empty',
    );
  });

  test('does not match when a required anchor is absent', () {
    final graph = Graph(
      nodes: [
        _node('a', route: '/a', anchors: ['needed'])
      ],
      entryNodeIds: ['a'],
    );
    expect(matchNode(const Fingerprint(route: '/a'), graph), isNull);
  });

  test('overlay must match', () {
    final graph = Graph(
      nodes: [_node('dialog', route: '/a', overlay: true)],
      entryNodeIds: ['dialog'],
    );
    expect(matchNode(const Fingerprint(route: '/a'), graph), isNull);
    expect(matchNode(const Fingerprint(route: '/a', overlay: true), graph),
        'dialog');
  });
}
