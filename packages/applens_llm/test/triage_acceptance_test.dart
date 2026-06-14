import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:applens_llm/applens_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Session 9 acceptance gate: replay Session 8's scenario (a tier-3 drift on
/// shop.dashboard with a restyle commit in the module) and prove the same
/// EvidencePackage yields the same verdict through ManualProvider (human file
/// round-trip) and a mocked ClaudeProvider — with zero caller changes — and that
/// triage never mutates the run (AI is advisory).

const _verdictJson = {
  'classification': 'intended',
  'confidence': 0.9,
  'reasoning': 'app-bar restyle matches commit abc123',
  'causal_commit': 'abc123',
};

Graph _graph() => Graph(
      nodes: [
        Node(
          id: 'shop.dashboard',
          identity: const NodeIdentity(route: '/dashboard'),
          payload: const NodePayload(
            visualBaselines: [
              VisualBaseline(
                context: BaselineContext(
                    device: 'default', locale: 'en', theme: 'light'),
                capture: CaptureKind.fullScreen,
                state: BaselineState.approved,
                image: 'sha256:old',
              ),
            ],
          ),
        ),
      ],
      entryNodeIds: const ['shop.dashboard'],
    );

RunRecord _run() => RunRecord(
      id: 'r',
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
            AssertionResult(tierOrder: 30, type: 'visual_match', passed: false),
          ],
          artifacts: [
            Artifact(
              kind: 'capture',
              description: 'sha256:newcandidate',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        ),
      ],
    );

const _commits = MapCommitSource({
  'shop': [Commit(ref: 'abc123', summary: 'restyle app bar')],
});

void main() {
  test('same evidence → same verdict through ManualProvider and ClaudeProvider',
      () async {
    final evidence = (await buildEvidence(_run(), _graph(), _commits)).single;

    // ManualProvider: a human drops the verdict file; complete() reads it.
    final dir = Directory.systemTemp.createTempSync('applens_swap_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/verdict.json')
        .writeAsStringSync(jsonEncode(_verdictJson));
    final manual = ManualProvider(
      evidencePath: '${dir.path}/evidence.md',
      verdictPath: '${dir.path}/verdict.json',
      out: StringBuffer(),
    );

    // ClaudeProvider: mocked transport returns the same verdict JSON.
    final claude = ClaudeProvider(
      apiKey: 'sk-test',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': jsonEncode(_verdictJson)},
              ],
              'usage': {'input_tokens': 10, 'output_tokens': 5},
            }),
            200,
          )),
    );

    final viaManual = await classify(evidence, manual, providerName: 'manual');
    final viaClaude = await classify(evidence, claude, providerName: 'claude');

    expect(viaManual.classification, viaClaude.classification);
    expect(viaManual.classification, TriageClass.intended);
    expect(viaManual.causalCommit, viaClaude.causalCommit);
    expect(viaManual.causalCommit, 'abc123');
    expect(viaManual.reasoning, viaClaude.reasoning);
    // Only the provenance label differs — the verdict itself survives the swap.
    expect(viaManual.provider, 'manual');
    expect(viaClaude.provider, 'claude');
  });

  test('triage never mutates the run (advisory; determinism preserved)',
      () async {
    final run = _run();
    final before = jsonEncode(run.toMap());

    await triageRun(run, _graph(), _commits,
        FakeLlmProvider(const LlmResult(json: _verdictJson)));

    expect(jsonEncode(run.toMap()), before);
  });
}
