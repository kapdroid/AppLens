import 'package:applens_core/applens_core.dart';
import 'package:applens_crawler/applens_crawler.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted state machine mirroring the stranger app's navigation (its five
/// screens and the taps between them), so the crawler can be exercised headless
/// before the real on-device crawl. Routes and keys match the hand-written
/// qa_graph exactly.
class _Stranger {
  String route = '/';

  static const _transitions = <(String, String), String>{
    ('/', 'btn_start_shopping'): '/catalog',
    ('/', 'btn_view_cart'): '/cart',
    ('/catalog', 'product_0'): '/product',
    ('/product', 'btn_add_to_cart'): '/cart',
    ('/cart', 'btn_place_order'): '/confirm', // destructive: skipped by default
    ('/confirm', 'btn_back_home'): '/',
  };

  static const _keysByRoute = <String, List<String>>{
    '/': ['btn_start_shopping', 'btn_view_cart'],
    '/catalog': ['product_0'],
    '/product': ['btn_add_to_cart'],
    '/cart': ['btn_place_order'],
    '/confirm': ['btn_back_home'],
  };

  void reset() => route = '/';

  void tap(String key) => route = _transitions[(route, key)] ?? route;

  WidgetTreeSnapshot tree() => WidgetTreeSnapshot(
        SerializedWidget(
          type: 'Scaffold',
          children: [
            for (final key in _keysByRoute[route] ?? const <String>[])
              SerializedWidget(type: 'Button', key: key),
          ],
        ),
      );
}

class _FakeDriver implements AppLensDriver {
  _FakeDriver(this._app);
  final _Stranger _app;

  @override
  Future<void> tap(WidgetSelector selector) async =>
      _app.tap((selector as KeySelector).key);

  @override
  Future<WidgetTreeSnapshot> tree() async => _app.tree();

  @override
  Future<void> settle(SettlePolicy policy) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const DriverException('not used by the crawler');
}

class _FakeFingerprint implements FingerprintSource {
  _FakeFingerprint(this._app);
  final _Stranger _app;
  @override
  Future<Fingerprint> capture() async => Fingerprint(route: _app.route);
}

class _StrangerSession implements CrawlSession {
  _StrangerSession() : _app = _Stranger() {
    driver = _FakeDriver(_app);
    fingerprint = _FakeFingerprint(_app);
  }
  final _Stranger _app;
  @override
  late final AppLensDriver driver;
  @override
  late final FingerprintSource fingerprint;
  @override
  Future<void> reset() async => _app.reset();
}

Set<String?> _routes(Graph graph) =>
    {for (final n in graph.nodes) n.identity.route};

Node _node(String id, String route) => Node(
      id: id,
      identity: NodeIdentity(route: route),
      payload: const NodePayload(),
    );

void main() {
  test('crawls ≥80% of the stranger screens, skipping destructive actions',
      () async {
    final result = await crawl(_StrangerSession(), module: 'shop');

    // 4 of the 5 hand-written screens are reachable without a destructive tap
    // (/confirm sits behind btn_place_order). 4/5 = 80%.
    final routes = _routes(result.graph);
    expect(routes, containsAll(<String>['/', '/catalog', '/product', '/cart']));
    expect(routes, isNot(contains('/confirm')));
    expect(result.skippedDestructive, contains('btn_place_order'));
    expect(result.statesDiscovered, 4);
  });

  test('allowDestructive reaches the confirmation screen (5/5)', () async {
    final result =
        await crawl(_StrangerSession(), allowDestructive: true, module: 'shop');
    expect(_routes(result.graph), contains('/confirm'));
    expect(result.statesDiscovered, 5);
  });

  test('proposes tap edges between discovered screens', () async {
    final result = await crawl(_StrangerSession(), module: 'shop');
    final dashboard =
        result.graph.nodes.firstWhere((n) => n.identity.route == '/');
    final keys = dashboard.payload.edges.map((e) => e.key).toSet();
    expect(keys, containsAll(<String>['btn_start_shopping', 'btn_view_cart']));
    // /cart is reached from both dashboard and product → one clustered node.
    expect(result.graph.nodes.where((n) => n.identity.route == '/cart'),
        hasLength(1));
  });

  test('the draft graph is well-formed (one entry, all edge targets exist)',
      () async {
    final result = await crawl(_StrangerSession(), module: 'shop');
    expect(result.graph.entryNodeIds, hasLength(1));
    final ids = result.graph.byId.keys.toSet();
    for (final node in result.graph.nodes) {
      for (final edge in node.payload.edges) {
        expect(ids, contains(edge.target));
      }
    }
  });

  test('the budget caps how many states are discovered', () async {
    final result = await crawl(_StrangerSession(),
        budget: const CrawlBudget(maxStates: 2), allowDestructive: true);
    expect(result.statesDiscovered, lessThanOrEqualTo(3));
  });

  test('drift detection surfaces screens missing from the approved graph', () {
    final discovered = Graph(
        nodes: [_node('app.a', '/'), _node('app.b', '/catalog')],
        entryNodeIds: const ['app.a']);
    final approved = Graph(
        nodes: [_node('shop.dashboard', '/')],
        entryNodeIds: const ['shop.dashboard']);

    final drift = driftReport(discovered, approved);
    expect(drift.hasDrift, isTrue);
    expect(drift.newRoutes, contains('/catalog'));
  });

  test('no drift when the crawl matches the approved routes', () {
    final g = Graph(nodes: [_node('a', '/')], entryNodeIds: const ['a']);
    expect(driftReport(g, g).hasDrift, isFalse);
  });
}
