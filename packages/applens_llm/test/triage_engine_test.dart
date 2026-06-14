import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';
import 'package:applens_llm/applens_llm.dart';
import 'package:test/test.dart';

/// A provider that actually reads the evidence text — proving the evidence
/// package carries the repo context, not just that the pipeline runs. Mimics a
/// model following the prompt: a change a commit explains is `intended` (citing
/// it); a change nothing explains is `bug`.
class _EvidenceAwareProvider implements LlmProvider {
  _EvidenceAwareProvider({this.capabilities = _vision});

  static const _vision =
      LlmCapabilities(vision: true, jsonMode: true, maxContextTokens: 1000000);

  @override
  final LlmCapabilities capabilities;

  LlmRequest? lastRequest;

  @override
  Future<LlmResult> complete(LlmRequest request) async {
    lastRequest = request;
    final evidence = request.messages.last.text;
    // Read only the commits section, the way a model would weigh repo context.
    final commitsSection = evidence.split('Commits touching').elementAt(1);
    if (commitsSection.contains('(none — nothing recent')) {
      return const LlmResult(json: {
        'classification': 'bug',
        'confidence': 0.9,
        'reasoning': 'no recent commit explains this change',
      });
    }
    final ref = RegExp(r'  - (\w+):').firstMatch(commitsSection)?.group(1);
    return LlmResult(json: {
      'classification': 'intended',
      'confidence': 0.85,
      'reasoning': 'matches commit $ref',
      'causal_commit': ref,
    });
  }
}

class _ThrowingProvider implements LlmProvider {
  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(vision: true, jsonMode: true, maxContextTokens: 1);

  @override
  Future<LlmResult> complete(LlmRequest request) async =>
      throw const LlmException('provider down');
}

Node _node(String id, {String? route, bool visual = false}) => Node(
      id: id,
      identity: NodeIdentity(route: route),
      payload: NodePayload(
        visualBaselines: visual
            ? const [
                VisualBaseline(
                  context: BaselineContext(
                      device: 'default', locale: 'en', theme: 'light'),
                  capture: CaptureKind.fullScreen,
                  state: BaselineState.approved,
                  image: 'sha256:old',
                ),
              ]
            : const [],
      ),
    );

Graph _graph() => Graph(
      nodes: [
        _node('shop.dashboard', route: '/dashboard', visual: true),
        _node('shop.catalog', route: '/catalog'),
      ],
      entryNodeIds: const ['shop.dashboard'],
    );

NodeVisit _visualFailure(String nodeId) => NodeVisit(
      step: 0,
      expectedNodeId: nodeId,
      matchedNodeId: nodeId,
      outcome: NodeOutcome.failedSoft,
      assertions: const [
        AssertionResult(
          tierOrder: 30,
          type: 'visual_match',
          passed: false,
          detail: '8.4% of pixels differ',
        ),
      ],
      artifacts: [
        Artifact(
          kind: 'diff',
          description: 'tier-3 diff',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        Artifact(
          kind: 'capture',
          description: 'sha256:newcandidate',
          bytes: Uint8List.fromList([4, 5, 6]),
        ),
      ],
    );

RunRecord _run(List<NodeVisit> visits) => RunRecord(
      id: 'r1',
      strategy: 'regression',
      graphHash: 'h',
      seed: 1,
      visits: visits,
    );

void main() {
  group('buildEvidence', () {
    test('builds one package per failure, skipping passed/pending visits',
        () async {
      final run = _run([
        const NodeVisit(
          step: 0,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.passed,
        ),
        _visualFailure('shop.catalog'),
        const NodeVisit(
          step: 2,
          expectedNodeId: 'shop.dashboard',
          matchedNodeId: 'shop.dashboard',
          outcome: NodeOutcome.pending,
        ),
      ]);

      final evidence =
          await buildEvidence(run, _graph(), const MapCommitSource({}));

      expect(evidence, hasLength(1));
      expect(evidence.single.nodeId, 'shop.catalog');
      expect(evidence.single.module, 'shop');
    });

    test('pulls diff/capture artifacts, commits, and visual flag', () async {
      final run = _run([_visualFailure('shop.dashboard')]);
      final commits = const MapCommitSource({
        'shop': [Commit(ref: 'abc123', summary: 'restyle app bar')],
      });

      final e = (await buildEvidence(run, _graph(), commits)).single;

      expect(e.isVisual, isTrue);
      expect(e.diffImage, isNotNull);
      expect(e.candidateImageKey, 'sha256:newcandidate');
      expect(e.route, '/dashboard');
      expect(e.commits.single.ref, 'abc123');
    });
  });

  group('classify', () {
    test('maps a schema-valid verdict onto the failed node', () async {
      final e = (await buildEvidence(
        _run([_visualFailure('shop.dashboard')]),
        _graph(),
        const MapCommitSource({
          'shop': [Commit(ref: 'abc123', summary: 'restyle')],
        }),
      ))
          .single;

      final verdict =
          await classify(e, _EvidenceAwareProvider(), providerName: 'fake');

      expect(verdict.nodeId, 'shop.dashboard');
      expect(verdict.classification, TriageClass.intended);
      expect(verdict.causalCommit, 'abc123');
      expect(verdict.provider, 'fake');
    });

    test('degrades to text-only for a no-vision provider', () async {
      final e = (await buildEvidence(
        _run([_visualFailure('shop.dashboard')]),
        _graph(),
        const MapCommitSource({
          'shop': [Commit(ref: 'abc123', summary: 'restyle')],
        }),
      ))
          .single;
      final provider = _EvidenceAwareProvider(
        capabilities: const LlmCapabilities(
            vision: false, jsonMode: true, maxContextTokens: 1000),
      );

      await classify(e, provider);

      final sentImages =
          provider.lastRequest!.messages.expand((m) => m.images).toList();
      expect(sentImages, isEmpty); // the diff image was stripped
    });
  });

  group('triageRun', () {
    test('intended visual failure with a candidate emits a proposal', () async {
      final report = await triageRun(
        _run([_visualFailure('shop.dashboard')]),
        _graph(),
        const MapCommitSource({
          'shop': [Commit(ref: 'abc123', summary: 'restyle')],
        }),
        _EvidenceAwareProvider(),
        providerName: 'fake',
      );

      expect(report.verdicts.single.classification, TriageClass.intended);
      expect(report.proposals, hasLength(1));
      final proposal = report.proposals.single;
      expect(proposal.nodeId, 'shop.dashboard');
      expect(proposal.baseline.state, BaselineState.proposed);
      expect(proposal.baseline.image, 'sha256:newcandidate');
      expect(proposal.baseline.reasonPr, 'abc123');
    });

    test('a failure with no related commit classifies as a bug, no proposal',
        () async {
      final report = await triageRun(
        _run([_visualFailure('shop.dashboard')]),
        _graph(),
        const MapCommitSource({}), // no commits touched the module
        _EvidenceAwareProvider(),
      );

      expect(report.verdicts.single.classification, TriageClass.bug);
      expect(report.proposals, isEmpty);
    });

    test('verdicts citing the same commit are clustered together', () async {
      final report = await triageRun(
        _run(
            [_visualFailure('shop.dashboard'), _visualFailure('shop.catalog')]),
        _graph(),
        const MapCommitSource({
          'shop': [Commit(ref: 'abc123', summary: 'restyle app bar')],
        }),
        _EvidenceAwareProvider(),
      );

      expect(report.verdicts, hasLength(2));
      expect(report.verdicts.every((v) => v.cluster == 'abc123'), isTrue);
    });

    test('a provider failure drops that node\'s triage, never throws',
        () async {
      final report = await triageRun(
        _run([_visualFailure('shop.dashboard')]),
        _graph(),
        const MapCommitSource({}),
        _ThrowingProvider(),
      );

      expect(report.verdicts, isEmpty);
      expect(report.proposals, isEmpty);
    });
  });
}
