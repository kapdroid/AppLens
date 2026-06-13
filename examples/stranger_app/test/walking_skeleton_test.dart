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
  testWidgets('walks the stranger graph (smoke) and scrolls the long list', (
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
    expect(
      {for (final v in record.visits) v.matchedNodeId},
      containsAll(['shop.dashboard', 'shop.catalog']),
    );

    // The scroll-into-long-list node, against the real 60-item catalog.
    await driver.scrollTo(const KeySelector('product_40'));
    expect(find.byKey(const Key('product_40')), findsOneWidget);
  });
}
