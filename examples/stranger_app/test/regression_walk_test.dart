// Regression EXECUTION, proven headless: walking every edge of the stranger
// graph against the real widgets must end green. This is the first time the
// regression strategy is *executed* (not just compiled) — it exposed two real
// orchestrator bugs on the device (a `back` landing on a non-canonical
// predecessor, and return-to-start not unwinding cross-module navigation). This
// test reproduces them headless so the fix is proven test-first.
import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:applens_sdk/applens_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  testWidgets('a regression walk covers every edge and ends all-green',
      (tester) async {
    final observer = AppLensNavigatorObserver();
    final cart = CartModel();
    await tester.pumpWidget(
      StrangerApp(cart: cart, navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();

    final driver = appLensWidgetDriver(tester);
    final graph = loadGraph('qa_graph');
    final plan = compilePlan(graph, strategy: PlanStrategy.regression);

    final record = await Orchestrator(
      driver: driver,
      fingerprints: WidgetFingerprintSource(
        driver,
        observer,
        flags: const UiInferenceFlagSource(
          [CountProbe('cart_count', 'cart_item_')],
        ),
      ),
      store: InMemoryRunStore(),
      onPathStart: () {
        AppLensState.reset();
        cart.clear();
      },
    ).run(graph, plan);

    final bad = record.visits
        .where((v) => v.outcome != NodeOutcome.passed)
        .map((v) => '${v.expectedNodeId}:${v.outcome.name}:${v.matchedNodeId}')
        .toList();
    expect(bad, isEmpty, reason: 'non-passing visits: ${bad.join(', ')}');
  });
}
