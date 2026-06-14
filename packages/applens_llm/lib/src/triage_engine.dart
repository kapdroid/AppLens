import 'package:applens_core/applens_core.dart';

import 'commit_source.dart';
import 'degrade.dart';
import 'evidence.dart';
import 'provider.dart';
import 'schema.dart';

/// The schema every triage verdict must validate against — the provider-neutral
/// contract that survives a vendor swap (ARCHITECTURE.md §12).
const triageVerdictSchema = <String, Object?>{
  'type': 'object',
  'required': ['classification', 'confidence', 'reasoning'],
  'properties': {
    'classification': {
      'type': 'string',
      'enum': ['bug', 'intended', 'flake'],
    },
    'confidence': {'type': 'number'},
    'reasoning': {'type': 'string'},
    'causal_commit': {'type': 'string', 'nullable': true},
  },
};

/// The triage prompt, versioned in-repo and provider-neutral (ARCHITECTURE.md
/// §12). Encodes the only judgement that needs repo context: a change a recent
/// commit explains is likely intended; a change nothing explains is likely a bug.
const triageSystemPrompt = '''
You are AppLens triage. A graph-based QA run found a failed UI node in a Flutter
app. Classify the failure as exactly one of:
- "bug": a real regression. Default here when no listed commit plausibly explains
  the observed change.
- "intended": the change matches a recent commit that touched this node's module
  (e.g. a restyle). Cite that commit's ref in causal_commit.
- "flake": looks nondeterministic (transient, timing, animation) and not tied to
  any commit.
You are advisory only — a human makes the final decision. Weigh the failed
assertions, the tree diff, the diff image if attached, and the listed commits.
Set confidence in [0,1]. Reply only with JSON matching the required schema.
''';

/// v1 captures one profile per node at logical resolution (ARCHITECTURE.md §8),
/// so a proposed baseline inherits this default context.
const _defaultContext =
    BaselineContext(device: 'default', locale: 'en', theme: 'light');

/// Classifies one failed node by asking [provider] (any vendor, or a human via
/// ManualProvider). The request degrades to text-only for a no-vision provider.
/// Propagates [LlmException] — the caller decides how a provider failure is
/// handled; AI is advisory, so it must never become a run verdict.
Future<TriageVerdict> classify(
  EvidencePackage evidence,
  LlmProvider provider, {
  String? providerName,
}) async {
  final request = LlmRequest(
    messages: [
      const LlmMessage(LlmRole.system, triageSystemPrompt),
      LlmMessage(
        LlmRole.user,
        _renderEvidence(evidence),
        images: [
          if (evidence.diffImage != null) LlmImage(bytes: evidence.diffImage!),
        ],
      ),
    ],
    jsonSchema: triageVerdictSchema,
  );

  final result = await provider
      .complete(degradeForCapabilities(request, provider.capabilities));
  final json = result.json;
  // Defense in depth: the port says complete() returns schema-valid output, but
  // re-check before the typed reads so a non-validating adapter degrades to an
  // (advisory) LlmException instead of crashing the run with a TypeError.
  final errors = validateAgainstSchema(json, triageVerdictSchema);
  if (errors.isNotEmpty) {
    throw LlmException('triage verdict failed schema: ${errors.join('; ')}');
  }
  return TriageVerdict(
    nodeId: evidence.nodeId,
    classification: TriageClass.fromName(json['classification']! as String) ??
        TriageClass.bug,
    confidence: (json['confidence']! as num).toDouble(),
    reasoning: json['reasoning']! as String,
    causalCommit: json['causal_commit'] as String?,
    provider: providerName,
  );
}

/// Triages every failure in [run]: builds evidence, classifies each node, emits
/// a baseline proposal for any visual failure judged *intended*, and clusters
/// verdicts that share a causal commit. A provider failure on one node drops
/// that node's triage (advisory) without aborting the rest or changing the run.
Future<TriageReport> triageRun(
  RunRecord run,
  Graph graph,
  CommitSource commits,
  LlmProvider provider, {
  String? providerName,
}) async {
  final evidence = await buildEvidence(run, graph, commits);
  final verdicts = <TriageVerdict>[];
  final proposals = <Proposal>[];

  for (final e in evidence) {
    final TriageVerdict verdict;
    try {
      verdict = await classify(e, provider, providerName: providerName);
    } on LlmException {
      continue; // advisory: a failed provider call yields no verdict, never a fail
    }
    verdicts.add(verdict);

    if (verdict.classification == TriageClass.intended &&
        e.isVisual &&
        e.candidateImageKey != null) {
      proposals.add(Proposal(
        nodeId: e.nodeId,
        reasoning: verdict.reasoning,
        baseline: VisualBaseline(
          context: _defaultContext,
          capture: e.captureKind,
          state: BaselineState.proposed,
          image: e.candidateImageKey,
          reasonPr: verdict.causalCommit,
        ),
      ));
    }
  }

  return TriageReport(
      verdicts: clusterByCausalPr(verdicts), proposals: proposals);
}

/// Collapses verdicts that cite the same commit into one cluster (the report
/// renders a cluster as a single confirm card — ARCHITECTURE.md §9). Verdicts
/// with no causal commit are left unclustered.
List<TriageVerdict> clusterByCausalPr(List<TriageVerdict> verdicts) => [
      for (final v in verdicts)
        v.causalCommit == null ? v : v.copyWith(cluster: v.causalCommit),
    ];

String _renderEvidence(EvidencePackage e) {
  final buffer = StringBuffer()
    ..writeln('Node: ${e.nodeId} (module: ${e.module})');
  if (e.route != null) buffer.writeln('Route: ${e.route}');
  buffer
    ..writeln('Visual failure: ${e.isVisual}')
    ..writeln()
    ..writeln('Failed assertions:');
  if (e.failedAssertions.isEmpty) {
    buffer.writeln('  (none recorded)');
  } else {
    for (final a in e.failedAssertions) {
      buffer.writeln('  - $a');
    }
  }
  buffer
    ..writeln()
    ..writeln('Tree diff:')
    ..writeln(e.treeDiff)
    ..writeln()
    ..writeln('Commits touching ${e.module} since last green:');
  if (e.commits.isEmpty) {
    buffer.writeln('  (none — nothing recent explains this change)');
  } else {
    for (final c in e.commits) {
      final files = c.files.isEmpty ? '' : ' [${c.files.join(', ')}]';
      buffer.writeln('  - ${c.ref}: ${c.summary}$files');
    }
  }
  return buffer.toString();
}
