// The crawler, proven headless: AppLens explores the real stranger app and
// proposes a draft graph via a re-pump CrawlSession. The on-device variant is
// integration_test/applens_crawl_entry.dart (the same session wiring). This
// proves the device glue — not just the scripted-mirror engine tests — works
// against real widgets (constitution: headless-testable first, device confirms).
import 'package:applens_crawler/applens_crawler.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

/// Drives a real [StrangerApp] for the crawler. [reset] re-pumps a fresh app —
/// the in-test equivalent of the device session relaunching under `flutter
/// drive` — with a fresh [AppLensNavigatorObserver] so the route probe restarts
/// clean. The crawl reads `driver`/`fingerprint` after each reset, so the
/// fingerprint always uses the current observer.
class StrangerCrawlSession implements CrawlSession {
  StrangerCrawlSession(this.tester) : driver = appLensWidgetDriver(tester);

  final WidgetTester tester;

  @override
  final AppLensDriver driver;

  AppLensNavigatorObserver _observer = AppLensNavigatorObserver();

  @override
  FingerprintSource get fingerprint =>
      WidgetFingerprintSource(driver, _observer);

  @override
  Future<void> reset() async {
    _observer = AppLensNavigatorObserver();
    // Unmount the previous tree first: re-pumping the same StrangerApp widget
    // type reuses the MaterialApp/Navigator element and would preserve the prior
    // route stack, so the fresh app must mount from scratch to land on its
    // initialRoute (the launch state every replay starts from).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [_observer]),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('crawls the real stranger app into a well-formed draft graph', (
    tester,
  ) async {
    final result = await crawl(
      StrangerCrawlSession(tester),
      module: 'shop',
      budget: const CrawlBudget(maxStates: 8, maxDepth: 4),
    );

    final routes = {for (final n in result.graph.nodes) n.identity.route};
    // It discovered real, distinct screens off the home screen.
    expect(routes, containsAll(<String>['/', '/catalog', '/cart']));
    expect(result.statesDiscovered, greaterThanOrEqualTo(3));

    // The destructive checkout on /cart was seen and declined (§11) — so the
    // crawl never reached the confirmation screen behind it.
    expect(result.skippedDestructive, contains('btn_place_order'));
    expect(routes, isNot(contains('/confirm')));

    // The draft is well-formed: one entry, every edge target is a real node.
    expect(result.graph.entryNodeIds, hasLength(1));
    final ids = result.graph.byId.keys.toSet();
    for (final node in result.graph.nodes) {
      for (final edge in node.payload.edges) {
        expect(ids, contains(edge.target));
      }
    }
  });
}
