import 'dart:typed_data';

import 'package:applens_core/applens_core.dart';

import 'commit_source.dart';

/// Everything triage needs to classify one failed node (ARCHITECTURE.md §12):
/// the failed assertions, a tree diff, the tier-3 diff image (if any), and —
/// the part no screenshot vendor has — the commits touching the node's module
/// since the last green run. Built deterministically from the run record; the
/// LLM only ever sees this.
class EvidencePackage {
  const EvidencePackage({
    required this.nodeId,
    required this.module,
    required this.failedAssertions,
    required this.commits,
    this.route,
    this.treeDiff = '',
    this.diffImage,
    this.isVisual = false,
    this.candidateImageKey,
    this.captureKind = CaptureKind.fullScreen,
  });

  final String nodeId;
  final String module;
  final String? route;

  /// `type: detail` for each assertion that failed (never skipped/passed ones).
  final List<String> failedAssertions;
  final List<Commit> commits;
  final String treeDiff;

  /// The tier-3 red-diff overlay PNG, when this is a visual failure — the image
  /// sent to a vision-capable provider.
  final Uint8List? diffImage;

  /// True when a tier-3 (`visual_match`) assertion failed: triage may propose a
  /// new baseline if it judges the change intended.
  final bool isVisual;

  /// Content address (`sha256:…`) of the drifted capture — the candidate golden
  /// a proposal would adopt. Null when the run recorded no candidate.
  final String? candidateImageKey;
  final CaptureKind captureKind;
}

/// The module a node belongs to is the first segment of its hierarchical id
/// (`shop.dashboard` → `shop`); see ARCHITECTURE.md §5.
String moduleOf(String nodeId) => nodeId.split('.').first;

/// Builds one [EvidencePackage] per failed node in [run] (passed and pending
/// visits are skipped — pending is an already-reviewed change). Pure except for
/// the [commits] lookup, which is the only repo-aware seam.
Future<List<EvidencePackage>> buildEvidence(
  RunRecord run,
  Graph graph,
  CommitSource commits,
) async {
  final packages = <EvidencePackage>[];
  for (final visit in run.visits) {
    if (visit.outcome == NodeOutcome.passed ||
        visit.outcome == NodeOutcome.pending) {
      continue;
    }
    final nodeId = visit.expectedNodeId;
    final node = graph.byId[nodeId];
    final module = moduleOf(nodeId);

    final failed = [
      for (final a in visit.assertions)
        if (!a.passed && !a.skipped)
          a.detail.isEmpty ? a.type : '${a.type}: ${a.detail}',
    ];
    final isVisual = visit.assertions
        .any((a) => a.type == 'visual_match' && !a.passed && !a.skipped);

    final diff = _firstArtifact(visit, 'diff');
    final capture = _firstArtifact(visit, 'capture');
    final tree = _firstArtifact(visit, 'tree');

    packages.add(EvidencePackage(
      nodeId: nodeId,
      module: module,
      route: node?.identity.route,
      failedAssertions: failed,
      commits: await commits.commitsTouchingModule(module),
      treeDiff: tree?.description ?? _synthTreeDiff(visit),
      diffImage: diff?.bytes,
      isVisual: isVisual,
      candidateImageKey: capture?.description,
      captureKind: node?.payload.visualBaselines.isNotEmpty ?? false
          ? node!.payload.visualBaselines.first.capture
          : CaptureKind.fullScreen,
    ));
  }
  return packages;
}

Artifact? _firstArtifact(NodeVisit visit, String kind) {
  for (final a in visit.artifacts) {
    if (a.kind == kind) return a;
  }
  return null;
}

String _synthTreeDiff(NodeVisit visit) {
  final matched = visit.matchedNodeId;
  if (visit.outcome == NodeOutcome.failedHard ||
      visit.outcome == NodeOutcome.blocked) {
    return 'navigation failed: expected ${visit.expectedNodeId}, '
        'matched ${matched ?? "nothing known"}';
  }
  return 'on ${visit.expectedNodeId}, assertions mismatched';
}
