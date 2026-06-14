import 'dart:io';
import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips an artifact binary payload (the diff PNG) through SQLite',
      () async {
    final store = SqliteRunStore.inMemory();
    addTearDown(store.close);
    final bytes = Uint8List.fromList([0, 255, 1, 254, 128, 7]);

    await store.saveRun(
      RunRecord(
        id: 'r',
        strategy: 'regression',
        graphHash: 'h',
        seed: 0,
        visits: [
          NodeVisit(
            step: 0,
            expectedNodeId: 'a',
            matchedNodeId: 'a',
            outcome: NodeOutcome.failedSoft,
            artifacts: [
              Artifact(kind: 'diff', description: 'red diff', bytes: bytes),
            ],
          ),
        ],
      ),
    );

    final loaded = await store.loadRun('r');
    final artifact = loaded!.visits.single.artifacts.single;
    expect(artifact.bytes, bytes); // not dropped
  });

  test('SqliteRunStore round-trips a run record through the schema', () async {
    final store = SqliteRunStore.inMemory();
    addTearDown(store.close);

    const record = RunRecord(
      id: 'run-1',
      strategy: 'smoke',
      graphHash: 'sha256:abc',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
          assertions: [
            AssertionResult(tierOrder: 10, type: 'widget_exists', passed: true),
          ],
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'shop.cart',
          matchedNodeId: 'shop.cart',
          outcome: NodeOutcome.failedSoft,
          assertions: [
            AssertionResult(
              tierOrder: 10,
              type: 'widget_exists',
              passed: false,
              detail: 'key "btn_place_order" not present',
            ),
          ],
          artifacts: [Artifact(kind: 'tree', description: 'root=MaterialApp')],
        ),
      ],
    );

    await store.saveRun(record);
    final loaded = await store.loadRun('run-1');

    expect(loaded, isNotNull);
    expect(loaded!.strategy, 'smoke');
    expect(loaded.graphHash, 'sha256:abc');
    expect(loaded.visits, hasLength(2));
    expect(loaded.visits[1].outcome, NodeOutcome.failedSoft);
    expect(loaded.visits[1].assertions.single.passed, isFalse);
    expect(loaded.visits[1].artifacts.single.kind, 'tree');
    expect(await store.loadRun('missing'), isNull);
  });

  test('persists to a file and survives a reopen (the CI artifact path)',
      () async {
    final dir = Directory.systemTemp.createTempSync('applens_runstore_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/run.db';

    final writer = SqliteRunStore.open(path);
    await writer.saveRun(
      const RunRecord(
        id: 'r',
        strategy: 'smoke',
        graphHash: 'h',
        seed: 0,
        visits: [
          NodeVisit(
            step: 0,
            expectedNodeId: 'A',
            matchedNodeId: 'A',
            outcome: NodeOutcome.passed,
          ),
        ],
      ),
    );
    await writer.close();

    final reader = SqliteRunStore.open(path);
    addTearDown(reader.close);
    final loaded = await reader.loadRun('r');
    expect(loaded?.visits.single.outcome, NodeOutcome.passed);
  });
}
