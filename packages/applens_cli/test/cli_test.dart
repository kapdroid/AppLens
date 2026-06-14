import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:applens_cli/applens_cli.dart';
import 'package:applens_core/applens_core.dart';
import 'package:applens_llm/applens_llm.dart';
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

  test('plan --strategy impact targets only the changed module', () async {
    final (code, output) = await _run([
      'plan',
      _qaGraph,
      '--strategy',
      'impact',
      '--changed-node',
      'shop.cart',
    ]);
    expect(code, 0);
    expect(output, contains('strategy: "impact"'));
    expect(output, contains('shop.cart'));
    expect(output, isNot(contains('shop.confirm'))); // unaffected screen absent
  });

  test('plan --strategy soak fails cleanly (unimplemented), not with a crash',
      () async {
    final (code, output) = await _run(['plan', _qaGraph, '--strategy', 'soak']);
    expect(code, 64);
    expect(output, contains('not implemented'));
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

  test('report on a malformed run.json fails cleanly, not with a stack trace',
      () async {
    final tmp = Directory.systemTemp.createTempSync('applens_badrun_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final bad = '${tmp.path}/run.json';
    File(bad).writeAsStringSync('{"unexpected": "shape"}');

    final (code, output) =
        await _run(['report', _qaGraph, bad, '--out', '${tmp.path}/r.html']);
    expect(code, 1);
    expect(output, contains('run file'));
  });

  test('report on a missing run.json fails cleanly', () async {
    final (code, output) =
        await _run(['report', _qaGraph, '/no/such/run.json']);
    expect(code, 1);
    expect(output, contains('no run file'));
  });

  test('report on a malformed --triage file fails cleanly, not with a crash',
      () async {
    final tmp = Directory.systemTemp.createTempSync('applens_badtriage_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = '${tmp.path}/run.db';
    final store = SqliteRunStore.open(db);
    await store.saveRun(const RunRecord(
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
    ));
    await store.close();
    final triage = '${tmp.path}/triage.json';
    File(triage)
        .writeAsStringSync('[1, 2, 3]'); // an array, not a triage object

    final (code, output) = await _run([
      'report',
      _qaGraph,
      db,
      '--triage',
      triage,
      '--out',
      '${tmp.path}/r.html',
    ]);
    expect(code, 1);
    expect(output, contains('triage file'));
  });

  test('run --dry-run prints the device commands without executing', () async {
    final (code, output) = await _run(['run', _qaGraph, '--dry-run']);
    expect(code, 0);
    expect(output, contains('flutter drive'));
  });

  test('triage writes verdicts + proposals from an injected provider',
      () async {
    final tmp = Directory.systemTemp.createTempSync('applens_triage_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final runJson = '${tmp.path}/run.json';
    File(runJson).writeAsStringSync(jsonEncode(
      RunRecord(
        id: 'run',
        strategy: 'regression',
        graphHash: 'h',
        seed: 0,
        visits: [
          NodeVisit(
            step: 0,
            expectedNodeId: 'shop.dashboard',
            matchedNodeId: 'shop.dashboard',
            outcome: NodeOutcome.failedSoft,
            assertions: const [
              AssertionResult(
                tierOrder: 30,
                type: 'visual_match',
                passed: false,
                detail: '8.4% differ',
              ),
            ],
            artifacts: [
              Artifact(
                kind: 'capture',
                description: 'sha256:cand',
                bytes: Uint8List.fromList([1]),
              ),
            ],
          ),
        ],
      ).toMap(),
    ));

    final triageOut = '${tmp.path}/triage.json';
    final buffer = StringBuffer();
    final code = await AppLensCli(
      out: buffer,
      triageProvider: FakeLlmProvider(const LlmResult(json: {
        'classification': 'intended',
        'confidence': 0.9,
        'reasoning': 'matches restyle abc123',
        'causal_commit': 'abc123',
      })),
      triageCommits: const MapCommitSource({
        'shop': [Commit(ref: 'abc123', summary: 'restyle app bar')],
      }),
    ).run([
      'triage',
      _qaGraph,
      runJson,
      '--provider',
      'fake',
      '--out',
      triageOut
    ]);

    expect(code, 0); // advisory — triage never gates
    expect(buffer.toString(), contains('1 proposal'));

    final report = TriageReport.fromMap(
        jsonDecode(File(triageOut).readAsStringSync()) as Map<String, Object?>);
    expect(report.verdicts.single.classification, TriageClass.intended);
    expect(report.verdicts.single.causalCommit, 'abc123');
    expect(report.verdicts.single.provider, 'fake');
    expect(report.proposals.single.baseline.image, 'sha256:cand');
  });

  test('author drafts a graph YAML from a prose test case', () async {
    final tmp = Directory.systemTemp.createTempSync('applens_author_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final testFile = '${tmp.path}/case.txt';
    File(testFile)
        .writeAsStringSync('From the home screen, tap Start to open settings.');
    final draft = '${tmp.path}/draft.yaml';

    final code = await AppLensCli(
      out: StringBuffer(),
      authorProvider: FakeLlmProvider(const LlmResult(json: {
        'nodes': [
          {
            'id': 'home',
            'route': '/',
            'edges': [
              {'action': 'tap', 'key': 'btn_start', 'target': 'settings'},
            ],
          },
          {'id': 'settings', 'route': '/settings'},
        ],
      })),
    ).run(['author', testFile, '--module', 'app', '--out', draft]);

    expect(code, 0);
    final yaml = File(draft).readAsStringSync();
    expect(yaml, contains('nodes:'));
    expect(yaml, contains('app.home'));
    expect(yaml, contains('app.settings'));
  });

  test('author exits 1 with a message when the provider fails', () async {
    final tmp = Directory.systemTemp.createTempSync('applens_author_fail_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final testFile = '${tmp.path}/case.txt';
    File(testFile).writeAsStringSync('anything');
    final draft = '${tmp.path}/draft.yaml';
    final out = StringBuffer();

    final code = await AppLensCli(
      out: out,
      // A draft missing the required `nodes` key makes author() re-validate and
      // throw LlmException; the command must catch it, not crash the process.
      authorProvider:
          FakeLlmProvider(const LlmResult(json: {'wrong': 'shape'})),
    ).run(['author', testFile, '--module', 'app', '--out', draft]);

    expect(code, 1);
    expect(out.toString(), contains('author failed'));
    expect(File(draft).existsSync(), isFalse); // no draft written on failure
  });

  test('crawl --dry-run prints the device command with crawl defines',
      () async {
    final (code, output) = await _run([
      'crawl',
      '--dry-run',
      '--budget',
      '12',
      '--allow-destructive',
    ]);
    expect(code, 0);
    expect(output, contains('flutter drive'));
    expect(output, contains('APPLENS_CRAWL_BUDGET=12'));
    expect(output, contains('APPLENS_CRAWL_ALLOW_DESTRUCTIVE=true'));
  });

  test('triage without an API key and no injected provider fails cleanly',
      () async {
    final tmp = Directory.systemTemp.createTempSync('applens_triage_nokey_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final runJson = '${tmp.path}/run.json';
    File(runJson).writeAsStringSync(jsonEncode(const RunRecord(
      id: 'run',
      strategy: 'smoke',
      graphHash: 'h',
      seed: 0,
    ).toMap()));

    final (code, output) = await _run([
      'triage',
      _qaGraph,
      runJson,
      '--api-key-env',
      'APPLENS_DEFINITELY_UNSET_KEY',
    ]);
    expect(code, 64);
    expect(output, contains('no API key'));
  });
}
