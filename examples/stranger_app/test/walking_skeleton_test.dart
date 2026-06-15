// The walking skeleton, proven headless: AppLens walks the stranger app's graph
// end-to-end against the real widgets via the first-party driver. The on-device
// variant is integration_test/applens_entry.dart (same orchestrator wiring).
import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  testWidgets('walks the 11-node graph (smoke) across all three modules', (
    tester,
  ) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();

    final driver = appLensWidgetDriver(tester);
    final graph = loadGraph('qa_graph');
    expect(validateGraph(graph).where((d) => d.isError), isEmpty);

    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    final record = await Orchestrator(
      driver: driver,
      fingerprints: WidgetFingerprintSource(driver, observer),
      store: InMemoryRunStore(),
    ).run(graph, plan);

    expect(
      record.visits.every((v) => v.outcome == NodeOutcome.passed),
      isTrue,
      reason: record.visits
          .map(
              (v) => '${v.expectedNodeId}:${v.outcome.name}:${v.matchedNodeId}')
          .join(', '),
    );
    // Smoke now reaches every module — shop, account (via the cross-module
    // login → profile path), and support.
    expect(
      {for (final v in record.visits) v.matchedNodeId},
      containsAll([
        'shop.dashboard',
        'shop.catalog',
        'account.profile',
        'support.help',
      ]),
    );
  });

  testWidgets('the driver scrolls into the long catalog list', (tester) async {
    await tester.pumpWidget(StrangerApp(cart: CartModel()));
    await tester.pumpAndSettle();
    final driver = appLensWidgetDriver(tester);

    await driver.tap(const KeySelector('btn_start_shopping'));
    await tester.pumpAndSettle();
    await driver.scrollTo(const KeySelector('product_40'));
    expect(find.byKey(const Key('product_40')), findsOneWidget);
  });

  testWidgets('the product detail screen reports its named route', (
    tester,
  ) async {
    // onGenerateRoute must forward `settings:` so the pushed route keeps its
    // name — otherwise the NavigatorObserver sees a null route and shop.product
    // (identity route /product) can never match. Smoke never reaches product
    // (it's not a `routes:` entry), so only a soak/regression walk exposes this.
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();
    final driver = appLensWidgetDriver(tester);

    await driver.tap(const KeySelector('btn_start_shopping'));
    await tester.pumpAndSettle();
    await driver.tap(const KeySelector('product_0'));
    await tester.pumpAndSettle();

    final fp = await WidgetFingerprintSource(driver, observer).capture();
    expect(fp.route, '/product', reason: 'the generated route must be named');
    expect(fp.anchors, containsAll(['btn_add_to_cart', 'lbl_product_name']));
  });

  testWidgets('the filled cart is flag-distinguished and backs to the product',
      (
    tester,
  ) async {
    // Adding a product opens the filled cart: cart_count inference is > 0 (so it
    // matches shop.cart, not shop.cart_empty), and because the only way in is a
    // product's "add to cart", back pops to that product.
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();
    final driver = appLensWidgetDriver(tester);
    final fingerprints = WidgetFingerprintSource(
      driver,
      observer,
      flags: const UiInferenceFlagSource(
        [CountProbe('cart_count', 'cart_item_')],
      ),
    );

    await driver.tap(const KeySelector('btn_start_shopping'));
    await tester.pumpAndSettle();
    await driver.tap(const KeySelector('product_0'));
    await tester.pumpAndSettle();
    await driver.tap(const KeySelector('btn_add_to_cart'));
    await tester.pumpAndSettle();

    final filled = await fingerprints.capture();
    expect(filled.route, '/cart');
    expect(filled.anchors,
        containsAll(['list_cart_items', 'btn_place_order', 'lbl_total']));
    expect(filled.flags['cart_count'], '1', reason: 'one item added');

    await driver.back();
    await tester.pumpAndSettle();
    final afterBack = await fingerprints.capture();
    expect(afterBack.route, '/product', reason: 'back pops to the product');
  });

  group('cross-path state reset (onPathStart)', () {
    // Path 1 adds a product (fills the cart); path 2 backs out and views the
    // cart from the dashboard, expecting the empty-cart node. Without a reset
    // the leaked item makes path 2 land on the filled cart; with it, the cart
    // is cleared between paths and the empty-cart node matches.
    Plan fillThenCheckEmpty(Graph graph) => Plan(
          strategy: PlanStrategy.soak,
          graphHash: graph.contentHash,
          seed: 0,
          paths: [
            PlanPath(start: 'shop.dashboard', steps: const [
              PlanStep(
                  action: EdgeAction.tap,
                  to: 'shop.catalog',
                  key: 'btn_start_shopping'),
              PlanStep(
                  action: EdgeAction.tap, to: 'shop.product', key: 'product_0'),
              PlanStep(
                  action: EdgeAction.tap,
                  to: 'shop.cart',
                  key: 'btn_add_to_cart'),
            ]),
            PlanPath(start: 'shop.dashboard', steps: const [
              PlanStep(
                  action: EdgeAction.tap,
                  to: 'shop.cart_empty',
                  key: 'btn_view_cart'),
            ]),
          ],
        );

    Future<RunRecord> walk(WidgetTester tester, {required bool reset}) async {
      final observer = AppLensNavigatorObserver();
      final cart = CartModel();
      await tester.pumpWidget(
        StrangerApp(cart: cart, navigatorObservers: [observer]),
      );
      await tester.pumpAndSettle();
      final driver = appLensWidgetDriver(tester);
      final graph = loadGraph('qa_graph');
      return Orchestrator(
        driver: driver,
        fingerprints: WidgetFingerprintSource(
          driver,
          observer,
          flags: const UiInferenceFlagSource(
            [CountProbe('cart_count', 'cart_item_')],
          ),
        ),
        store: InMemoryRunStore(),
        onPathStart: reset ? () => cart.clear() : null,
      ).run(graph, fillThenCheckEmpty(graph));
    }

    testWidgets('without it, a prior path leaks cart state (the bug)',
        (tester) async {
      final record = await walk(tester, reset: false);
      final cartEmpty = record.visits
          .firstWhere((v) => v.expectedNodeId == 'shop.cart_empty');
      expect(cartEmpty.outcome, isNot(NodeOutcome.passed),
          reason: 'the leaked item makes it match the filled cart');
      expect(cartEmpty.matchedNodeId, 'shop.cart');
    });

    testWidgets('with it, the cart is cleared and the empty cart matches',
        (tester) async {
      final record = await walk(tester, reset: true);
      expect(
        record.visits.every((v) => v.outcome == NodeOutcome.passed),
        isTrue,
        reason: record.visits
            .map((v) =>
                '${v.expectedNodeId}:${v.outcome.name}:${v.matchedNodeId}')
            .join(', '),
      );
    });
  });

  testWidgets('the action engine enters text into the login form', (
    tester,
  ) async {
    await tester.pumpWidget(StrangerApp(cart: CartModel()));
    await tester.pumpAndSettle();
    final driver = appLensWidgetDriver(tester);

    await driver.tap(const KeySelector('btn_account'));
    await tester.pumpAndSettle();
    await driver.enterText(const KeySelector('field_username'), 'alex');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'alex'), findsOneWidget);
  });
}
