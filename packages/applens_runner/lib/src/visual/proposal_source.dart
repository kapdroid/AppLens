import 'package:applens_core/applens_core.dart';

/// Open (unconfirmed) baseline proposals, keyed by node id. A proposal is a
/// candidate new golden written by triage when a tier-3 mismatch looks
/// *intended* (ARCHITECTURE.md §9) — it lives in the run store, never in node
/// YAML, until a human confirms it. Each entry is a [VisualBaseline] in the
/// `proposed` state whose content-addressed image is loaded through the same
/// [BaselineSource] as approved goldens.
///
/// A run compares a tier-3 capture against the approved baseline *and* these:
/// matching an open proposal is `pending` (yellow, not a regression); matching
/// neither is red. So a known, reviewed-pending change never masks a real one.
abstract interface class ProposalSource {
  Future<List<VisualBaseline>> openProposalsFor(String nodeId);
}
