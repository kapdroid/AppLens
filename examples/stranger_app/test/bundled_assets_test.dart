// Guards the device asset path: the on-device entrypoints load qa_graph from the
// bundled assets (not the host filesystem), so an incomplete `assets:` list in
// pubspec.yaml — e.g. a module added without bundling its node files — makes the
// device graph dangle even though the filesystem-loading headless tests pass.
// Loading via the same AssetManifest path here catches that in the gate.
import 'package:applens_core/applens_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the bundled qa_graph assets load and validate', (tester) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = <String, String>{
      for (final key in manifest
          .listAssets()
          .where((a) => a.startsWith('qa_graph/') && a.endsWith('.yaml')))
        key: await rootBundle.loadString(key),
    };

    final graph = loadGraph('qa_graph', files: MapGraphFiles(files));
    // Every module the graph references must be bundled, or cross-module edges
    // dangle (the bug a stale `assets:` list caused on device).
    expect(
      validateGraph(graph).where((d) => d.isError),
      isEmpty,
      reason: 'bundled assets are incomplete — add the missing module to '
          'pubspec.yaml assets',
    );
    // All three modules (shop + account + support) are bundled — including
    // both /cart states (empty + filled), the eleventh node.
    expect(graph.nodes, hasLength(11));
    expect(
      {for (final n in graph.nodes) n.id.split('.').first},
      containsAll(<String>['shop', 'account', 'support']),
    );
  });
}
