import 'dart:convert';

import 'package:applens_core/applens_core.dart';
import 'package:test/test.dart';

void main() {
  group('TriageVerdict', () {
    test('round-trips through JSON', () {
      const verdict = TriageVerdict(
        nodeId: 'shop.dashboard',
        classification: TriageClass.intended,
        confidence: 0.86,
        reasoning: 'app-bar restyle; commit abc123 touched theme.dart',
        causalCommit: 'abc123',
        cluster: 'abc123',
        provider: 'claude',
      );

      final back = TriageVerdict.fromMap(
          jsonDecode(jsonEncode(verdict.toMap())) as Map<String, Object?>);

      expect(back.nodeId, 'shop.dashboard');
      expect(back.classification, TriageClass.intended);
      expect(back.confidence, 0.86);
      expect(back.causalCommit, 'abc123');
      expect(back.cluster, 'abc123');
      expect(back.provider, 'claude');
      expect(back.overturned, isFalse);
    });

    test('defaults a missing/unknown classification to bug (fail safe)', () {
      final back = TriageVerdict.fromMap(const {
        'node_id': 'x',
        'classification': 'nonsense',
        'confidence': 0.1,
        'reasoning': 'r',
      });
      expect(back.classification, TriageClass.bug);
    });
  });

  group('Proposal', () {
    test('round-trips with its proposed VisualBaseline', () {
      const proposal = Proposal(
        nodeId: 'shop.dashboard',
        baseline: VisualBaseline(
          context: BaselineContext(device: 'pixel', locale: 'en', theme: 'l'),
          capture: CaptureKind.fullScreen,
          state: BaselineState.proposed,
          image: 'sha256:deadbeef',
          reasonPr: 'https://github.com/x/y/pull/9',
        ),
        reasoning: 'matches restyle',
      );

      final back = Proposal.fromMap(
          jsonDecode(jsonEncode(proposal.toMap())) as Map<String, Object?>);

      expect(back.nodeId, 'shop.dashboard');
      expect(back.baseline.state, BaselineState.proposed);
      expect(back.baseline.capture, CaptureKind.fullScreen);
      expect(back.baseline.image, 'sha256:deadbeef');
      expect(back.baseline.reasonPr, 'https://github.com/x/y/pull/9');
      expect(back.reasoning, 'matches restyle');
    });
  });

  group('VisualBaseline.fromMap', () {
    test('throws on an unknown state/capture rather than coercing', () {
      expect(
        () => VisualBaseline.fromMap(const {
          'context': {'device': 'd', 'locale': 'l', 'theme': 't'},
          'capture': 'full_screen',
          'state': 'aproved', // typo
        }),
        throwsFormatException,
      );
      expect(
        () => VisualBaseline.fromMap(const {
          'context': {'device': 'd', 'locale': 'l', 'theme': 't'},
          'capture': 'bogus',
          'state': 'approved',
        }),
        throwsFormatException,
      );
    });
  });

  group('TriageReport', () {
    test('round-trips verdicts + proposals and computes overturn rate', () {
      const report = TriageReport(
        verdicts: [
          TriageVerdict(
            nodeId: 'a',
            classification: TriageClass.bug,
            confidence: 0.9,
            reasoning: 'no related commit',
            overturned: true,
          ),
          TriageVerdict(
            nodeId: 'b',
            classification: TriageClass.intended,
            confidence: 0.8,
            reasoning: 'restyle',
          ),
        ],
      );

      expect(report.overturnRate, 0.5);

      final back = TriageReport.fromMap(
          jsonDecode(jsonEncode(report.toMap())) as Map<String, Object?>);
      expect(back.verdicts, hasLength(2));
      expect(back.verdicts.first.overturned, isTrue);
      expect(back.overturnRate, 0.5);
    });

    test('a fresh report (no human decisions) has overturn rate 0', () {
      expect(const TriageReport().overturnRate, 0);
    });
  });
}
