import 'package:applens_core/applens_core.dart';
import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

const _draftJson = {
  'nodes': [
    {
      'id': 'dashboard',
      'route': '/',
      'anchors': ['btn_start_shopping'],
      'assertions': [
        {'type': 'widget_exists', 'key': 'btn_start_shopping'},
        {'type': 'text_equals', 'key': 'lbl_welcome', 'value': 'Welcome'},
      ],
      'edges': [
        {'action': 'tap', 'key': 'btn_start_shopping', 'target': 'catalog'},
      ],
    },
    {
      'id': 'catalog',
      'route': '/catalog',
      'assertions': [
        {'type': 'widget_exists', 'key': 'list_catalog'},
      ],
    },
  ],
};

void main() {
  test('drafts a module-mirrored graph from a prose test case', () async {
    final provider = FakeLlmProvider(const LlmResult(json: _draftJson));

    final graph = await author(
      'From the dashboard, tap Start Shopping to reach the catalog.',
      provider,
      module: 'shop',
    );

    expect(graph.byId.keys, containsAll(['shop.dashboard', 'shop.catalog']));
    expect(graph.entryNodeIds, ['shop.dashboard']);

    final dashboard = graph.byId['shop.dashboard']!;
    expect(dashboard.identity.route, '/');
    expect(dashboard.identity.anchors, contains('btn_start_shopping'));
    expect(dashboard.payload.assertions.map((a) => a.type),
        containsAll(['widget_exists', 'text_equals']));
    // The edge target is qualified into the module too.
    final edge = dashboard.payload.edges.single;
    expect(edge.action, EdgeAction.tap);
    expect(edge.target, 'shop.catalog');
    expect(edge.key, 'btn_start_shopping');
  });

  test('a text_equals assertion keeps its value in args', () async {
    final graph = await author(
        'welcome screen', FakeLlmProvider(const LlmResult(json: _draftJson)),
        module: 'shop');
    final welcome = graph.byId['shop.dashboard']!.payload.assertions
        .firstWhere((a) => a.type == 'text_equals');
    expect(welcome.args['key'], 'lbl_welcome');
    expect(welcome.args['value'], 'Welcome');
  });

  test('passes the request through the LlmProvider port (provider-agnostic)',
      () async {
    final provider = FakeLlmProvider(const LlmResult(json: {'nodes': []}));
    await author('anything', provider);
    expect(provider.lastRequest, isNotNull);
    expect(provider.lastRequest!.jsonSchema, authorNodeSchema);
  });
}
