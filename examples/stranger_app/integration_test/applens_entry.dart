// AppLens runner host for the stranger app (the walking skeleton).
//
// Runs headless under `flutter test integration_test/applens_entry.dart` and,
// with `-d <device>`, on a real emulator — the same code, the Tier-0 contract.
import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppLens walks the stranger graph (smoke)', (tester) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();

    final driver = appLensWidgetDriver(tester);
    final graph = loadGraph('qa_graph');
    expect(
      validateGraph(graph).where((d) => d.isError),
      isEmpty,
      reason: 'the graph must validate before a run',
    );

    final plan = compilePlan(graph, strategy: PlanStrategy.smoke);
    final orchestrator = Orchestrator(
      driver: driver,
      fingerprints: WidgetFingerprintSource(driver, observer),
      store: InMemoryRunStore(),
    );
    final record = await orchestrator.run(graph, plan);

    // Every smoke-tagged node was reached and verified.
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

    // Scroll into the long catalog list against the real app (the gate's
    // scroll-into-long-list node).
    await driver.scrollTo(const KeySelector('product_40'));
    expect(find.byKey(const Key('product_40')), findsOneWidget);
  });
}
