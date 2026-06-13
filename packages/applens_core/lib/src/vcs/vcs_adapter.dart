/// The seam over a hosted VCS (GitHub / GitLab / Azure DevOps). v1 ships a
/// GitHub implementation (Session 8); the port exists from Session 0 so every
/// later session builds against an unmovable target.
///
/// AppLens never lets the host decide a merge: the [MergeGuard] is evaluated
/// in-process so the auto-merge rule stays deterministic and auditable.
abstract interface class VcsAdapter {
  /// Opens a pull request for [draft] and returns the created [PullRequest].
  Future<PullRequest> openPr(PrDraft draft);

  /// Merges [pr] only if [guard] permits the set of files the PR changes.
  Future<MergeResult> mergeIfGuardPasses(PullRequest pr, MergeGuard guard);
}

/// An immutable description of a pull request to open.
class PrDraft {
  const PrDraft({
    required this.title,
    required this.body,
    required this.headBranch,
    this.baseBranch = 'main',
    this.labels = const <String>[],
  });

  final String title;
  final String body;
  final String headBranch;
  final String baseBranch;
  final List<String> labels;
}

/// An immutable handle to an opened pull request.
class PullRequest {
  const PullRequest({
    required this.number,
    required this.url,
    required this.headBranch,
    required this.baseBranch,
    this.isOpen = true,
  });

  final int number;
  final Uri url;
  final String headBranch;
  final String baseBranch;
  final bool isOpen;
}

/// The outcome of a guarded merge attempt.
enum MergeOutcome { merged, guardRejected, conflict, blocked }

/// An immutable result of [VcsAdapter.mergeIfGuardPasses].
class MergeResult {
  const MergeResult(this.outcome, {this.detail = ''});

  final MergeOutcome outcome;

  /// Human-facing explanation, empty on a clean merge.
  final String detail;

  bool get merged => outcome == MergeOutcome.merged;
}

/// A deterministic predicate over the files a PR changes. AppLens evaluates the
/// guard itself rather than delegating to the host. The canonical v1 guard
/// (Session 8) permits a merge only when every changed path is a visual
/// baseline entry or a golden file.
abstract interface class MergeGuard {
  /// Whether a PR whose diff touches exactly [changedPaths] may auto-merge.
  bool permits(Iterable<String> changedPaths);
}
