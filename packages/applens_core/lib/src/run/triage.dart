import '../model/assertion.dart';

/// How triage classifies a failure (ARCHITECTURE.md §12). The classification is
/// *advisory* — it pre-sorts the report and may emit a proposal, but a human
/// makes the only decision. It never changes a run's pass/fail verdict.
enum TriageClass {
  /// A real regression — the change was not intended.
  bug,

  /// An intended change (e.g. a restyle PR) — triage may propose a new baseline.
  intended,

  /// Nondeterministic; not reproducible on retry.
  flake;

  static TriageClass? fromName(String value) {
    for (final c in TriageClass.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}

/// One triage verdict for a failed node — the `triage_verdicts` row (§13).
/// [causalCommit] is the correlated commit the model cited; [cluster] groups
/// verdicts sharing a cause so the report collapses them to one card. AI is
/// advisory: [overturned] records when a human's decision differed (the tracked
/// overturn-rate metric, §9).
class TriageVerdict {
  const TriageVerdict({
    required this.nodeId,
    required this.classification,
    required this.confidence,
    required this.reasoning,
    this.causalCommit,
    this.cluster,
    this.provider,
    this.overturned = false,
  });

  final String nodeId;
  final TriageClass classification;
  final double confidence;
  final String reasoning;
  final String? causalCommit;
  final String? cluster;

  /// Which adapter produced this verdict (e.g. `manual`, `claude`) — provenance
  /// for the overturn-rate metric, never a gating input.
  final String? provider;
  final bool overturned;

  TriageVerdict copyWith({String? cluster, bool? overturned}) => TriageVerdict(
        nodeId: nodeId,
        classification: classification,
        confidence: confidence,
        reasoning: reasoning,
        causalCommit: causalCommit,
        cluster: cluster ?? this.cluster,
        provider: provider,
        overturned: overturned ?? this.overturned,
      );

  Map<String, Object?> toMap() => {
        'node_id': nodeId,
        'classification': classification.name,
        'confidence': confidence,
        'reasoning': reasoning,
        if (causalCommit != null) 'causal_commit': causalCommit,
        if (cluster != null) 'cluster': cluster,
        if (provider != null) 'provider': provider,
        'overturned': overturned,
      };

  factory TriageVerdict.fromMap(Map<String, Object?> map) => TriageVerdict(
        nodeId: map['node_id']! as String,
        classification:
            TriageClass.fromName(map['classification']! as String) ??
                TriageClass.bug,
        confidence: (map['confidence']! as num).toDouble(),
        reasoning: map['reasoning']! as String,
        causalCommit: map['causal_commit'] as String?,
        cluster: map['cluster'] as String?,
        provider: map['provider'] as String?,
        overturned: map['overturned'] as bool? ?? false,
      );
}

/// A candidate new golden written by triage for a failure it classified
/// *intended* (ARCHITECTURE.md §9). It lives in the run store — never in node
/// YAML — until a human confirms it, at which point the sidecar applies the YAML
/// mutation and opens the guarded PR. The [baseline] is a [VisualBaseline] in
/// the `proposed` state, loaded through the same content-addressed source as
/// approved goldens.
class Proposal {
  const Proposal({
    required this.nodeId,
    required this.baseline,
    this.reasoning = '',
  });

  final String nodeId;
  final VisualBaseline baseline;
  final String reasoning;

  Map<String, Object?> toMap() => {
        'node_id': nodeId,
        'baseline': baseline.toMap(),
        'reasoning': reasoning,
      };

  factory Proposal.fromMap(Map<String, Object?> map) => Proposal(
        nodeId: map['node_id']! as String,
        baseline: VisualBaseline.fromMap(
            (map['baseline']! as Map).cast<String, Object?>()),
        reasoning: map['reasoning'] as String? ?? '',
      );
}

/// The output of `applens triage` for a run: the per-node verdicts and any
/// baseline proposals, plus the human-overturn rate over verdicts a human has
/// since decided on. Written as `triage.json` alongside `run.json`; read by the
/// report. Triage produces only this — proposals and verdicts, never a verdict
/// that gates the run.
class TriageReport {
  const TriageReport({
    this.verdicts = const [],
    this.proposals = const [],
  });

  final List<TriageVerdict> verdicts;
  final List<Proposal> proposals;

  /// Human-overturn rate (§9: above ~10%, fix the evidence package, not the
  /// policy). [overturned] is set when a human's confirm decision differed from
  /// the verdict, so on a fresh run — before any human has decided — this is 0.
  double get overturnRate {
    if (verdicts.isEmpty) return 0;
    return verdicts.where((v) => v.overturned).length / verdicts.length;
  }

  Map<String, Object?> toMap() => {
        'verdicts': [for (final v in verdicts) v.toMap()],
        'proposals': [for (final p in proposals) p.toMap()],
      };

  factory TriageReport.fromMap(Map<String, Object?> map) => TriageReport(
        verdicts: [
          for (final v in (map['verdicts'] as List? ?? const []))
            TriageVerdict.fromMap((v as Map).cast<String, Object?>()),
        ],
        proposals: [
          for (final p in (map['proposals'] as List? ?? const []))
            Proposal.fromMap((p as Map).cast<String, Object?>()),
        ],
      );
}
