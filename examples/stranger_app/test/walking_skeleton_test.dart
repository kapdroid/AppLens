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
  testWidgets('walks the 10-node graph (smoke) across all three modules', (
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
