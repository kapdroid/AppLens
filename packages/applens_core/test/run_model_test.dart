import 'dart:convert';
import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

void main() {
  test('Artifact carries binary payload across the JSON transport (base64)',
      () {
    final diff = Uint8List.fromList([0, 255, 1, 254, 128, 7]);
    final artifact =
        Artifact(kind: 'diff', description: '3px differ', bytes: diff);

    final round = Artifact.fromMap(
      (jsonDecode(jsonEncode(artifact.toMap())) as Map).cast<String, Object?>(),
    );

    expect(round.kind, 'diff');
    expect(round.description, '3px differ');
    expect(round.bytes, equals(diff));
  });

  test('RunRecord round-trips through toMap/fromMap and JSON', () {
    const record = RunRecord(
      id: 'r',
      strategy: 'smoke',
      graphHash: 'sha256:h',
      seed: 0,
      visits: [
        NodeVisit(
          step: 0,
          expectedNodeId: 'a',
          matchedNodeId: 'a',
          outcome: NodeOutcome.passed,
          assertions: [
            AssertionResult(tierOrder: 10, type: 'widget_exists', passed: true),
          ],
        ),
        NodeVisit(
          step: 1,
          expectedNodeId: 'b',
          matchedNodeId: null,
          outcome: NodeOutcome.failedHard,
          artifacts: [Artifact(kind: 'tree', description: 'root=X')],
        ),
      ],
    );

    // The device→host transport: encode to JSON, decode, rebuild.
    final json = jsonEncode(record.toMap());
    final round = RunRecord.fromMap(
      (jsonDecode(json) as Map).cast<String, Object?>(),
    );

    expect(round.id, 'r');
    expect(round.graphHash, 'sha256:h');
    expect(round.visits, hasLength(2));
    expect(round.visits[0].assertions.single.type, 'widget_exists');
    expect(round.visits[1].matchedNodeId, isNull);
    expect(round.visits[1].outcome, NodeOutcome.failedHard);
    expect(round.visits[1].artifacts.single.kind, 'tree');
  });
}
