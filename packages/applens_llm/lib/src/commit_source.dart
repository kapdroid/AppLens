/// A commit that touched a node's module, for repo-aware triage
/// (ARCHITECTURE.md §1/§12 — "the moat"). [ref] is the short sha or PR ref the
/// report and verdict cite.
class Commit {
  const Commit({
    required this.ref,
    required this.summary,
    this.files = const [],
  });

  final String ref;
  final String summary;
  final List<String> files;
}

/// The seam where repo context enters triage: the commits touching a module
/// since the last green run. The deterministic core never sees this — it feeds
/// the evidence package only. An IO adapter shells `git log` (later); tests and
/// keyless runs use [MapCommitSource].
abstract interface class CommitSource {
  Future<List<Commit>> commitsTouchingModule(String module);
}

/// A scripted [CommitSource] for tests and for runs without a git checkout:
/// returns the commits registered for a module, or none.
class MapCommitSource implements CommitSource {
  const MapCommitSource(this._byModule);

  final Map<String, List<Commit>> _byModule;

  @override
  Future<List<Commit>> commitsTouchingModule(String module) async =>
      _byModule[module] ?? const [];
}
