import 'dart:io';

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

  test('the crawl is deterministic: same app → byte-identical draft', () async {
    String draft(Graph g) => g.toMap().toString();
    final first = await crawl(_StrangerSession(), module: 'shop');
    final second = await crawl(_StrangerSession(), module: 'shop');
    expect(draft(first.graph), draft(second.graph));
  });

  test('the scripted model still covers the real shop-module routes', () {
    // Guards against the in-test mirror drifting from the hand-written fixture:
    // every non-destructive-gated shop route the real graph declares must be one
    // the crawl can reach. The mirror models the shop flow specifically, so the
    // guard scopes to the shop module (loaded from the repo so a fixture edit to
    // the shop screens fails loudly).
    final root = _repoDirContaining('examples/stranger_app/qa_graph');
    final real = loadGraph('${root.path}/examples/stranger_app/qa_graph');
    final shopRoutes = {
      for (final n in real.nodes)
        if (n.id.startsWith('shop.') && n.identity.route != null)
          n.identity.route!,
    }..remove('/confirm'); // only reachable via the destructive btn_place_order

    final mirrorRoutes = _Stranger._keysByRoute.keys.toSet();
    expect(mirrorRoutes, containsAll(shopRoutes));
  });

  test('destructive matching is tokenized: benign keys are still crawled', () {
    // btn_reorder contains "order" and btn_transfer contains a real keyword;
    // only the genuinely destructive one is skipped.
    final session = _ScriptSession(_ScriptApp(
      initial: 's0',
      routeOf: {'s0': '/home', 's1': '/list'},
      keysOf: {
        's0': ['btn_reorder', 'btn_transfer'],
        's1': [],
      },
      transitions: {('s0', 'btn_reorder'): 's1'},
    ));

    return crawl(session).then((result) {
      expect(result.skippedDestructive, contains('btn_transfer'));
      expect(result.skippedDestructive, isNot(contains('btn_reorder')));
      expect(_routes(result.graph), contains('/list')); // reorder was explored
    });
  });

  test('destructive matching splits letter/digit boundaries (btn2pay)', () {
    final session = _ScriptSession(_ScriptApp(
      initial: 's0',
      routeOf: {'s0': '/home'},
      keysOf: {
        's0': ['btn2pay', 'open_filters'],
      },
      transitions: const {},
    ));
    return crawl(session).then((result) {
      // "pay" surfaces from btn2pay via the digit boundary; open_filters does not.
      expect(result.skippedDestructive, contains('btn2pay'));
      expect(result.skippedDestructive, isNot(contains('open_filters')));
    });
  });

  test('hybrid: long keywords match glued lowercase, short ones stay tokenized',
      () {
    // Fully-glued all-lowercase keys: a long keyword (submit/delete) is caught
    // as a substring, but a short one (order/buy) and a substring-risk one
    // (wipe ⊂ swipe) are not, so benign keys stay crawlable.
    final session = _ScriptSession(_ScriptApp(
      initial: 's0',
      routeOf: {'s0': '/home'},
      keysOf: {
        's0': ['submitform', 'deleteall', 'reorder', 'buyer', 'swipecard'],
      },
      transitions: const {},
    ));
    return crawl(session).then((result) {
      expect(
          result.skippedDestructive, containsAll(['submitform', 'deleteall']));
      for (final benign in ['reorder', 'buyer', 'swipecard']) {
        expect(result.skippedDestructive, isNot(contains(benign)));
      }
    });
  });

  test('hybrid: multi-token keyword derivatives are not false-positives', () {
    // Well-formed camelCase keys whose tokens merely derive from a keyword
    // (confirmationNumber → confirmation, submittedAt → submitted) tokenize into
    // multiple words, so the substring pass must NOT fire — they stay crawlable.
    final session = _ScriptSession(_ScriptApp(
      initial: 's0',
      routeOf: {'s0': '/home'},
      keysOf: {
        's0': [
          'confirmationNumber',
          'submittedAt',
          'deletedItemsBadge',
          'cancelledOrdersTab',
        ],
      },
      transitions: const {},
    ));
    return crawl(session).then((result) {
      expect(result.skippedDestructive, isEmpty);
    });
  });

  test('distinct states never collapse onto one node id', () {
    // Three states; the third shares route /x with the first but has a
    // different tree, and its generated id would collide with the second's
    // (/x_2) under naive suffixing.
    final session = _ScriptSession(_ScriptApp(
      initial: 's0',
      routeOf: {'s0': '/x', 's1': '/x_2', 's2': '/x'},
      keysOf: {
        's0': ['go1'],
        's1': ['go2'],
        's2': [],
      },
      transitions: {('s0', 'go1'): 's1', ('s1', 'go2'): 's2'},
    ));

    return crawl(session, module: 'm').then((result) {
      expect(result.statesDiscovered, 3);
      // No two distinct states collapsed: every state has its own node id.
      expect(result.graph.byId.length, 3);
      expect(result.graph.nodes.map((n) => n.id).toSet(), hasLength(3));
    });
  });
}

/// A general scripted app keyed by an internal state id (so two states can share
/// a route yet stay distinct), used to exercise crawler edge cases.
class _ScriptApp {
  _ScriptApp({
    required this.initial,
    required this.routeOf,
    required this.keysOf,
    required this.transitions,
  }) : state = initial;

  final String initial;
  final Map<String, String> routeOf;
  final Map<String, List<String>> keysOf;
  final Map<(String, String), String> transitions;
  String state;

  void reset() => state = initial;
  void tap(String key) => state = transitions[(state, key)] ?? state;
  String get route => routeOf[state]!;

  WidgetTreeSnapshot tree() => WidgetTreeSnapshot(
        SerializedWidget(
          type: 'S_$state', // state id in the type → distinct tree per state
          children: [
            for (final key in keysOf[state] ?? const <String>[])
              SerializedWidget(type: 'Button', key: key),
          ],
        ),
      );
}

class _ScriptDriver implements AppLensDriver {
  _ScriptDriver(this._app);
  final _ScriptApp _app;
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

class _ScriptFp implements FingerprintSource {
  _ScriptFp(this._app);
  final _ScriptApp _app;
  @override
  Future<Fingerprint> capture() async => Fingerprint(route: _app.route);
}

class _ScriptSession implements CrawlSession {
  _ScriptSession(this._app) {
    driver = _ScriptDriver(_app);
    fingerprint = _ScriptFp(_app);
  }
  final _ScriptApp _app;
  @override
  late final AppLensDriver driver;
  @override
  late final FingerprintSource fingerprint;
  @override
  Future<void> reset() async => _app.reset();
}

Directory _repoDirContaining(String relative) {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/$relative').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('cannot locate "$relative"');
    }
    dir = parent;
  }
}
