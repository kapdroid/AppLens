import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

const _nodeYaml = '''
id: shop.cart
identity:
  route: /cart
  anchors: [list_cart_items, btn_place_order]
  flags: { cart_count: ">0" }
  overlay: false
payload:
  assertions:
    - { type: widget_exists, key: btn_place_order }
    - { type: text_equals, key: lbl_total, source: computed }
  edges:
    - { action: tap, key: btn_place_order, target: shop.confirm }
    - { action: back, target: shop.catalog }
  guards: { requires: [journey.started] }
  tags: [sanity, shopping]
  owner: team-shop
''';

void main() {
  test('a node parses into the typed model', () {
    final node = parseNode(_nodeYaml, source: 'cart.yaml');
    expect(node.id, 'shop.cart');
    expect(node.identity.route, '/cart');
    expect(node.identity.flags['cart_count'], isA<IntRangeConstraint>());
    expect(node.payload.edges.first.action, EdgeAction.tap);
    expect(node.payload.edges.first.target, 'shop.confirm');
    expect(node.payload.edges.last.action, EdgeAction.back);
    expect(node.payload.guard?.requires, ['journey.started']);
    expect(node.payload.tags, ['sanity', 'shopping']);
  });

  test('parse → serialize → parse round-trips (serialization is stable)', () {
    final node = parseNode(_nodeYaml, source: 'cart.yaml');
    final once = writeYaml(node.toMap());
    final twice = writeYaml(parseNode(once, source: 'round-trip').toMap());
    expect(twice, once);
  });

  test('a syntactically valid but mistyped value reports a precise location',
      () {
    const bad = 'id: x\nidentity:\n  route: 123\n';
    expect(
      () => parseNode(bad, source: 'bad.yaml'),
      throwsA(
        isA<GraphParseException>()
            .having((e) => e.location.line, 'line', 3)
            .having((e) => e.message, 'message', contains('route')),
      ),
    );
  });

  test('an out-of-range flag comparison is a located parse error, not a crash',
      () {
    const bad = 'id: x\n'
        'identity:\n'
        '  flags: { n: ">99999999999999999999" }\n';
    expect(
      () => parseNode(bad, source: 'bad.yaml'),
      throwsA(
        isA<GraphParseException>()
            .having((e) => e.location.line, 'line', 3)
            .having((e) => e.message, 'message', contains('out of range')),
      ),
    );
  });

  test('a YAML syntax error reports a location', () {
    const broken = 'id: x\nidentity: [unclosed\n';
    expect(() => parseNode(broken, source: 'broken.yaml'),
        throwsA(isA<GraphParseException>()));
  });

  test('a swipe edge round-trips its direction', () {
    const yaml = 'id: x\n'
        'identity: { route: /x }\n'
        'payload:\n'
        '  edges:\n'
        '    - { action: swipe, direction: left, key: pager, target: y }\n';
    final node = parseNode(yaml, source: 'x.yaml');
    final edge = node.payload.edges.single;
    expect(edge.action, EdgeAction.swipe);
    expect(edge.direction, SwipeDirection.left);
    final twice = parseNode(writeYaml(node.toMap()), source: 'x.yaml');
    expect(twice.payload.edges.single.direction, SwipeDirection.left);
  });

  test('an unknown swipe direction is a located parse error', () {
    const bad = 'id: x\n'
        'identity: { route: /x }\n'
        'payload:\n'
        '  edges:\n'
        '    - { action: swipe, direction: sideways, target: y }\n';
    expect(
      () => parseNode(bad, source: 'bad.yaml'),
      throwsA(isA<GraphParseException>()
          .having((e) => e.message, 'message', contains('direction'))),
    );
  });

  test('a mistyped baseline state is a loud parse error, not silent coercion',
      () {
    const bad = 'id: x\n'
        'identity: { route: /x }\n'
        'payload:\n'
        '  visual_baselines:\n'
        '    - context: { device: d, locale: l, theme: t }\n'
        '      capture: full_screen\n'
        '      state: aproved\n' // typo for "approved"
        '      image: "sha256:z"\n';
    expect(
      () => parseNode(bad, source: 'bad.yaml'),
      throwsA(isA<GraphParseException>()
          .having((e) => e.message, 'message', contains('state'))),
    );
  });

  test('a fragment that declares its own includes is a loud parse error', () {
    const fragment = 'includes: [shared/other]\n'
        'identity: { anchors: [app_bar] }\n';
    expect(
      () => parseFragment(fragment, source: 'frag.yaml'),
      throwsA(isA<GraphParseException>()
          .having((e) => e.message, 'message', contains('includes'))),
    );
  });

  test('a mistyped baseline capture is a loud parse error', () {
    const bad = 'id: x\n'
        'identity: { route: /x }\n'
        'payload:\n'
        '  visual_baselines:\n'
        '    - context: { device: d, locale: l, theme: t }\n'
        '      capture: cropToWidget\n' // enum-name, not the yaml spelling
        '      state: approved\n'
        '      image: "sha256:z"\n';
    expect(
      () => parseNode(bad, source: 'bad.yaml'),
      throwsA(isA<GraphParseException>()
          .having((e) => e.message, 'message', contains('capture'))),
    );
  });
}
