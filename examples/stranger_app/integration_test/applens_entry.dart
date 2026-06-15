// AppLens runner host for the stranger app (the walking skeleton).
//
// Runs headless under `flutter test integration_test/applens_entry.dart` and,
// with `-d <device>`, on a real emulator — the same code, the Tier-0 contract.
import 'dart:convert';

import 'package:applens_core/applens_core.dart';
import 'package:applens_runner/applens_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stranger_app/cart_model.dart';
import 'package:stranger_app/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppLens walks the stranger graph (smoke)', (tester) async {
    final observer = AppLensNavigatorObserver();
    await tester.pumpWidget(
      StrangerApp(cart: CartModel(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();

    final driver = appLensWidgetDriver(tester);
    // On-device the host filesystem is unavailable, so load qa_graph from the
    // bundled assets (declared in pubspec.yaml) into an in-memory file tree.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest.listAssets().where((a) => a.startsWith('qa_graph/'));
    // Graph YAML loads as strings; goldens load as bytes — loadString on a PNG
    // would corrupt it, so the two are split here.
    final files = <String, String>{
      for (final key in assets.where((a) =>
          !a.startsWith('qa_graph/goldens/') &&
          !a.startsWith('qa_graph/structural/')))
        key: await rootBundle.loadString(key),
    };
    final goldens = <String, Uint8List>{
      for (final key in assets.where((a) => a.startsWith('qa_graph/goldens/')))
        'sha256:${key.split('/').last.replaceAll('.png', '')}':
            (await rootBundle.load(key)).buffer.asUint8List(),
    };
    // Tier-2.5 semantic snapshots (text + geometry), bundled as JSON.
    final structural = <String?, StructuralSnapshot>{
      for (final key
          in assets.where((a) => a.startsWith('qa_graph/structural/')))
        'sha256:${key.split('/').last.replaceAll('.json', '')}':
            StructuralSnapshot.fromMap(
                jsonDecode(await rootBundle.loadString(key))
                    as Map<String, Object?>),
    };
    final graph = loadGraph('qa_graph', files: MapGraphFiles(files));
    expect(
      validateGraph(graph).where((d) => d.isError),
      isEmpty,
      reason: 'the graph must validate before a run',
    );

    // Strategy/seed/soak budget come from `applens run` as dart-defines, so the
    // same host runs smoke, regression, impact, or a seeded soak on the device.
    const strategyName =
        String.fromEnvironment('APPLENS_STRATEGY', defaultValue: 'smoke');
    const seed = int.fromEnvironment('APPLENS_SEED');
    const soakSteps =
        int.fromEnvironment('APPLENS_SOAK_STEPS', defaultValue: 40);
    // seed/soakSteps arrive as dart-defines at build time; the analyzer can't
    // see the override and flags them as matching defaults, hence the ignores.
    final plan = compilePlan(
      graph,
      strategy: PlanStrategy.fromYaml(strategyName) ?? PlanStrategy.smoke,
      // ignore: avoid_redundant_argument_values
      seed: seed,
      // ignore: avoid_redundant_argument_values
      soakSteps: soakSteps,
    );
    final orchestrator = Orchestrator(
      driver: driver,
      fingerprints: WidgetFingerprintSource(driver, observer),
      store: InMemoryRunStore(),
      // Tier 3: compare tagged nodes against the bundled goldens. captureContext
      // is null so any approved baseline matches (single-profile v1).
      baselines: MapBaselineSource(goldens),
      // Tier 2.5: diff watched widgets' text + geometry against the snapshots.
      structuralBaselines: MapStructuralBaselineSource(structural),
    );
    final record = await orchestrator.run(graph, plan);

    // Always transport the run to the host (the `flutter drive` driver writes
    // run.json) — a failing run must still reach `applens report`, whose exit
    // code is the verdict. The assertions below check only that the walk
    // *mechanism* worked, not the per-node pass/fail (that's the report's job).
    binding.reportData = <String, dynamic>{'run': record.toMap()};

    expect(
      {for (final v in record.visits) v.matchedNodeId},
      containsAll(['shop.dashboard', 'shop.catalog']),
      reason: record.visits
          .map(
              (v) => '${v.expectedNodeId}:${v.outcome.name}:${v.matchedNodeId}')
          .join(', '),
    );

    // Scroll into the long catalog list against the real app (the gate's
    // scroll-into-long-list node). Reach the catalog from a fresh launch first —
    // the multi-path walk leaves the app on its last path's screen, not the
    // catalog (mirrors the headless scroll test).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(StrangerApp(cart: CartModel()));
    await tester.pumpAndSettle();
    await driver.tap(const KeySelector('btn_start_shopping'));
    await driver.settle(const SettlePolicy());
    await driver.scrollTo(const KeySelector('product_40'));
    expect(find.byKey(const Key('product_40')), findsOneWidget);
  });
}
