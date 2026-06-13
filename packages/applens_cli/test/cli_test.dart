import 'dart:io';

import 'package:applens_cli/applens_cli.dart';
import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

Directory _repoDirContaining(String relative) {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/$relative').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('cannot locate "$relative"');
    }
    dir = parent;
  }
}

final String _qaGraph =
    '${_repoDirContaining('examples/stranger_app/qa_graph').path}'
    '/examples/stranger_app/qa_graph';

Future<(int, String)> _run(List<String> args) async {
  final out = StringBuffer();
  final code = await AppLensCli(out: out).run(args);
  return (code, out.toString());
}

void main() {
  test('validate accepts the stranger graph', () async {
    final (code, output) = await _run(['validate', _qaGraph]);
    expect(code, 0);
    expect(output, contains('✓ valid'));
  });

  test('plan compiles a smoke plan to YAML', () async {
    final (code, output) =
        await _run(['plan', _qaGraph, '--strategy', 'smoke']);
    expect(code, 0);
    expect(output, contains('strategy:'));
    expect(output, contains('graph_hash:'));
  });

  test('graph stats reports counts and the module', () async {
    final (code, output) = await _run(['graph', 'stats', _qaGraph]);
    expect(code, 0);
    expect(output, contains('nodes:'));
    expect(output, contains('shop:'));
  });

  test('graph find filters by tag', () async {
    final (code, output) = await _run([
      'graph',
      'find',
      _qaGraph,
      '--tag',
      'sanity',
    ]);
    expect(code, 0);
    expect(output, contains('shop.dashboard'));
  });

  test('graph path shows a shortest path', () async {
    final (code, output) = await _run([
      'graph',
      'path',
      _qaGraph,
      'shop.dashboard',
      'shop.confirm',
    ]);
    expect(code, 0);
    expect(output, contains('shop.dashboard ->'));
    expect(output, contains('shop.confirm'));
  });

  test('init scaffolds qa_graph, applens.yaml, and the entrypoint', () async {
    final tmp = Directory.systemTemp.createTempSync('applens_init_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (code, _) = await _run(['init', tmp.path]);
    expect(code, 0);
    expect(File('${tmp.path}/qa_graph/applens.yaml').existsSync(), isTrue);
    expect(
      File('${tmp.path}/integration_test/applens_entry.dart').existsSync(),
      isTrue,
    );
  });

  test('report renders HTML from a run store and returns the exit code',
      () async {
    final tmp = Directory.systemTemp.createTempSync('applens_report_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = '${tmp.path}/run.db';
    final html = '${tmp.path}/report.html';

    final store = SqliteRunStore.open(db);
    await store.saveRun(
      const RunRecord(
        id: 'run',
        strategy: 'smoke',
        graphHash: 'h',
        seed: 0,
        visits: [
          NodeVisit(
            step: 0,
            expectedNodeId: 'shop.dashboard',
            matchedNodeId: 'shop.dashboard',
            outcome: NodeOutcome.passed,
          ),
        ],
      ),
    );
    await store.close();

    final (code, output) = await _run(['report', _qaGraph, db, '--out', html]);
    expect(code, 0); // all passed → green
    expect(output, contains('✓ wrote'));
    expect(File(html).readAsStringSync(), contains('AppLens run report'));
  });

  test('report surfaces exit 1 on a red run', () async {
    final tmp = Directory.systemTemp.createTempSync('applens_report_red_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = '${tmp.path}/run.db';
    final store = SqliteRunStore.open(db);
    await store.saveRun(
      const RunRecord(
        id: 'run',
        strategy: 'smoke',
        graphHash: 'h',
        seed: 0,
        visits: [
          NodeVisit(
            step: 0,
            expectedNodeId: 'shop.cart',
            matchedNodeId: 'shop.cart',
            outcome: NodeOutcome.failedSoft,
            assertions: [
              AssertionResult(
                tierOrder: 10,
                type: 'widget_exists',
                passed: false,
                detail: 'missing',
              ),
            ],
          ),
        ],
      ),
    );
    await store.close();
    final (code, _) = await _run([
      'report',
      _qaGraph,
      db,
      '--out',
      '${tmp.path}/r.html',
    ]);
    expect(code, 1);
  });

  test('run --dry-run prints the device commands without executing', () async {
    final (code, output) = await _run(['run', _qaGraph, '--dry-run']);
    expect(code, 0);
    expect(output, contains('flutter test'));
  });
}
