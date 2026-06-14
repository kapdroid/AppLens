// AppLens crawl host for the stranger app (Gate C).
//
// Runs headless under `flutter test integration_test/applens_crawl_entry.dart`
// and, with `-d <device>`, on a real emulator via `applens crawl` — the same
// re-pump CrawlSession the headless test (test/crawl_skeleton_test.dart) proves.
// Crawl parameters arrive as the dart-defines `applens crawl` passes; the draft
// graph and drift are transported to the host through the integration_test
// driver's reportData. The draft is a PR a human prunes — never auto-merged.
import 'package:applens_core/applens_core.dart';
import 'package:applens_crawler/applens_crawler.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

/// Drives the real [StrangerApp] for the crawler. [reset] re-pumps a fresh app
/// (unmounting first so the new Navigator starts at its initialRoute, not the
/// prior route stack) with a fresh observer. Mirrors the headless
/// test/crawl_skeleton_test.dart session so the device run is confirmation.
class _StrangerCrawlSession implements CrawlSession {
  _StrangerCrawlSession(this.tester) : driver = appLensWidgetDriver(tester);

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
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [_observer]),
    );
    await tester.pumpAndSettle();
  }
}

// Crawl parameters arrive as dart-defines `applens crawl` passes (a const
// context is required to read a define; wrapping each in a function keeps the
// call-site value non-const so it isn't mistaken for a redundant default).
String _module() =>
    const String.fromEnvironment('APPLENS_CRAWL_MODULE', defaultValue: 'shop');
int _budget() =>
    const int.fromEnvironment('APPLENS_CRAWL_BUDGET', defaultValue: 40);
int _depth() =>
    const int.fromEnvironment('APPLENS_CRAWL_DEPTH', defaultValue: 8);
bool _allowDestructive() =>
    const bool.fromEnvironment('APPLENS_CRAWL_ALLOW_DESTRUCTIVE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppLens crawls the stranger app into a draft graph',
      (tester) async {
    final allowDestructive = _allowDestructive();
    final result = await crawl(
      _StrangerCrawlSession(tester),
      module: _module(),
      budget: CrawlBudget(maxStates: _budget(), maxDepth: _depth()),
      allowDestructive: allowDestructive,
    );

    // Drift vs the approved graph (bundled as assets so the on-device run can
    // load it without the host filesystem). The graph-YAML files load as strings.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = <String, String>{
      for (final key in manifest
          .listAssets()
          .where((a) => a.startsWith('qa_graph/') && a.endsWith('.yaml')))
        key: await rootBundle.loadString(key),
    };
    final approved = loadGraph('qa_graph', files: MapGraphFiles(files));
    final drift = driftReport(result.graph, approved);

    // Transport the draft + drift to the host (`flutter drive` writes it out).
    // The draft is a proposal a human reviews — this entrypoint never writes the
    // graph directory.
    binding.reportData = <String, dynamic>{
      'draft_graph': result.graph.toMap(),
      'states_discovered': result.statesDiscovered,
      'actions_tried': result.actionsTried,
      'skipped_destructive': result.skippedDestructive,
      'drift': <String, dynamic>{
        'has_drift': drift.hasDrift,
        'new_routes': drift.newRoutes,
        'new_actions': drift.newActions,
      },
    };

    // The crawl mechanism worked against the real app: it discovered distinct
    // screens and (by default) declined the destructive checkout (§11).
    expect(result.statesDiscovered, greaterThanOrEqualTo(3));
    expect(result.graph.entryNodeIds, hasLength(1));
    if (!allowDestructive) {
      expect(result.skippedDestructive, contains('btn_place_order'));
    }
  });
}
