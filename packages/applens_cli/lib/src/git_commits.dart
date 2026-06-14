import 'dart:io';

import 'package:applens_llm/applens_llm.dart';

/// A [CommitSource] backed by `git log` over the repo at [repoRoot]. For a
/// module it lists commits — since [sinceRef] if given, else over recent
/// history — that touched the module's mapped paths ([modulePaths] from
/// applens.yaml) or, absent a map, any path whose name contains the module
/// (a coarse v1 heuristic; the precise module→path map is a refinement).
///
/// This is the repo-correlation moat (ARCHITECTURE.md §1) — the one input no
/// screenshot vendor has. It feeds the evidence package only; the deterministic
/// core never sees it.
class GitCommitSource implements CommitSource {
  const GitCommitSource({
    this.repoRoot = '.',
    this.sinceRef,
    this.modulePaths = const {},
    this.limit = 50,
  });

  final String repoRoot;
  final String? sinceRef;
  final Map<String, List<String>> modulePaths;
  final int limit;

  static const _unitSep = '\u001f';

  @override
  Future<List<Commit>> commitsTouchingModule(String module) async {
    final paths = modulePaths[module] ?? ['*$module*'];
    final range = sinceRef == null ? 'HEAD' : '$sinceRef..HEAD';
    final ProcessResult result;
    try {
      result = await Process.run('git', [
        '-C',
        repoRoot,
        'log',
        range,
        '--pretty=format:%h$_unitSep%s',
        '-n',
        '$limit',
        '--',
        ...paths,
      ]);
    } on ProcessException {
      return const []; // no git / not a repo — triage degrades to no repo context
    }
    if (result.exitCode != 0) return const [];
    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) return const [];
    return [
      for (final line in stdout.split('\n'))
        if (line.contains(_unitSep))
          Commit(
            ref: line.split(_unitSep).first,
            summary: line.split(_unitSep).last,
          ),
    ];
  }
}
